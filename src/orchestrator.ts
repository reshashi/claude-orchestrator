/**
 * Orchestrator
 *
 * Main orchestration loop that monitors workers and manages their lifecycle.
 * Replaces orchestrator-loop.sh with cross-platform Node.js implementation.
 */

import { EventEmitter } from 'node:events';
import * as path from 'node:path';
import * as os from 'node:os';

import type {
  WorkerConfig,
  WorkerInstance,
  WorkerEvent,
  OrchestratorConfig,
  Logger,
} from './types.js';

import { WorkerManager } from './worker-manager.js';
import { StateManager } from './state-manager.js';
import { GitHub } from './github.js';
import { MemoryService } from './memory/index.js';
import {
  needsIntervention,
  isTerminalState,
  getStateDescription,
} from './state-machine.js';

const DEFAULT_CONFIG: OrchestratorConfig = {
  pollIntervalMs: 5000,
  workersDir: path.join(os.homedir(), '.claude', 'workers'),
  worktreesDir: path.join(os.homedir(), '.worktrees'),
  logFile: path.join(os.homedir(), '.claude', 'orchestrator.log'),
  autoMerge: true,
  autoReview: true,
  memory: {
    enabled: true,
    dataDir: path.join(os.homedir(), '.claude', 'memory'),
  },
};

export interface OrchestratorOptions {
  config?: Partial<OrchestratorConfig>;
  logger: Logger;
}

export class Orchestrator extends EventEmitter {
  private readonly config: OrchestratorConfig;
  private readonly logger: Logger;
  private readonly workerManager: WorkerManager;
  private readonly stateManager: StateManager;
  private readonly memoryService: MemoryService | null = null;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private isRunning = false;
  private githubClients: Map<string, GitHub> = new Map();

  constructor(options: OrchestratorOptions) {
    super();
    this.config = { ...DEFAULT_CONFIG, ...options.config };
    this.logger = options.logger;

    this.workerManager = new WorkerManager({
      workersDir: this.config.workersDir,
      worktreesDir: this.config.worktreesDir,
      logger: this.logger,
    });

    this.stateManager = new StateManager({
      workersDir: this.config.workersDir,
      logger: this.logger,
    });

    // Initialize memory service if enabled
    if (this.config.memory?.enabled) {
      this.memoryService = new MemoryService({
        dataDir: this.config.memory.dataDir,
        dbPath: this.config.memory.dbPath,
        logger: this.logger,
      });
    }

    // Forward worker events
    this.workerManager.on('event', (event: WorkerEvent) => {
      this.handleWorkerEvent(event);
      this.emit('worker_event', event);
    });
  }

  /**
   * Initialize the orchestrator
   */
  async initialize(): Promise<void> {
    await this.stateManager.initialize();

    // Initialize memory service
    if (this.memoryService) {
      this.memoryService.initialize();
      this.memoryService.startSession({
        metadata: { startedAt: new Date().toISOString() },
      });
    }

    // Recover any workers that were running before restart
    const persistedWorkers = await this.stateManager.loadAllWorkerStates();

    for (const state of persistedWorkers) {
      if (!isTerminalState(state.state)) {
        this.logger.info(`Found active worker ${state.id} in state ${state.state}`);
        // Note: We don't restart processes automatically - user must do that explicitly
      }
    }

    this.logger.info('Orchestrator initialized');
  }

  /**
   * Start the orchestration loop
   */
  start(): void {
    if (this.isRunning) {
      this.logger.warn('Orchestrator already running');
      return;
    }

    this.isRunning = true;
    this.logger.info('Starting orchestrator loop', {
      pollInterval: this.config.pollIntervalMs,
    });

    this.pollTimer = setInterval(() => {
      this.tick().catch(err => {
        this.logger.error('Orchestrator tick error', { error: String(err) });
      });
    }, this.config.pollIntervalMs);

    // Run initial tick
    this.tick().catch(err => {
      this.logger.error('Initial tick error', { error: String(err) });
    });
  }

  /**
   * Stop the orchestration loop
   */
  stop(): void {
    if (!this.isRunning) return;

    this.isRunning = false;
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }

    // End memory session
    if (this.memoryService?.isInitialized()) {
      this.memoryService.endSession('Orchestrator stopped');
      this.memoryService.shutdown();
    }

