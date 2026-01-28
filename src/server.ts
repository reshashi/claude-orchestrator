/**
 * HTTP API Server
 *
 * Fastify-based HTTP and WebSocket server for the orchestrator.
 * Enables Moltbot and other clients to interact with the orchestrator via REST API.
 */

import Fastify, { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import fastifyWebsocket from '@fastify/websocket';
import fastifyCors from '@fastify/cors';
import * as path from 'node:path';
import * as os from 'node:os';
import type { WebSocket } from 'ws';

import { Orchestrator } from './orchestrator.js';
import { StateManager } from './state-manager.js';
import type { Logger, WorkerEvent, PersistedWorkerState } from './types.js';

export interface ServerConfig {
  port: number;
  host: string;
  logger: Logger;
  orchestrator?: Orchestrator;
}

export interface ApiWorkerResponse {
  id: string;
  state: string;
  config: {
    repoName: string;
    worktreePath: string;
    branchName: string;
    task: string;
    createdAt: string;
  };
  pid: number | null;
  prNumber: number | null;
  prUrl: string | null;
  lastActivity: string;
  error: string | null;
  reviewStatus: string;
  agentsRun: string[];
}

// Convert persisted state to API response format
function toApiResponse(state: PersistedWorkerState): ApiWorkerResponse {
  return {
    id: state.id,
    state: state.state,
    config: {
      repoName: state.config.repoName,
      worktreePath: state.config.worktreePath,
      branchName: state.config.branchName,
      task: state.config.task,
      createdAt: typeof state.config.createdAt === 'string'
        ? state.config.createdAt
        : new Date(state.config.createdAt).toISOString(),
    },
    pid: state.pid,
    prNumber: state.prNumber,
    prUrl: state.prUrl,
    lastActivity: state.lastActivity,
    error: state.error,
    reviewStatus: state.reviewStatus,
    agentsRun: state.agentsRun,
  };
}

export async function createServer(config: ServerConfig): Promise<FastifyInstance> {
  const { logger } = config;

  // Create Fastify instance
  const fastify = Fastify({
    logger: false, // We use our own logger
  });

  // Register plugins
  await fastify.register(fastifyCors, {
    origin: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  });

  await fastify.register(fastifyWebsocket);

  // State management
  const workersDir = path.join(os.homedir(), '.claude', 'workers');
  const stateManager = new StateManager({ workersDir, logger });
  await stateManager.initialize();

  // Orchestrator (create if not provided)
  let orchestrator = config.orchestrator;
  if (!orchestrator) {
    orchestrator = new Orchestrator({ logger });
    await orchestrator.initialize();
  }

  // WebSocket connections for real-time updates
  const wsClients = new Set<WebSocket>();

  // Broadcast event to all WebSocket clients
  function broadcast(event: WorkerEvent | { type: string; [key: string]: unknown }): void {
    const message = JSON.stringify(event);
    for (const client of wsClients) {
      if (client.readyState === 1) { // OPEN
        client.send(message);
      }
    }
  }

  // Forward orchestrator events to WebSocket clients
  orchestrator.on('worker_event', (event: WorkerEvent) => {
    broadcast(event);
  });

  // ==========================================
  // Health Check
  // ==========================================

  fastify.get('/api/health', async (_request: FastifyRequest, reply: FastifyReply) => {
    const workers = await stateManager.loadAllWorkerStates();
    const activeCount = workers.filter(w =>
      !['MERGED', 'STOPPED', 'ERROR'].includes(w.state)
    ).length;

    return reply.send({
      status: 'healthy',
      version: '3.1.0',
      activeWorkers: activeCount,
      totalWorkers: workers.length,
      timestamp: new Date().toISOString(),
    });
  });

  // ==========================================
  // Workers API
  // ==========================================

  // List all workers
  interface ListWorkersQuery {
    all?: string;
  }

  fastify.get<{ Querystring: ListWorkersQuery }>(
    '/api/workers',
    async (request, reply) => {
      const showAll = request.query.all === 'true';
      const workers = await stateManager.loadAllWorkerStates();

      const filtered = showAll
        ? workers
        : workers.filter(w => !['MERGED', 'STOPPED'].includes(w.state));

      return reply.send(filtered.map(toApiResponse));
    }
  );

  // Get worker by ID
  interface GetWorkerParams {
    id: string;
  }

  fastify.get<{ Params: GetWorkerParams }>(
    '/api/workers/:id',
    async (request, reply) => {
      const { id } = request.params;
      const state = await stateManager.loadWorkerState(id);

      if (!state) {
        return reply.status(404).send({ error: `Worker '${id}' not found` });
      }

      return reply.send(toApiResponse(state));
    }
  );

  // Spawn new worker
  interface SpawnWorkerBody {
    name: string;
    task: string;
    repo?: string;
  }

  fastify.post<{ Body: SpawnWorkerBody }>(
    '/api/workers',
    async (request, reply) => {
      const { name, task, repo } = request.body;

      if (!name || !task) {
        return reply.status(400).send({
          error: 'Missing required fields: name and task',
        });
      }

      // Check if worker already exists
      if (await stateManager.workerExists(name)) {
        return reply.status(409).send({
          error: `Worker '${name}' already exists`,
        });
      }

      try {
        const worker = await orchestrator!.spawn(name, task, repo);

        broadcast({
          type: 'worker_spawned',
          workerId: worker.config.id,
          state: worker.state,
        });

        return reply.status(201).send({
          id: worker.config.id,
          state: worker.state,
          config: {
            repoName: worker.config.repoName,
            worktreePath: worker.config.worktreePath,
            branchName: worker.config.branchName,
            task: worker.config.task,
            createdAt: worker.config.createdAt.toISOString(),
          },
          pid: worker.pid,
        });
      } catch (err) {
        logger.error('Failed to spawn worker', { error: String(err) });
        return reply.status(500).send({
          error: `Failed to spawn worker: ${err}`,
        });
      }
    }
  );

  // Get worker output
  interface GetOutputParams {
    id: string;
  }

  interface GetOutputQuery {
    lines?: string;
  }

  fastify.get<{ Params: GetOutputParams; Querystring: GetOutputQuery }>(
    '/api/workers/:id/output',
    async (request, reply) => {
      const { id } = request.params;
      const lines = parseInt(request.query.lines ?? '50', 10);

      const state = await stateManager.loadWorkerState(id);
      if (!state) {
        return reply.status(404).send({ error: `Worker '${id}' not found` });
      }

      const output = await stateManager.readOutputLog(id, lines);
      return reply.send({ output });
    }
  );

  // Send message to worker
  interface SendMessageParams {
    id: string;
  }

  interface SendMessageBody {
    message: string;
  }

  fastify.post<{ Params: SendMessageParams; Body: SendMessageBody }>(
    '/api/workers/:id/send',
    async (request, reply) => {
      const { id } = request.params;
      const { message } = request.body;

      if (!message) {
        return reply.status(400).send({ error: 'Missing required field: message' });
      }

      const state = await stateManager.loadWorkerState(id);
      if (!state) {
        return reply.status(404).send({ error: `Worker '${id}' not found` });
      }

      try {
        await orchestrator!.sendMessage(id, message);

        broadcast({
          type: 'message_sent',
          workerId: id,
          message,
        });

        return reply.send({ success: true });
      } catch (err) {
        return reply.status(500).send({
          error: `Failed to send message: ${err}`,
        });
      }
    }
  );

  // Stop worker
  interface StopWorkerParams {
    id: string;
  }

  fastify.post<{ Params: StopWorkerParams }>(
    '/api/workers/:id/stop',
    async (request, reply) => {
      const { id } = request.params;

      const state = await stateManager.loadWorkerState(id);
      if (!state) {
        return reply.status(404).send({ error: `Worker '${id}' not found` });
      }

      try {
        await orchestrator!.stopWorker(id);

        broadcast({
          type: 'worker_stopped',
          workerId: id,
        });

        return reply.send({ success: true, state: 'STOPPED' });
      } catch (err) {
        return reply.status(500).send({
          error: `Failed to stop worker: ${err}`,
        });
      }
    }
  );

  // Merge worker's PR
  interface MergeWorkerParams {
    id: string;
  }

  fastify.post<{ Params: MergeWorkerParams }>(
    '/api/workers/:id/merge',
    async (request, reply) => {
      const { id } = request.params;

      const state = await stateManager.loadWorkerState(id);
      if (!state) {
        return reply.status(404).send({ error: `Worker '${id}' not found` });
      }

      if (!state.prNumber) {
        return reply.status(400).send({ error: `Worker '${id}' has no PR to merge` });
      }

      try {
        const success = await orchestrator!.triggerMerge(id);

        if (success) {
          broadcast({
            type: 'pr_merged',
            workerId: id,
            prNumber: state.prNumber,
          });
        }

        return reply.send({ merged: success });
      } catch (err) {
        return reply.status(500).send({
          error: `Failed to merge PR: ${err}`,
        });
      }
    }
  );

  // Delete/cleanup worker
  interface DeleteWorkerParams {
    id: string;
  }

  fastify.delete<{ Params: DeleteWorkerParams }>(
    '/api/workers/:id',
    async (request, reply) => {
      const { id } = request.params;

      const state = await stateManager.loadWorkerState(id);
      if (!state) {
        return reply.status(404).send({ error: `Worker '${id}' not found` });
      }

      try {
        await orchestrator!.cleanup(id);

        broadcast({
          type: 'worker_cleaned',
          workerId: id,
        });

        return reply.send({ success: true });
      } catch (err) {
        return reply.status(500).send({
          error: `Failed to cleanup worker: ${err}`,
        });
      }
    }
  );

  // Cleanup all completed workers
  fastify.post('/api/cleanup', async (_request, reply) => {
    try {
      const cleaned = await stateManager.cleanup();

      for (const id of cleaned) {
        broadcast({
          type: 'worker_cleaned',
          workerId: id,
        });
      }

      return reply.send({ cleaned });
    } catch (err) {
      return reply.status(500).send({
        error: `Failed to cleanup: ${err}`,
      });
    }
  });

  // ==========================================
  // Project API (Full autonomous workflow)
  // ==========================================

  interface StartProjectBody {
    description: string;
  }

  fastify.post<{ Body: StartProjectBody }>(
    '/api/project',
    async (request, reply) => {
      const { description } = request.body;

      if (!description) {
        return reply.status(400).send({
          error: 'Missing required field: description',
        });
      }

      // Generate a project ID
      const projectId = `project-${Date.now()}`;

      broadcast({
        type: 'project_started',
        projectId,
        description,
      });

      // Note: Full project implementation would involve:
      // 1. Generate PRD using Claude
      // 2. Break into tasks
      // 3. Spawn workers
      // 4. Monitor and merge
      // For now, we return the project ID and let the skill handle coordination

      return reply.status(202).send({
        projectId,
        status: 'accepted',
        message: 'Project queued for processing',
      });
    }
  );

  // ==========================================
  // WebSocket for real-time updates
  // ==========================================

  fastify.get('/ws/status', { websocket: true }, (socket: WebSocket, _request) => {
    logger.info('WebSocket client connected');
    wsClients.add(socket);

    // Send current state on connect
    stateManager.loadAllWorkerStates().then(workers => {
      socket.send(JSON.stringify({
        type: 'initial_state',
        workers: workers.map(toApiResponse),
      }));
    }).catch(err => {
      logger.error('Failed to send initial state', { error: String(err) });
    });

    socket.on('close', () => {
      logger.info('WebSocket client disconnected');
      wsClients.delete(socket);
    });

    socket.on('error', (err) => {
      logger.error('WebSocket error', { error: String(err) });
      wsClients.delete(socket);
    });
  });

  // ==========================================
  // Start server
  // ==========================================

  // Store references for external access via decoration
  // Using Object.assign to avoid TypeScript strict type issues
  Object.assign(fastify, {
    orchestrator,
    stateManager,
    broadcast,
  });

  return fastify;
}

export async function startServer(config: ServerConfig): Promise<FastifyInstance> {
  const fastify = await createServer(config);

  try {
    await fastify.listen({ port: config.port, host: config.host });
    config.logger.info(`Server listening on http://${config.host}:${config.port}`);
    config.logger.info(`WebSocket available at ws://${config.host}:${config.port}/ws/status`);
    return fastify;
  } catch (err) {
    config.logger.error('Failed to start server', { error: String(err) });
    throw err;
  }
}
