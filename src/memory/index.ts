/**
 * Memory Module
 *
 * Persistent memory system for the orchestrator.
 * Inspired by claude-mem but implemented as a lightweight integration.
 */

// Export types
export type {
  ObservationType,
  Session,
  NewSession,
  Observation,
  NewObservation,
  Summary,
  NewSummary,
  ObservationFilter,
  SearchOptions,
  SearchResult,
  MemoryConfig,
} from './types.js';

// Export database
export { MemoryDatabase } from './database.js';
export type { DatabaseOptions } from './database.js';

// Export stores
export { SessionStore } from './session-store.js';
export { ObservationStore } from './observation-store.js';

// Export search
export { searchObservations } from './search.js';

// Export main service
export { MemoryService } from './memory-service.js';
