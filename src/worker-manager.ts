/**
 * Worker Manager
 *
 * Manages Claude CLI worker processes - spawning, monitoring, and termination.
 * Replaces the macOS-specific iTerm/AppleScript approach with cross-platform
 * Node.js child processes.
 */

import { spawn, type ChildProcess } from 'node:child_process';
import { EventEmitter } from 'node:events';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';

import type {
  WorkerConfig,
  WorkerInstance,
  WorkerState,
  WorkerEvent,
  ClaudeMessage,
  Logger,
  AgentType,
} from './types.js';

import {
  createJsonlParser,
  extractPrUrl,
  extractPrNumber,
  hasToolUse,
  isComplete,
  isApiError,
  isReviewComplete,
} from './jsonl-parser.js';

export interface WorkerManagerOptions {
  workersDir: string;       // ~/.claude/workers
  worktreesDir: string;     // ~/.worktrees
  logger: Logger;
}

export class WorkerManager extends EventEmitter {
  private workers: Map<string, WorkerInstance> = new Map();
  private outputBuffers: Map<string, string[]> = new Map();
  private readonly options: WorkerManagerOptions;
  private readonly logger: Logger;

  constructor(options: WorkerManagerOptions) {
    super();
    this.options = options;
    this.logger = options.logger;
  }

