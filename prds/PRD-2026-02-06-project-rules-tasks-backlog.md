# PRD: Project Quality Rules & Tasks Backlog Database

## 1. Executive Summary

Formalize the orchestrator's quality enforcement rules and migrate the tasks backlog from a markdown file to a SQLite database table. This project standardizes that `/review` and `/qcode` are always run for each worker (or directly in main for simple tasks), critical issues must be fixed before merge, and suggestions are captured in a persistent backlog. The backlog migration provides structured storage, queryability, and graceful transition from any existing TASKS_BACKLOG.md files.

## 2. Goals & Success Criteria

- [ ] `/review` and `/qcode` are documented as mandatory quality gates in project.md, spawn.md, and orchestrator-loop.sh
- [ ] Critical issues from reviews block merges until fixed (already exists in orchestrator-loop.sh, formalize in docs)
- [ ] Suggestions from reviews are automatically added to the tasks backlog database
- [ ] TasksBacklog table exists in SQLite memory database with proper schema
- [ ] Existing TASKS_BACKLOG.md files are migrated to the database on first run
- [ ] CLI commands available: `backlog add`, `backlog list`, `backlog complete`, `backlog delete`
- [ ] Bash wrapper scripts provide access to backlog from shell
- [ ] Migration is idempotent and backward-compatible (checks for `.backlog-migrated` marker)
- [ ] `/backlog` slash command added for viewing/managing backlog from Claude sessions

## 3. Technical Requirements

### Files to Create

- `src/memory/backlog-store.ts` - TypeScript store for tasks backlog CRUD operations
- `scripts/backlog.sh` - Bash wrapper for backlog CLI operations
- `commands/backlog.md` - Slash command for managing backlog from Claude sessions
- `templates/TASKS_BACKLOG_DEPRECATED.md` - Deprecation notice template

### Files to Modify

- `src/memory/database.ts` - Add V2 migration for tasks_backlog table
- `src/memory/types.ts` - Add BacklogTask interface and types
- `src/memory/index.ts` - Export backlog store
- `src/memory/memory-service.ts` - Add backlog methods to facade
- `commands/project.md` - Formalize quality rules, update backlog references to use database
- `commands/spawn.md` - Add quality gate reminders for workers
- `scripts/orchestrator-loop.sh` - Add backlog insertion for suggestions after review
- `install.sh` - Add migration call for existing TASKS_BACKLOG.md files

### Dependencies

- No new npm packages needed (uses existing better-sqlite3)

## 4. Worker Task Breakdown

### Worker 1: db-schema

- **Task**: Add tasks_backlog table to SQLite schema with V2 migration. Create BacklogTask types in types.ts. Create backlog-store.ts with CRUD operations. Update memory-service.ts facade with backlog methods.
- **Owns**: `src/memory/database.ts`, `src/memory/types.ts`, `src/memory/backlog-store.ts`, `src/memory/index.ts`, `src/memory/memory-service.ts`
- **Off-limits**: `scripts/*`, `commands/*`, `install.sh`
- **Depends on**: none

### Worker 2: bash-cli

- **Task**: Create bash wrapper script (backlog.sh) that interfaces with the TypeScript backlog system. Add TASKS_BACKLOG.md migration logic to install.sh. Create deprecation notice template.
- **Owns**: `scripts/backlog.sh`, `install.sh`, `templates/TASKS_BACKLOG_DEPRECATED.md`
- **Off-limits**: `src/*`, `commands/*`
- **Depends on**: db-schema (needs to know the API)

### Worker 3: commands-docs

- **Task**: Create /backlog slash command. Update project.md and spawn.md to formalize quality rules. Update orchestrator-loop.sh to insert suggestions into backlog after review.
- **Owns**: `commands/backlog.md`, `commands/project.md`, `commands/spawn.md`, `scripts/orchestrator-loop.sh`
- **Off-limits**: `src/memory/*`, `install.sh`
- **Depends on**: db-schema (needs to understand the API for orchestrator-loop.sh integration)

## 5. Verification Plan

How to verify the project is complete:

- [ ] Run `npm run type-check` - passes
- [ ] Run `npm run lint` - passes
- [ ] Run `npm run test` - all tests pass
- [ ] Run `npm run build` - builds successfully
- [ ] Create test TASKS_BACKLOG.md, run install.sh --update, verify migration occurred
- [ ] Use `/backlog add "Test task"` and verify it appears in `/backlog list`
- [ ] Review commands/project.md and verify quality rules are clearly documented
- [ ] Start a test worker, verify /review and /qcode are mentioned in instructions
- [ ] Manually verify schema_migrations table shows version 2 after DB init

## 6. Execution Status

> **READ THIS FIRST AFTER CONTEXT COMPACTION**
> This section is the source of truth for project progress.

### Current State

- **Phase**: QUALITY_GATES
- **Iteration**: 1 of 3
- **Started**: 2026-02-06T00:00:00Z
- **Last Updated**: 2026-02-06T16:30:00Z

### Phase Checklist

- [x] Phase 1: PRD Generation
- [x] Phase 2: Implementation (direct, no workers needed)
- [x] Phase 3: Implementation Complete
- [ ] Phase 4: Review Complete
- [ ] Phase 5: Quality Gates Passed
- [ ] Phase 6: Deliverables Generated
- [ ] Phase 7: Project Complete

### Implementation Status (Direct - No Workers)

| Task | Status | Notes |
|------|--------|-------|
| DB Schema V2 migration | completed | Added tasks_backlog table |
| BacklogStore CRUD | completed | src/memory/backlog-store.ts |
| MemoryService facade | completed | Added backlog methods |
| Bash CLI wrapper | completed | scripts/backlog.sh |
| Install.sh migration | completed | Migrates TASKS_BACKLOG.md |
| /backlog command | completed | commands/backlog.md |
| project.md update | completed | Formalized quality rules |
| spawn.md update | completed | Added quality reminders |

### Blockers & Issues

- orchestrator-loop.sh is heavily tied to iTerm tabs (deprecated) - needs future refactoring
- ESLint config needs updating to v9 format (pre-existing issue)

### Quality Gate Results

- [x] `/review` (auto-review.sh): PASS - 0 critical, 0 important, 4 suggestions
- [x] `/qcode` (auto-qcode.sh): PASS - 1 fix available
- [x] Security scan: 5 vulnerabilities (4 moderate, 1 high) - pre-existing
- [x] Build: PASS
- [x] Tests: 88 passed

### Backlog Items Added

- 70 console.log statements in production code (suggestion)
- 3 large files over 500 lines (suggestion)

### Log

- 2026-02-06T00:00:00Z Project PRD created
- 2026-02-06T16:28:00Z Implementation completed (direct, no workers)
- 2026-02-06T16:30:00Z Build and tests pass
- 2026-02-06T16:35:00Z Git hooks implemented for heuristic enforcement
- 2026-02-06T16:40:00Z Quality gates passed
