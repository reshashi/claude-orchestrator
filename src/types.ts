/**
 * Core types for Claude Orchestrator
 *
 * Defines the worker lifecycle, message formats, and state management types.
 */

import type { ChildProcess } from 'node:child_process';

// Worker States - matches the state machine from bash implementation
export type WorkerState =
  | 'SPAWNING'      // Process starting
  | 'INITIALIZING'  // Claude loading
  | 'WORKING'       // Actively processing
  | 'PR_OPEN'       // PR created, awaiting review
  | 'REVIEWING'     // QA review in progress
  | 'MERGING'       // PR being merged
  | 'MERGED'        // PR merged, ready for cleanup
  | 'ERROR'         // Something went wrong
  | 'STOPPED';      // Process terminated

// Worker configuration passed at spawn time
export interface WorkerConfig {
  id: string;                    // Unique worker ID (e.g., "auth-flow")
  repoName: string;              // Repository name
  worktreePath: string;          // Path to worktree
  branchName: string;            // Git branch name
  task: string;                  // Task description
  createdAt: Date;               // When worker was created
}

// Runtime worker state
export interface WorkerInstance {
  config: WorkerConfig;
  state: WorkerState;
  process: ChildProcess | null;
  pid: number | null;
  prNumber: number | null;       // GitHub PR number if created
  prUrl: string | null;          // GitHub PR URL
  lastActivity: Date;            // Last output timestamp
  error: string | null;          // Error message if in ERROR state
  reviewStatus: ReviewStatus;    // QA review status
  agentsRun: AgentType[];        // Which agents have completed
}

// Review status tracking
export type ReviewStatus = 'none' | 'pending' | 'passed' | 'failed';

// Agent types that can run on a PR
export type AgentType = 'qa' | 'security' | 'devops' | 'simplifier';

// Persisted worker state (saved to disk)
export interface PersistedWorkerState {
  id: string;
  config: WorkerConfig;
  state: WorkerState;
  pid: number | null;
  prNumber: number | null;
  prUrl: string | null;
  lastActivity: string;          // ISO date string
  error: string | null;
  reviewStatus: ReviewStatus;
  agentsRun: AgentType[];
}

// Registry of all workers (persisted to ~/.claude/workers/registry.json)
export interface WorkerRegistry {
  version: number;               // Schema version for migrations
  workers: Record<string, PersistedWorkerState>;
  lastUpdated: string;           // ISO date string
}

// Claude --print JSON stream message types
export interface ClaudeMessage {
  type: 'system' | 'human' | 'assistant' | 'result';
  message?: AssistantMessage;
  result?: ResultMessage;
  subtype?: string;
}

export interface AssistantMessage {
  id: string;
  type: 'message';
  role: 'assistant';
  content: ContentBlock[];
  model: string;
  stop_reason: string | null;
  stop_sequence: string | null;
  usage: {
    input_tokens: number;
    output_tokens: number;
  };
}

export interface ContentBlock {
  type: 'text' | 'tool_use' | 'tool_result';
  text?: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
}

export interface ResultMessage {
  duration_ms: number;
  duration_api_ms: number;
  is_error: boolean;
  num_turns: number;
  result?: string;
  session_id: string;
  total_cost_usd: number;
}

// Events emitted by workers
export type WorkerEvent =
  | { type: 'state_change'; workerId: string; from: WorkerState; to: WorkerState }
  | { type: 'output'; workerId: string; message: ClaudeMessage }
  | { type: 'error'; workerId: string; error: string }
  | { type: 'pr_detected'; workerId: string; prNumber: number; prUrl: string }
  | { type: 'pr_merged'; workerId: string; prNumber: number }
  | { type: 'review_complete'; workerId: string; result: ReviewStatus }
  | { type: 'process_exit'; workerId: string; code: number | null };

// CLI command types
export type Command =
  | { type: 'spawn'; name: string; task: string; repoName?: string }
  | { type: 'list' }
  | { type: 'status'; workerId?: string }
  | { type: 'send'; workerId: string; message: string }
  | { type: 'read'; workerId: string; lines?: number }
  | { type: 'stop'; workerId: string }
  | { type: 'merge'; workerId: string }
  | { type: 'cleanup'; workerId?: string };

// GitHub PR status
export interface PrStatus {
  number: number;
  url: string;
  state: 'open' | 'closed' | 'merged';
  ciStatus: 'pending' | 'passed' | 'failed' | 'unknown';
  labels: string[];
  additions: number;
  deletions: number;
}

// Orchestrator configuration
export interface OrchestratorConfig {
  pollIntervalMs: number;        // How often to check workers (default: 5000)
  workersDir: string;            // Where to store worker state
  worktreesDir: string;          // Where worktrees are created
  logFile: string;               // Path to log file
  autoMerge: boolean;            // Whether to auto-merge passed PRs
  autoReview: boolean;           // Whether to auto-run QA review
  memory?: MemoryConfig;         // Memory persistence configuration
}

// Memory system configuration
export interface MemoryConfig {
  enabled: boolean;              // Whether to enable memory persistence
  dataDir: string;               // Where to store memory database
  dbPath?: string;               // Optional custom database path
}

// Logger interface
export interface Logger {
  info(message: string, meta?: Record<string, unknown>): void;
  warn(message: string, meta?: Record<string, unknown>): void;
  error(message: string, meta?: Record<string, unknown>): void;
  debug(message: string, meta?: Record<string, unknown>): void;
}
