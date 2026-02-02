/**
 * Memory Service
 *
 * Main facade for the memory system.
 * Coordinates database, stores, and search functionality.
 */

import * as path from 'node:path';
import { MemoryDatabase } from './database.js';
import { SessionStore } from './session-store.js';
import { ObservationStore } from './observation-store.js';
import { searchObservations, getSearchSummary } from './search.js';
import type {
  MemoryConfig,
  Session,
  NewSession,
  Observation,
  NewObservation,
  ObservationFilter,
  SearchOptions,
  SearchResult,
  ObservationType,
} from './types.js';
import type { Logger } from '../types.js';

/**
 * Memory service options
 */
export interface MemoryServiceOptions extends MemoryConfig {
  logger?: Logger;
}

/**
 * Memory Service
 *
 * Provides a unified API for persistent memory operations.
 */
export class MemoryService {
  private readonly database: MemoryDatabase;
  private readonly sessions: SessionStore;
  private readonly observations: ObservationStore;
  private readonly logger?: Logger;

  private currentSessionId: string | null = null;
  private initialized = false;

  constructor(options: MemoryServiceOptions) {
    const dbPath = options.dbPath ?? path.join(options.dataDir, 'memory.db');

    this.database = new MemoryDatabase({
      dataDir: options.dataDir,
      dbPath,
      logger: options.logger,
    });

    this.sessions = new SessionStore(this.database);
    this.observations = new ObservationStore(this.database);
    this.logger = options.logger;
  }

  // ============================================
  // Lifecycle Methods
  // ============================================

  /**
   * Initialize the memory service
   */
  initialize(): void {
    if (this.initialized) {
      return;
    }

    this.database.initialize();
    this.initialized = true;
    this.logger?.info?.('Memory service initialized');
  }

  /**
   * Shutdown the memory service
   */
  shutdown(): void {
    if (!this.initialized) {
      return;
    }

    // End current session if active
    if (this.currentSessionId) {
      this.endSession();
    }

    this.database.close();
    this.initialized = false;
    this.logger?.info?.('Memory service shutdown');
  }

  /**
   * Check if service is initialized
   */
  isInitialized(): boolean {
    return this.initialized;
  }

  // ============================================
  // Session Methods
  // ============================================

  /**
   * Start a new orchestrator session
   */
  startSession(options: NewSession = {}): string {
    this.ensureInitialized();

    // End existing session if any
    if (this.currentSessionId) {
      this.endSession();
    }

    const session = this.sessions.create(options);
    this.currentSessionId = session.id;

    this.logger?.info?.('Started new memory session', { sessionId: session.id });

    return session.id;
  }

  /**
   * End the current session
   */
  endSession(summary?: string): void {
    this.ensureInitialized();

    if (!this.currentSessionId) {
      return;
    }

    this.sessions.endSession(this.currentSessionId, summary);
    this.logger?.info?.('Ended memory session', { sessionId: this.currentSessionId });

    this.currentSessionId = null;
  }

  /**
   * Get the current session ID
   */
  getCurrentSessionId(): string | null {
    return this.currentSessionId;
  }

  /**
   * Get session by ID
   */
  getSession(id: string): Session | null {
    this.ensureInitialized();
    return this.sessions.getById(id);
  }

  /**
   * Get recent sessions
   */
  getRecentSessions(limit: number = 10): Session[] {
    this.ensureInitialized();
    return this.sessions.getRecent(limit);
  }

  /**
   * Increment worker count for current session
   */
  incrementWorkerCount(): void {
    this.ensureInitialized();

    if (this.currentSessionId) {
      this.sessions.incrementWorkerCount(this.currentSessionId);
    }
  }

  // ============================================
  // Observation Methods
  // ============================================

  /**
   * Capture an observation
   * Uses current session if sessionId not provided
   */
  captureObservation(input: Omit<NewObservation, 'sessionId'> & { sessionId?: string }): Observation {
    this.ensureInitialized();

    const sessionId = input.sessionId ?? this.currentSessionId;

    if (!sessionId) {
      throw new Error('No active session. Call startSession() first or provide sessionId.');
    }

    const observation = this.observations.add({
      sessionId,
      workerId: input.workerId,
      type: input.type,
      content: input.content,
      metadata: input.metadata,
    });

    this.logger?.debug?.('Captured observation', {
      id: observation.id,
      workerId: observation.workerId,
      type: observation.type,
    });

    return observation;
  }

