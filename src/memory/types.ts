/**
 * Memory Module Types
 *
 * TypeScript types for the persistent memory system.
 */

/**
 * Observation types that can be recorded
 */
export type ObservationType =
  | 'state_change'    // Worker state transition
  | 'pr_event'        // PR created, merged, etc.
  | 'error'           // Error occurred
  | 'task_complete'   // Task completed
  | 'message_sent'    // Message sent to worker
  | 'custom';         // Custom observation

/**
 * A session represents a single orchestrator run
 */
export interface Session {
  id: string;
  startedAt: string;
  endedAt: string | null;
  workerCount: number;
  summary: string | null;
  metadata: Record<string, unknown> | null;
}

/**
 * Input for creating a new session
 */
export interface NewSession {
  id?: string;
  metadata?: Record<string, unknown>;
}

/**
 * An observation is a captured event or piece of information
 */
export interface Observation {
  id: number;
  sessionId: string;
  workerId: string;
  type: ObservationType;
  content: string;
  metadata: Record<string, unknown> | null;
  createdAt: string;
}

/**
 * Input for creating a new observation
 */
export interface NewObservation {
  sessionId: string;
  workerId: string;
  type: ObservationType;
  content: string;
  metadata?: Record<string, unknown>;
}

/**
 * A summary is a compressed version of session activity
 */
export interface Summary {
  id: number;
  sessionId: string;
  summary: string;
  createdAt: string;
}

/**
 * Input for creating a new summary
 */
export interface NewSummary {
  sessionId: string;
  summary: string;
}

/**
 * Filter options for querying observations
 */
export interface ObservationFilter {
  sessionId?: string;
  workerId?: string;
  type?: ObservationType;
  since?: string;
  limit?: number;
  offset?: number;
}

/**
 * Options for search queries
 */
export interface SearchOptions {
  limit?: number;
  offset?: number;
  sessionId?: string;
  workerId?: string;
  type?: ObservationType;
  since?: string;
}

/**
 * A search result with relevance score
 */
export interface SearchResult {
  observation: Observation;
  rank: number;
  snippet: string;
}

/**
 * Memory service configuration
 */
export interface MemoryConfig {
  dataDir: string;
  dbPath?: string;
}

/**
 * Database row types (internal)
 */
export interface SessionRow {
  id: string;
  started_at: string;
  ended_at: string | null;
  worker_count: number;
  summary: string | null;
  metadata: string | null;
}

export interface ObservationRow {
  id: number;
  session_id: string;
  worker_id: string;
  type: string;
  content: string;
  metadata: string | null;
  created_at: string;
}

export interface SummaryRow {
  id: number;
  session_id: string;
  summary: string;
  created_at: string;
}

export interface FtsSearchRow extends ObservationRow {
  rank: number;
}

// ============================================
// Tasks Backlog Types
// ============================================

/**
 * Priority levels for backlog tasks
 */
export type BacklogPriority = 'critical' | 'important' | 'suggestion';

/**
 * Status of a backlog task
 */
export type BacklogStatus = 'pending' | 'in_progress' | 'completed' | 'deleted';

/**
 * Source of a backlog task
 */
export type BacklogSource = 'project' | 'review' | 'manual';

/**
 * A task in the backlog
 */
export interface BacklogTask {
  id: number;
  source: BacklogSource;
  priority: BacklogPriority;
  title: string;
  description: string | null;
  filePath: string | null;
  lineNumber: number | null;
  status: BacklogStatus;
  createdAt: string;
  completedAt: string | null;
  metadata: Record<string, unknown> | null;
}

/**
 * Input for creating a new backlog task
 */
export interface NewBacklogTask {
  source: BacklogSource;
  priority: BacklogPriority;
  title: string;
  description?: string;
  filePath?: string;
  lineNumber?: number;
  metadata?: Record<string, unknown>;
}

/**
 * Filter options for querying backlog tasks
 */
export interface BacklogFilter {
  source?: BacklogSource;
  priority?: BacklogPriority;
  status?: BacklogStatus;
  since?: string;
  limit?: number;
  offset?: number;
}

/**
 * Database row type for backlog tasks (internal)
 */
export interface BacklogTaskRow {
  id: number;
  source: string;
  priority: string;
  title: string;
  description: string | null;
  file_path: string | null;
  line_number: number | null;
  status: string;
  created_at: string;
  completed_at: string | null;
  metadata: string | null;
}