    this.logger.info('Orchestrator stopped');
  }

  /**
   * Single tick of the orchestration loop
   */
  private async tick(): Promise<void> {
    const workers = this.workerManager.getAllWorkers();

    for (const worker of workers) {
      await this.processWorker(worker);
    }
  }

  /**
   * Process a single worker
   */
  private async processWorker(worker: WorkerInstance): Promise<void> {
    const workerId = worker.config.id;

    // Skip terminal states
    if (isTerminalState(worker.state)) {
      return;
    }

    // Check for intervention needs
    const intervention = needsIntervention(worker);
    if (intervention.needed) {
      this.logger.warn(`Worker ${workerId} needs intervention`, intervention);
      await this.handleIntervention(worker, intervention);
      return;
    }

    // State-specific handling
    switch (worker.state) {
      case 'PR_OPEN':
        await this.handlePrOpen(worker);
        break;

      case 'REVIEWING':
        await this.handleReviewing(worker);
        break;

      case 'MERGING':
        await this.handleMerging(worker);
        break;
    }

    // Persist state after processing
    await this.stateManager.saveWorkerState(worker);
  }

  /**
   * Handle PR_OPEN state - check CI and initiate review
   */
  private async handlePrOpen(worker: WorkerInstance): Promise<void> {
    const { config, prNumber } = worker;
    if (!prNumber) return;

    const gh = await this.getGitHubClient(config.worktreePath);
    if (!gh) return;

    const status = await gh.getPrStatus(prNumber);
    if (!status) return;

    this.logger.debug(`PR #${prNumber} status`, { ...status });

    if (status.ciStatus === 'passed') {
      // CI passed - check if review needed
      if (worker.reviewStatus === 'none' && this.config.autoReview) {
        this.logger.info(`PR #${prNumber} CI passed, initiating review`);
        await this.initiateReview(worker);
      } else if (worker.reviewStatus === 'passed') {
        // Review passed - run additional quality agents
        await this.runQualityAgents(worker, gh);
      }
    } else if (status.ciStatus === 'failed') {
      // CI failed - nudge worker to fix
      this.logger.info(`PR #${prNumber} CI failed, nudging worker`);
      await this.nudgeWorker(worker, 'CI failed. Run `gh pr checks` and fix the issues.');

      // Clear review state since code will change
      worker.reviewStatus = 'none';
      worker.agentsRun = [];
    }
    // If pending, just wait
  }

  /**
   * Handle REVIEWING state - check if review complete
   */
  private async handleReviewing(worker: WorkerInstance): Promise<void> {
    // Review completion is detected via message parsing
    // State will transition based on review results
    if (worker.reviewStatus === 'passed') {
      this.workerManager.transitionState(worker.config.id, 'PR_OPEN');
    } else if (worker.reviewStatus === 'failed') {
      this.logger.info(`Worker ${worker.config.id} review failed, back to PR_OPEN`);
      this.workerManager.transitionState(worker.config.id, 'PR_OPEN');
    }
  }

  /**
   * Handle MERGING state - perform merge
   */
  private async handleMerging(worker: WorkerInstance): Promise<void> {
    const { config, prNumber } = worker;
    if (!prNumber) return;

    const gh = await this.getGitHubClient(config.worktreePath);
    if (!gh) return;

    if (this.config.autoMerge) {
      const success = await gh.mergePr(prNumber, 'squash', true);
      if (success) {
        this.workerManager.transitionState(config.id, 'MERGED');
        this.emit('pr_merged', { workerId: config.id, prNumber });
      } else {
        this.workerManager.transitionState(config.id, 'ERROR');
        worker.error = 'Merge failed';
      }
    }
  }

  /**
   * Initiate QA review
   */
  private async initiateReview(worker: WorkerInstance): Promise<void> {
    const { config, prNumber } = worker;

    worker.reviewStatus = 'pending';
    this.workerManager.transitionState(config.id, 'REVIEWING');

    // Send review command to worker
    await this.workerManager.sendMessage(
      config.id,
      `/review ${config.branchName}`
    );

    // Add review label
    const gh = await this.getGitHubClient(config.worktreePath);
    if (gh && prNumber) {
      await gh.addLabel(prNumber, 'review-pending');
    }
  }

  /**
   * Run quality agents (security, devops, simplifier)
   */
  private async runQualityAgents(worker: WorkerInstance, gh: GitHub): Promise<void> {
    const { prNumber, agentsRun, config } = worker;
    if (!prNumber) return;

    // Security scan runs on ALL PRs
    if (!agentsRun.includes('security')) {
      this.logger.info(`Running security scan for PR #${prNumber}`);
      await this.workerManager.sendMessage(
        config.id,
        "Run 'npm audit --audit-level=high' and report any vulnerabilities. If critical issues found, list them clearly."
      );
      this.workerManager.markAgentRun(config.id, 'security');
    }

    // DevOps review for infrastructure changes
    if (!agentsRun.includes('devops') && await gh.needsDevopsReview(prNumber)) {
      this.logger.info(`Running devops review for PR #${prNumber}`);
      await this.workerManager.sendMessage(config.id, '/deploy');
      this.workerManager.markAgentRun(config.id, 'devops');
    }

    // Code simplifier for large PRs
    if (!agentsRun.includes('simplifier') && await gh.needsCodeSimplifier(prNumber)) {
      this.logger.info(`Running code-simplifier for PR #${prNumber}`);
      await this.workerManager.sendMessage(config.id, '/qcode');
      this.workerManager.markAgentRun(config.id, 'simplifier');
    }

    // Check if all agents complete
    const allComplete = await this.checkAgentsComplete(worker, gh);
    if (allComplete) {
      this.logger.info(`PR #${prNumber} all agents passed, transitioning to MERGING`);
      this.workerManager.transitionState(config.id, 'MERGING');
    }
  }

  /**
   * Check if all required agents have completed
   */
  private async checkAgentsComplete(worker: WorkerInstance, gh: GitHub): Promise<boolean> {
    const { prNumber, agentsRun, reviewStatus } = worker;
    if (!prNumber) return false;

    // Review must have passed
    if (reviewStatus !== 'passed') return false;

    // Security must have run
    if (!agentsRun.includes('security')) return false;

    // DevOps must have run if needed
    if (await gh.needsDevopsReview(prNumber) && !agentsRun.includes('devops')) {
      return false;
    }

    // Simplifier must have run if needed
    if (await gh.needsCodeSimplifier(prNumber) && !agentsRun.includes('simplifier')) {
      return false;
    }

    return true;
  }

  /**
   * Handle worker intervention
   */
  private async handleIntervention(
    worker: WorkerInstance,
    intervention: { needed: boolean; reason?: string; action?: string }
  ): Promise<void> {
    const { config } = worker;

    switch (intervention.action) {
      case 'nudge':
        await this.nudgeWorker(worker, 'Are you still working? Please continue with your task.');
        break;

      case 'restart':
        this.logger.info(`Restarting worker ${config.id}`);
        await this.workerManager.terminate(config.id);
        // User must explicitly restart
        this.emit('worker_needs_restart', { workerId: config.id, reason: intervention.reason });
        break;

      case 'manual':
        this.emit('worker_needs_manual', { workerId: config.id, reason: intervention.reason });
        break;
    }
  }

  /**
   * Send a nudge message to a worker
   */
  private async nudgeWorker(worker: WorkerInstance, message: string): Promise<void> {
    try {
      await this.workerManager.sendMessage(worker.config.id, message);
    } catch (err) {
      this.logger.warn(`Failed to nudge worker ${worker.config.id}`, { error: String(err) });
    }
  }

  /**
   * Handle events from worker manager
   */
  private async handleWorkerEvent(event: WorkerEvent): Promise<void> {
    // Capture to memory if enabled
    this.captureEventToMemory(event);

    switch (event.type) {
      case 'state_change':
        await this.stateManager.saveWorkerState(
          this.workerManager.getWorker(event.workerId)!
        );
        break;

      case 'pr_detected':
        this.logger.info(`Worker ${event.workerId} created PR #${event.prNumber}`);
        break;

      case 'review_complete':
        const worker = this.workerManager.getWorker(event.workerId);
        if (worker?.prNumber) {
          const gh = await this.getGitHubClient(worker.config.worktreePath);
          if (gh) {
            await gh.removeLabel(worker.prNumber, 'review-pending');
            if (event.result === 'passed') {
              await gh.addLabel(worker.prNumber, 'reviewed');
            }
          }
        }
        break;

      case 'process_exit':
        // Clean up if process exited
        break;
    }
  }

  /**
   * Capture worker event to memory system
   */
  private captureEventToMemory(event: WorkerEvent): void {
    if (!this.memoryService?.isInitialized()) return;

    try {
      switch (event.type) {
        case 'state_change':
          this.memoryService.captureStateChange(
            event.workerId,
            event.from,
            event.to
          );
          break;

        case 'pr_detected':
          this.memoryService.capturePrEvent(
            event.workerId,
            'created',
            event.prNumber,
            event.prUrl
          );
          break;

        case 'pr_merged':
          this.memoryService.capturePrEvent(
            event.workerId,
            'merged',
            event.prNumber
          );
          break;

        case 'review_complete':
          this.memoryService.captureObservation({
            workerId: event.workerId,
            type: 'pr_event',
            content: `Review completed for worker ${event.workerId}: ${event.result}`,
            metadata: { result: event.result },
          });
          break;

        case 'error':
          this.memoryService.captureError(event.workerId, event.error);
          break;

        case 'process_exit':
          this.memoryService.captureObservation({
            workerId: event.workerId,
            type: 'state_change',
            content: `Process exited for worker ${event.workerId} with code ${event.code}`,
            metadata: { exitCode: event.code },
          });
          break;
      }
    } catch (err) {
      this.logger.warn('Failed to capture event to memory', { error: String(err) });
    }
  }

  /**
   * Get or create GitHub client for a worktree
   */
  private async getGitHubClient(worktreePath: string): Promise<GitHub | null> {
    if (this.githubClients.has(worktreePath)) {
      return this.githubClients.get(worktreePath)!;
    }

    const gh = await GitHub.fromWorktree(worktreePath, this.logger);
    if (gh) {
      this.githubClients.set(worktreePath, gh);
    }
    return gh;
  }

  // =====================================
  // Public API
  // =====================================

  /**
   * Spawn a new worker
   */
  async spawn(
    name: string,
    task: string,
    repoName?: string
  ): Promise<WorkerInstance> {
    // Determine repo from current directory if not provided
    const effectiveRepoName = repoName ?? path.basename(process.cwd());
    const worktreePath = path.join(this.config.worktreesDir, effectiveRepoName, name);
    const branchName = `feature/${name}`;

    const config: WorkerConfig = {
      id: name,
      repoName: effectiveRepoName,
      worktreePath,
      branchName,
      task,
      createdAt: new Date(),
    };

    const worker = await this.workerManager.spawn(config);
    await this.stateManager.saveWorkerState(worker);

    // Track in memory
    if (this.memoryService?.isInitialized()) {
      this.memoryService.incrementWorkerCount();
      this.memoryService.captureObservation({
        workerId: name,
        type: 'state_change',
        content: `Spawned worker ${name} with task: ${task.substring(0, 100)}`,
        metadata: { task, repoName: effectiveRepoName, worktreePath, branchName },
      });
    }

    return worker;
  }

  /**
   * List all workers
   */
  listWorkers(): WorkerInstance[] {
    return this.workerManager.getAllWorkers();
  }

  /**
   * Get worker status
   */
  getWorkerStatus(workerId: string): {
    worker: WorkerInstance | undefined;
    description: string;
  } {
    const worker = this.workerManager.getWorker(workerId);
    return {
      worker,
      description: worker ? getStateDescription(worker.state) : 'Worker not found',
    };
  }

  /**
   * Send message to worker
   */
  async sendMessage(workerId: string, message: string): Promise<void> {
    await this.workerManager.sendMessage(workerId, message);
  }

  /**
   * Read worker output
   */
  getOutput(workerId: string, lines?: number): string[] {
    return this.workerManager.getOutput(workerId, lines);
  }

  /**
   * Stop a worker
   */
  async stopWorker(workerId: string): Promise<void> {
    await this.workerManager.terminate(workerId);
  }

  /**
   * Clean up completed workers
   */
  async cleanup(workerId?: string): Promise<void> {
    if (workerId) {
      const worker = this.workerManager.getWorker(workerId);
      if (worker && isTerminalState(worker.state)) {
        this.workerManager.removeWorker(workerId);
        await this.stateManager.removeWorkerState(workerId);
      }
    } else {
      await this.stateManager.cleanup();
    }
  }

  /**
   * Manually trigger merge for a worker
   */
  async triggerMerge(workerId: string): Promise<boolean> {
    const worker = this.workerManager.getWorker(workerId);
    if (!worker?.prNumber) {
      this.logger.warn(`Worker ${workerId} has no PR to merge`);
      return false;
    }

    const gh = await this.getGitHubClient(worker.config.worktreePath);
    if (!gh) return false;

    this.workerManager.transitionState(workerId, 'MERGING');
    return await gh.mergePr(worker.prNumber, 'squash', true);
  }

  /**
   * Get the memory service (for API access)
   */
  getMemoryService(): MemoryService | null {
    return this.memoryService;
  }
}
