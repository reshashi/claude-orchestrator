/**
 * Claude Orchestrator
 *
 * Cross-platform Claude Code worker orchestration.
 */

// Export main classes
export { Orchestrator } from './orchestrator.js';
export { WorkerManager } from './worker-manager.js';
export { StateManager } from './state-manager.js';
export { GitHub } from './github.js';

// Export utilities
export { createLogger, createSilentLogger } from './logger.js';
export { createJsonlParser, parseJsonlLine } from './jsonl-parser.js';
export * from './state-machine.js';

// Export types
export type {
  WorkerState,
  WorkerConfig,
  WorkerInstance,
  WorkerEvent,
  WorkerRegistry,
  PersistedWorkerState,
  ClaudeMessage,
  PrStatus,
  OrchestratorConfig,
  Logger,
  AgentType,
  ReviewStatus,
} from './types.js';

// CLI entry point
export { createCli } from './cli.js';