  /**
   * Capture a state change observation
   */
  captureStateChange(
    workerId: string,
    fromState: string,
    toState: string,
    metadata?: Record<string, unknown>
  ): Observation {
    return this.captureObservation({
      workerId,
      type: 'state_change',
      content: `Worker ${workerId} transitioned from ${fromState} to ${toState}`,
      metadata: { fromState, toState, ...metadata },
    });
  }

  /**
   * Capture a PR event observation
   */
  capturePrEvent(
    workerId: string,
    event: 'created' | 'merged' | 'closed' | 'reviewed',
    prNumber: number,
    prUrl?: string
  ): Observation {
    return this.captureObservation({
      workerId,
      type: 'pr_event',
      content: `PR #${prNumber} ${event} for worker ${workerId}`,
      metadata: { event, prNumber, prUrl },
    });
  }

  /**
   * Capture an error observation
   */
  captureError(workerId: string, error: string, metadata?: Record<string, unknown>): Observation {
    return this.captureObservation({
      workerId,
      type: 'error',
      content: `Error in worker ${workerId}: ${error}`,
      metadata: { error, ...metadata },
    });
  }

  /**
   * Capture a task completion observation
   */
  captureTaskComplete(workerId: string, task: string, metadata?: Record<string, unknown>): Observation {
    return this.captureObservation({
      workerId,
      type: 'task_complete',
      content: `Worker ${workerId} completed: ${task}`,
      metadata: { task, ...metadata },
    });
  }

  /**
   * Get observations with filtering
   */
  getObservations(filter: ObservationFilter = {}): Observation[] {
    this.ensureInitialized();
    return this.observations.getFiltered(filter);
  }

  /**
   * Get observations for a specific worker
   */
  getWorkerObservations(workerId: string, limit: number = 100): Observation[] {
    this.ensureInitialized();
    return this.observations.getByWorkerId(workerId, limit);
  }

  /**
   * Get observations by IDs
   */
  getObservationsByIds(ids: number[]): Observation[] {
    this.ensureInitialized();
    return this.observations.getByIds(ids);
  }

  /**
   * Get recent observations
   */
  getRecentObservations(limit: number = 50): Observation[] {
    this.ensureInitialized();
    return this.observations.getRecent(limit);
  }

  // ============================================
  // Search Methods
  // ============================================

  /**
   * Search observations using full-text search
   */
  search(query: string, options: SearchOptions = {}): SearchResult[] {
    this.ensureInitialized();
    return searchObservations(this.database, query, options);
  }

  /**
   * Search with summary
   */
  searchWithSummary(query: string, options: SearchOptions = {}): {
    results: SearchResult[];
    summary: ReturnType<typeof getSearchSummary>;
  } {
    const results = this.search(query, options);
    const summary = getSearchSummary(results);
    return { results, summary };
  }

  // ============================================
  // Stats and Utilities
  // ============================================

  /**
   * Get memory statistics
   */
  getStats(): {
    sessions: number;
    observations: number;
    summaries: number;
    sizeBytes: number;
    currentSessionId: string | null;
  } {
    this.ensureInitialized();
    const dbStats = this.database.getStats();
    return {
      ...dbStats,
      currentSessionId: this.currentSessionId,
    };
  }

  /**
   * Get unique worker IDs
   */
  getWorkerIds(): string[] {
    this.ensureInitialized();
    return this.observations.getUniqueWorkerIds();
  }

  /**
   * Get session timeline
   */
  getSessionTimeline(sessionId: string): Array<{
    workerId: string;
    type: ObservationType;
    content: string;
    createdAt: string;
  }> {
    this.ensureInitialized();
    return this.observations.getTimeline(sessionId);
  }

  /**
   * Clean up old sessions
   */
  cleanup(olderThanDays: number = 30): number {
    this.ensureInitialized();
    const count = this.sessions.cleanup(olderThanDays);
    this.logger?.info?.('Cleaned up old sessions', { count, olderThanDays });
    return count;
  }

  /**
   * Vacuum the database
   */
  vacuum(): void {
    this.ensureInitialized();
    this.database.vacuum();
  }

  // ============================================
  // Private Methods
  // ============================================

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new Error('Memory service not initialized. Call initialize() first.');
    }
  }
}