  /**
   * Spawn a new Claude worker process
   */
  async spawn(config: WorkerConfig): Promise<WorkerInstance> {
    const { id, worktreePath, task } = config;

    if (this.workers.has(id)) {
      throw new Error(`Worker ${id} already exists`);
    }

    // Verify worktree exists
    try {
      await fs.access(worktreePath);
    } catch {
      throw new Error(`Worktree not found at ${worktreePath}`);
    }

    this.logger.info(`Spawning worker ${id}`, { worktreePath, task });

    // Create worker instance
    const worker: WorkerInstance = {
      config,
      state: 'SPAWNING',
      process: null,
      pid: null,
      prNumber: null,
      prUrl: null,
      lastActivity: new Date(),
      error: null,
      reviewStatus: 'none',
      agentsRun: [],
    };

    this.workers.set(id, worker);
    this.outputBuffers.set(id, []);

    // Spawn Claude CLI with --print mode
    const proc = spawn('claude', [
      '--print',
      '--output-format', 'stream-json',
      '--dangerously-skip-permissions',
      task,
    ], {
      cwd: worktreePath,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    worker.process = proc;
    worker.pid = proc.pid ?? null;

    this.setupProcessHandlers(id, proc);
    this.transitionState(id, 'INITIALIZING');

    return worker;
  }

  /**
   * Set up stdout/stderr handlers for a worker process
   */
  private setupProcessHandlers(workerId: string, proc: ChildProcess): void {
    const worker = this.workers.get(workerId);
    if (!worker) return;

    // Create JSONL parser for stdout
    const parser = createJsonlParser(
      (message) => this.handleMessage(workerId, message),
      (error, rawLine) => {
        this.logger.debug(`Parse error for ${workerId}: ${error.message}`, { rawLine });
        // Store raw line in buffer even if not JSON
        this.appendOutput(workerId, rawLine);
      }
    );

    // Handle stdout
    proc.stdout?.on('data', (chunk: Buffer) => {
      const text = chunk.toString();
      parser.write(text);
      this.appendOutput(workerId, text);
      this.updateActivity(workerId);
    });

    // Handle stderr
    proc.stderr?.on('data', (chunk: Buffer) => {
      const text = chunk.toString();
      this.logger.warn(`Worker ${workerId} stderr: ${text}`);
      this.appendOutput(workerId, `[stderr] ${text}`);
      this.logError(workerId, text);
    });

    // Handle process exit
    proc.on('exit', (code, signal) => {
      this.logger.info(`Worker ${workerId} exited`, { code, signal });
      parser.flush();

      const currentWorker = this.workers.get(workerId);
      if (currentWorker) {
        currentWorker.process = null;
        currentWorker.pid = null;

        if (currentWorker.state !== 'MERGED' && currentWorker.state !== 'STOPPED') {
          if (code !== 0) {
            this.transitionState(workerId, 'ERROR');
            currentWorker.error = `Process exited with code ${code}`;
          } else {
            this.transitionState(workerId, 'STOPPED');
          }
        }
      }

      this.emit('event', {
        type: 'process_exit',
        workerId,
        code,
      } satisfies WorkerEvent);
    });

    // Handle process error
    proc.on('error', (err) => {
      this.logger.error(`Worker ${workerId} process error: ${err.message}`);
      this.transitionState(workerId, 'ERROR');

      const currentWorker = this.workers.get(workerId);
      if (currentWorker) {
        currentWorker.error = err.message;
      }

      this.emit('event', {
        type: 'error',
        workerId,
        error: err.message,
      } satisfies WorkerEvent);
    });
  }

  /**
   * Handle a parsed JSON message from Claude
   */
  private handleMessage(workerId: string, message: ClaudeMessage): void {
    const worker = this.workers.get(workerId);
    if (!worker) return;

    this.emit('event', {
      type: 'output',
      workerId,
      message,
    } satisfies WorkerEvent);

    // State detection based on message content
    if (hasToolUse(message)) {
      // Tool use indicates active work
      if (worker.state === 'INITIALIZING') {
        this.transitionState(workerId, 'WORKING');
      }
    }

    // Check for PR URL in output
    const prUrl = extractPrUrl(message);
    if (prUrl && !worker.prUrl) {
      const prNumber = extractPrNumber(message);
      worker.prUrl = prUrl;
      worker.prNumber = prNumber;

      this.logger.info(`Worker ${workerId} created PR`, { prUrl, prNumber });

      if (prNumber) {
        this.emit('event', {
          type: 'pr_detected',
          workerId,
          prNumber,
          prUrl,
        } satisfies WorkerEvent);

        this.transitionState(workerId, 'PR_OPEN');
      }
    }

    // Check for review completion
    const reviewResult = isReviewComplete(message);
    if (reviewResult && worker.reviewStatus === 'pending') {
      worker.reviewStatus = reviewResult;

      this.emit('event', {
        type: 'review_complete',
        workerId,
        result: reviewResult,
      } satisfies WorkerEvent);
    }

    // Check for API errors
    if (isApiError(message)) {
      this.transitionState(workerId, 'ERROR');
      worker.error = 'Claude API error detected';
    }

    // Check for completion
    if (isComplete(message) && worker.state === 'WORKING') {
      // Don't immediately mark as complete - check for PR
      if (!worker.prUrl) {
        // No PR yet but Claude finished - might be waiting for input
        this.logger.debug(`Worker ${workerId} completed without PR`);
      }
    }
  }

  /**
   * Send a message to a worker via stdin
   */
  async sendMessage(workerId: string, message: string): Promise<void> {
    const worker = this.workers.get(workerId);
    if (!worker?.process?.stdin?.writable) {
      throw new Error(`Worker ${workerId} is not running or stdin not available`);
    }

    this.logger.info(`Sending message to ${workerId}`, { message: message.substring(0, 100) });

    return new Promise((resolve, reject) => {
      worker.process!.stdin!.write(message + '\n', (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  /**
   * Terminate a worker process gracefully
   */
  async terminate(workerId: string): Promise<void> {
    const worker = this.workers.get(workerId);
    if (!worker?.process) {
      this.logger.warn(`Worker ${workerId} not running`);
      return;
    }

    this.logger.info(`Terminating worker ${workerId}`);

    return new Promise((resolve) => {
      const proc = worker.process!;

      // Give process time to exit gracefully
      const timeout = setTimeout(() => {
        if (proc.killed) return;
        this.logger.warn(`Force killing worker ${workerId}`);
        proc.kill('SIGKILL');
      }, 5000);

      proc.once('exit', () => {
        clearTimeout(timeout);
        this.transitionState(workerId, 'STOPPED');
        resolve();
      });

      proc.kill('SIGTERM');
    });
  }

  /**
   * Get a worker by ID
   */
  getWorker(workerId: string): WorkerInstance | undefined {
    return this.workers.get(workerId);
  }

  /**
   * Get all workers
   */
  getAllWorkers(): WorkerInstance[] {
    return Array.from(this.workers.values());
  }

  /**
   * Get worker output buffer
   */
  getOutput(workerId: string, lines?: number): string[] {
    const buffer = this.outputBuffers.get(workerId) ?? [];
    if (lines) {
      return buffer.slice(-lines);
    }
    return buffer;
  }

  /**
   * Transition worker state
   */
  transitionState(workerId: string, newState: WorkerState): void {
    const worker = this.workers.get(workerId);
    if (!worker) return;

    const oldState = worker.state;
    if (oldState === newState) return;

    this.logger.info(`Worker ${workerId} state: ${oldState} -> ${newState}`);
    worker.state = newState;

    this.emit('event', {
      type: 'state_change',
      workerId,
      from: oldState,
      to: newState,
    } satisfies WorkerEvent);
  }

  /**
   * Mark an agent as having run
   */
  markAgentRun(workerId: string, agent: AgentType): void {
    const worker = this.workers.get(workerId);
    if (!worker) return;

    if (!worker.agentsRun.includes(agent)) {
      worker.agentsRun.push(agent);
    }
  }

  /**
   * Check if an agent has run
   */
  hasAgentRun(workerId: string, agent: AgentType): boolean {
    const worker = this.workers.get(workerId);
    return worker?.agentsRun.includes(agent) ?? false;
  }

  /**
   * Set review status
   */
  setReviewStatus(workerId: string, status: WorkerInstance['reviewStatus']): void {
    const worker = this.workers.get(workerId);
    if (worker) {
      worker.reviewStatus = status;
    }
  }

  /**
   * Remove a worker from tracking
   */
  removeWorker(workerId: string): void {
    this.workers.delete(workerId);
    this.outputBuffers.delete(workerId);
  }

  /**
   * Append to output buffer
   */
  private appendOutput(workerId: string, text: string): void {
    const buffer = this.outputBuffers.get(workerId);
    if (buffer) {
      // Split by lines and add each
      const lines = text.split('\n').filter(l => l.trim());
      buffer.push(...lines);

      // Keep buffer size reasonable (last 1000 lines)
      if (buffer.length > 1000) {
        buffer.splice(0, buffer.length - 1000);
      }
    }
  }

  /**
   * Update last activity timestamp
   */
  private updateActivity(workerId: string): void {
    const worker = this.workers.get(workerId);
    if (worker) {
      worker.lastActivity = new Date();
    }
  }

  /**
   * Log error to worker-specific error log
   */
  private async logError(workerId: string, error: string): Promise<void> {
    const errorLogPath = path.join(this.options.workersDir, workerId, 'errors.log');

    try {
      await fs.mkdir(path.dirname(errorLogPath), { recursive: true });
      const timestamp = new Date().toISOString();
      await fs.appendFile(errorLogPath, `[${timestamp}] ${error}\n`);
    } catch {
      // Ignore file write errors
    }
  }
}
