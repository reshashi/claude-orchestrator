/**
 * State Manager
 *
 * Handles persistence and recovery of worker state.
 * State is stored in ~/.claude/workers/<worker-id>/state.json
 */

import * as fs from 'node:fs/promises';
import * as path from 'node:path';

import type {
  WorkerInstance,
  WorkerRegistry,
  PersistedWorkerState,
  Logger,
} from './types.js';

const REGISTRY_VERSION = 1;

export interface StateManagerOptions {
  workersDir: string;  // ~/.claude/workers
  logger: Logger;
}

export class StateManager {
  private readonly options: StateManagerOptions;
  private readonly logger: Logger;
  private readonly registryPath: string;

  constructor(options: StateManagerOptions) {
    this.options = options;
    this.logger = options.logger;
    this.registryPath = path.join(options.workersDir, 'registry.json');
  }

  /**
   * Initialize state directory
   */
  async initialize(): Promise<void> {
    await fs.mkdir(this.options.workersDir, { recursive: true });

    // Create registry if it doesn't exist
    try {
      await fs.access(this.registryPath);
    } catch {
      await this.saveRegistry({
        version: REGISTRY_VERSION,
        workers: {},
        lastUpdated: new Date().toISOString(),
      });
    }
  }

  /**
   * Load the worker registry
   */
  async loadRegistry(): Promise<WorkerRegistry> {
    try {
      const content = await fs.readFile(this.registryPath, 'utf-8');
      return JSON.parse(content) as WorkerRegistry;
    } catch {
      return {
        version: REGISTRY_VERSION,
        workers: {},
        lastUpdated: new Date().toISOString(),
      };
    }
  }

  /**
   * Save the worker registry
   */
  async saveRegistry(registry: WorkerRegistry): Promise<void> {
    registry.lastUpdated = new Date().toISOString();
    await fs.writeFile(
      this.registryPath,
      JSON.stringify(registry, null, 2),
      'utf-8'
    );
  }

  /**
   * Save a worker's state
   */
  async saveWorkerState(worker: WorkerInstance): Promise<void> {
    const { id } = worker.config;
    const workerDir = path.join(this.options.workersDir, id);

    await fs.mkdir(workerDir, { recursive: true });

    // Create persisted state
    const state: PersistedWorkerState = {
      id,
      config: worker.config,
      state: worker.state,
      pid: worker.pid,
      prNumber: worker.prNumber,
      prUrl: worker.prUrl,
      lastActivity: worker.lastActivity.toISOString(),
      error: worker.error,
      reviewStatus: worker.reviewStatus,
      agentsRun: worker.agentsRun,
    };

    // Save to worker directory
    const statePath = path.join(workerDir, 'state.json');
    await fs.writeFile(statePath, JSON.stringify(state, null, 2), 'utf-8');

    // Update registry
    const registry = await this.loadRegistry();
    registry.workers[id] = state;
    await this.saveRegistry(registry);

    this.logger.debug(`Saved state for worker ${id}`, { state: worker.state });
  }

  /**
   * Load a worker's state from disk
   */
  async loadWorkerState(workerId: string): Promise<PersistedWorkerState | null> {
    const statePath = path.join(this.options.workersDir, workerId, 'state.json');

    try {
      const content = await fs.readFile(statePath, 'utf-8');
      return JSON.parse(content) as PersistedWorkerState;
    } catch {
      return null;
    }
  }

  /**
   * Load all persisted worker states
   */
  async loadAllWorkerStates(): Promise<PersistedWorkerState[]> {
    const registry = await this.loadRegistry();
    return Object.values(registry.workers);
  }

  /**
   * Remove a worker's state
   */
  async removeWorkerState(workerId: string): Promise<void> {
    const workerDir = path.join(this.options.workersDir, workerId);

    try {
      await fs.rm(workerDir, { recursive: true, force: true });
    } catch {
      // Ignore if already removed
    }

    // Update registry
    const registry = await this.loadRegistry();
    delete registry.workers[workerId];
    await this.saveRegistry(registry);

    this.logger.info(`Removed state for worker ${workerId}`);
  }

  /**
   * Append to worker output log
   */
  async appendOutputLog(workerId: string, content: string): Promise<void> {
    const outputPath = path.join(this.options.workersDir, workerId, 'output.jsonl');

    try {
      await fs.mkdir(path.dirname(outputPath), { recursive: true });
      await fs.appendFile(outputPath, content + '\n', 'utf-8');
    } catch (err) {
      this.logger.warn(`Failed to append output for ${workerId}`, { error: String(err) });
    }
  }

  /**
   * Read worker output log
   */
  async readOutputLog(workerId: string, lines?: number): Promise<string[]> {
    const outputPath = path.join(this.options.workersDir, workerId, 'output.jsonl');

    try {
      const content = await fs.readFile(outputPath, 'utf-8');
      const allLines = content.split('\n').filter(l => l.trim());

      if (lines) {
        return allLines.slice(-lines);
      }
      return allLines;
    } catch {
      return [];
    }
  }

  /**
   * Clean up completed/stale workers
   */
  async cleanup(maxAgeMs: number = 7 * 24 * 60 * 60 * 1000): Promise<string[]> {
    const registry = await this.loadRegistry();
    const now = Date.now();
    const cleaned: string[] = [];

    for (const [id, state] of Object.entries(registry.workers)) {
      const age = now - new Date(state.lastActivity).getTime();

      // Remove merged or stopped workers older than maxAge
      if (['MERGED', 'STOPPED', 'ERROR'].includes(state.state) && age > maxAgeMs) {
        await this.removeWorkerState(id);
        cleaned.push(id);
      }
    }

    if (cleaned.length > 0) {
      this.logger.info(`Cleaned up ${cleaned.length} stale workers`, { workers: cleaned });
    }

    return cleaned;
  }

  /**
   * Get active worker count
   */
  async getActiveCount(): Promise<number> {
    const registry = await this.loadRegistry();
    const activeStates = ['SPAWNING', 'INITIALIZING', 'WORKING', 'PR_OPEN', 'REVIEWING', 'MERGING'];

    return Object.values(registry.workers).filter(w =>
      activeStates.includes(w.state)
    ).length;
  }

  /**
   * Check if a worker ID already exists
   */
  async workerExists(workerId: string): Promise<boolean> {
    const registry = await this.loadRegistry();
    return workerId in registry.workers;
  }

  /**
   * Convert persisted state back to worker instance
   * (Used when recovering workers on restart)
   */
  persistedToInstance(state: PersistedWorkerState): Omit<WorkerInstance, 'process'> & { process: null } {
    return {
      config: {
        ...state.config,
        createdAt: new Date(state.config.createdAt),
      },
      state: state.state,
      process: null,
      pid: state.pid,
      prNumber: state.prNumber,
      prUrl: state.prUrl,
      lastActivity: new Date(state.lastActivity),
      error: state.error,
      reviewStatus: state.reviewStatus,
      agentsRun: state.agentsRun,
    };
  }
}
