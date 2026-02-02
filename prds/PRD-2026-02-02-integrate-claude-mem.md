# PRD: Integrate Claude-Mem into Orchestrator

## 1. Executive Summary

Integrate the claude-mem persistent memory system into the claude-orchestrator to enable workers to maintain context across sessions and to provide the orchestrator with memory of past worker activities, decisions, and outcomes. This integration will leverage claude-mem's SQLite-based storage, AI-powered compression, and semantic search to enhance worker coordination and knowledge persistence.

## 2. Goals & Success Criteria

- [ ] Workers can store observations about their work to a shared memory system
- [ ] Orchestrator can query past session context when making decisions
- [ ] Memory is persisted across orchestrator restarts
- [ ] `/mem-search` command allows natural language queries of worker history
- [ ] Memory integrates seamlessly with existing worker state management
- [ ] Build passes (`npm run build`)
- [ ] Type-check passes (`npm run type-check`)
- [ ] Tests pass (`npm run test`)
- [ ] Memory service starts with orchestrator serve command

## 3. Technical Requirements

### Integration Approach

We will implement a **lightweight integration** that:
1. Uses SQLite (via `better-sqlite3`) for persistence, mirroring claude-mem's approach
2. Provides a MemoryService class that the orchestrator can use
3. Hooks into worker lifecycle events to capture observations
4. Exposes memory search via HTTP API endpoints
5. Does NOT require Bun or the full claude-mem worker service

### Files to Create

- `src/memory/index.ts` - Memory module exports
- `src/memory/memory-service.ts` - Core MemoryService class
- `src/memory/database.ts` - SQLite database initialization and migrations
- `src/memory/types.ts` - TypeScript types for memory entities
- `src/memory/observation-store.ts` - Store for worker observations
- `src/memory/session-store.ts` - Store for orchestrator sessions
- `src/memory/search.ts` - Memory search functionality
- `src/__tests__/memory/memory-service.test.ts` - Unit tests
- `commands/mem-search.md` - Memory search slash command

### Files to Modify

- `src/index.ts` - Export memory module
- `src/server.ts` - Add memory API endpoints
- `src/orchestrator.ts` - Integrate memory capture on worker events
- `src/worker-manager.ts` - Capture observations on worker state changes
- `src/types.ts` - Add memory-related types
- `package.json` - Add `better-sqlite3` dependency

### Dependencies

- `better-sqlite3` - Fast, synchronous SQLite3 binding for Node.js
- `@types/better-sqlite3` - TypeScript types (devDependency)

## 4. Worker Task Breakdown

### Worker 1: memory-db
- **Task**: Create SQLite database layer with migrations and core types. Implement Database class with initialization, migrations table, and schema for sessions/observations/summaries.
- **Owns**: `src/memory/database.ts`, `src/memory/types.ts`, `src/memory/index.ts`
- **Off-limits**: `src/server.ts`, `src/orchestrator.ts`, `src/worker-manager.ts`, existing files
- **Depends on**: none

### Worker 2: memory-stores
- **Task**: Implement ObservationStore and SessionStore classes with CRUD operations for storing and retrieving worker observations and orchestrator sessions.
- **Owns**: `src/memory/observation-store.ts`, `src/memory/session-store.ts`
- **Off-limits**: `src/server.ts`, `src/orchestrator.ts`, existing files outside memory/
- **Depends on**: memory-db

### Worker 3: memory-service
- **Task**: Create MemoryService facade class that coordinates database, stores, and search. Implement lifecycle methods (start, stop, captureObservation, search).
- **Owns**: `src/memory/memory-service.ts`, `src/memory/search.ts`
- **Off-limits**: `src/server.ts`, `src/orchestrator.ts`, existing files outside memory/
- **Depends on**: memory-stores

### Worker 4: memory-integration
- **Task**: Integrate MemoryService into orchestrator and server. Add memory API endpoints. Hook worker lifecycle to capture observations. Update exports.
- **Owns**: Modifications to `src/server.ts`, `src/orchestrator.ts`, `src/worker-manager.ts`, `src/index.ts`, `src/types.ts`, `package.json`
- **Off-limits**: Files in `src/memory/` (those are owned by other workers)
- **Depends on**: memory-service

### Worker 5: memory-tests-commands
- **Task**: Write comprehensive tests for memory service. Create /mem-search slash command documentation.
- **Owns**: `src/__tests__/memory/`, `commands/mem-search.md`
- **Off-limits**: Implementation files (src/memory/*.ts, src/server.ts, etc.)
- **Depends on**: memory-integration

## 5. Architecture Design

### Database Schema

```sql
-- Sessions table (orchestrator sessions, not Claude sessions)
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  worker_count INTEGER DEFAULT 0,
  summary TEXT,
  metadata TEXT -- JSON
);

-- Observations table
CREATE TABLE observations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  worker_id TEXT NOT NULL,
  type TEXT NOT NULL, -- 'state_change', 'pr_event', 'error', 'task_complete', 'custom'
  content TEXT NOT NULL,
  metadata TEXT, -- JSON
  created_at TEXT NOT NULL,
  FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- Summaries table (compressed session summaries)
CREATE TABLE summaries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  summary TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- Full-text search index
CREATE VIRTUAL TABLE observations_fts USING fts5(
  content,
  content=observations,
  content_rowid=id
);
```

### API Endpoints

```
GET  /api/memory/search?q=<query>&limit=<n>  - Search observations
GET  /api/memory/sessions                     - List recent sessions
GET  /api/memory/sessions/:id                 - Get session details
GET  /api/memory/observations?worker=<id>    - Get observations for worker
POST /api/memory/observations                 - Add custom observation
```

### Memory Service Interface

```typescript
interface MemoryService {
  // Lifecycle
  initialize(): Promise<void>;
  shutdown(): Promise<void>;

  // Sessions
  startSession(): Promise<string>;
  endSession(sessionId: string, summary?: string): Promise<void>;

  // Observations
  captureObservation(obs: NewObservation): Promise<number>;
  getObservations(filter: ObservationFilter): Promise<Observation[]>;

  // Search
  search(query: string, options?: SearchOptions): Promise<SearchResult[]>;
}
```

## 6. Verification Plan

How to verify the project is complete:

- [ ] `npm install` succeeds with new dependencies
- [ ] `npm run build` completes without errors
- [ ] `npm run type-check` passes
- [ ] `npm run test` passes including new memory tests
- [ ] Start server with `npm run serve`, verify `/api/memory/search` responds
- [ ] Spawn a worker, verify observations are captured in SQLite
- [ ] Stop worker, verify final observation recorded
- [ ] Search observations via API endpoint
- [ ] Restart server, verify memory persists
- [ ] `/mem-search` command documentation exists

## 7. Non-Goals (Out of Scope)

- **Vector/semantic search**: FTS5 keyword search is sufficient for v1
- **AI compression**: No automatic summarization in v1 (can add later)
- **Chroma integration**: Not needed for initial integration
- **Claude-mem plugin compatibility**: We build our own lightweight version
- **Web UI viewer**: CLI and API are sufficient for now
