## [2.4] - 2026-01-14

### Added

- **Memory System**: Persistent memory across Claude sessions
  - `~/.claude/memory/toolchain.json` - Track tools and CLIs you use
  - `~/.claude/memory/repos.json` - Track repositories you work with
  - `~/.claude/memory/facts.json` - Store facts the orchestrator should remember
  - `~/.claude/memory/projects/` - Per-project persistent context
  - `~/.claude/memory/sessions/` - Session handoff summaries for continuity

- **`/assistant` Command**: Meta-task delegation for the orchestrator
  - `/assistant remember "fact"` - Store facts to persistent memory
  - `/assistant recall "topic"` - Search memory for relevant facts
  - `/assistant toolchain add/list` - Manage toolchain registry
  - `/assistant repos add/list` - Manage repository registry
  - `/assistant session-end` - Generate session handoff summary

- **`orchestrator-assistant` Agent**: Lightweight Haiku-based assistant for memory management

- **Memory Scripts**: Bash utilities for memory operations
  - `memory-read.sh` - Read from memory files
  - `memory-write.sh` - Write to memory files
  - `session-summary.sh` - Generate session summaries

### Changed

- `install.sh` now creates `~/.claude/memory/` directory structure
- Memory templates are copied on first install

---

## [2.3] - 2026-01-14

### Added

- **`claude-orchestrator` Command**: New wrapper to start Claude as the orchestrator
  - Automatically captures the current iTerm window ID
  - Pre-loads orchestrator context so you don't need to remind Claude of its role
  - Usage: `claude-orchestrator [repo-name]`

- **Window-Scoped Tab Management**: Workers now spawn in the orchestrator's window only
  - Each iTerm window can have its own orchestrator for different projects
  - No more tabs appearing in random windows
  - Window ID stored in `~/.claude/orchestrator-window-id`
  - New `window-utils.sh` utility with window-scoped AppleScript functions

- **Structured JSON Logging**: All orchestrator events now logged in JSON Lines format
  - New `logging.sh` utility with typed event functions
  - Logs written to `~/.claude/logs/orchestrator.jsonl`
  - Backward compatible text logs still written to `~/.claude/orchestrator.log`
  - Event types: worker_state_change, pr_detected, review_started, agent_completed, etc.

- **Prometheus Metrics Endpoint**: `/metrics` endpoint for monitoring integration
  - New `metrics.sh` utility for counter/gauge/histogram tracking
  - New `metrics-server.sh` lightweight HTTP server on port 9090
  - Counters: projects_total, workers_spawned, prs_merged, reviews_passed, etc.
  - Gauges: active_workers, active_projects, orchestrator_up
  - Histograms: prd_generation_seconds, worker_execution_seconds, review_seconds

- **Cost Tracking**: Claude API usage estimation and budget alerts
  - New `cost-tracker.sh` utility for tracking token usage
  - Per-project cost files in `~/.claude/costs/`
  - Model-specific pricing (Opus, Sonnet, Haiku)
  - Budget alert notifications when threshold exceeded
  - Functions: `record_usage`, `get_project_summary`, `generate_cost_report`

- **Web Dashboard**: Real-time monitoring UI
  - New `dashboard/` directory with HTML/JS dashboard
  - New `start-dashboard.sh` launcher script
  - Live metrics display with auto-refresh
  - Worker status cards with state visualization
  - Cost breakdown panel
  - Streaming log viewer

- **Documentation**: New `docs/OBSERVABILITY.md` guide covering all observability features

### Changed

- `orchestrator-loop.sh` now sources `logging.sh` for structured logging
- All major orchestrator events emit both JSON and text logs
- Log functions are backward compatible - existing log() calls still work

### Technical Details

- JSON log schema defined in `schemas/log-event.json`
- Prometheus metrics schema in `schemas/metrics.json`
- Cost summary template in `templates/cost-summary.md`

## [2.2] - 2026-01-13

### Fixed
- **Focus-stealing fix**: Orchestrator no longer steals window focus when sending input to workers
  - Removed `activate` commands from AppleScript
  - Removed `System Events` keystroke approach that required focus
  - Now uses iTerm's `write text` directly which works without activating the window
  - Users can now work in other applications while orchestrator runs in background

- **WORKER.md filename mismatch**: Fixed reference from `WORKER.md` to `WORKER_CLAUDE.md` in worker initialization message (line 232)

### Changed
- `send_to_worker()` function simplified - no longer needs delay or keystroke simulation
- `send_enter()` function simplified - uses empty `write text` instead of selecting tab and sending keystroke

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-01-13

### Added

- **Security Scanning on All PRs**: Every PR now gets a security scan (`npm audit`) regardless of files changed
- **Quality Agents in Planner Review Phase**: After all workers merge, the Planner now runs:
  - `/review` (QA Guardian) - Code quality and policy compliance
  - `/qcode` (Code Simplifier) - Clean up combined changes
  - `npm audit` - Security vulnerability scan
  - `/deploy` (DevOps) - Deployment readiness (if infrastructure changed)

### Changed

- **Lowered Code Simplifier Threshold**: Now triggers on 50+ line changes (was 100+)
- **Pre-PR Quality Gates**: Workers are now instructed to run `npm run type-check && npm run lint && npm run test` BEFORE creating a PR
- **Enhanced Agent Completion Detection**: More robust pattern matching for agent output

### Fixed

- **SC2115**: Safe `rm -rf` in wt.sh using `${var:?}` to prevent empty variable expansion
- **SC2155**: Separated local declarations from command substitutions in orchestrator-loop.sh (6 instances)
- **SC2034**: Prefixed unused variables with `_` in orchestrator.sh read loop

### Improved

- Better integration of QA Guardian, DevOps Engineer, and Code Simplifier agents
- More thorough quality checks throughout the development lifecycle
- Agents now run at multiple checkpoints: pre-PR (worker), post-CI (orchestrator), and post-merge (planner)
- All scripts now pass shellcheck without warnings

## [2.0.0] - 2026-01-13

### Added

- **Planner Layer**: New intelligent Planner that sits above the Orchestrator
  - Takes conceptual project descriptions from humans
  - Generates comprehensive PRDs automatically
  - Reviews completed work against requirements
  - Provides iterative feedback (up to 3 iterations)
  - Delivers completion summaries and usage guides

- **`/project` Command**: Single entry point for autonomous project execution
  - Accepts natural language project descriptions
  - Orchestrates the full pipeline: PRD → spawn workers → monitor → review → deliver
  - Fully autonomous - human can walk away after starting

- **Project Mode**: New orchestrator mode for tracking multi-worker projects
  - `project-state.json` for tracking project status, workers, and iterations
  - Automatic completion detection when all workers merge
  - macOS + terminal bell notifications on completion

- **Templates Directory**: Structured templates for consistent output
  - `prd-template.md` - PRD structure with worker task breakdown
  - `summary-template.md` - Completion summary with usage guides

- **Planner Agent** (`agents/planner.md`): Agent definition for project planning
  - Uses Claude Opus for deep reasoning
  - Handles PRD generation and work review

### Changed

- **Improved State Detection** in `orchestrator-loop.sh`
  - Check for "Composing/thinking" state first to avoid interrupting Claude
  - Better PR URL pattern matching (detects github.com/.../pull/NNN)
  - Narrowed ERROR detection to only Claude/system errors (API errors, connection failures)
  - No longer triggers false ERROR on build/test failures that workers handle autonomously

- **Fixed Message Submission** in `orchestrator.sh`
  - Added explicit `keystroke return` after `write text` to ensure messages are submitted
  - Resolves issue where workers would get stuck waiting for newline character

### Fixed

- Workers no longer get stuck waiting for newline character when orchestrator sends messages
- Orchestrator no longer interrupts workers with false ERROR detection on build failures
- Workers can now handle "command not found" and "Exit code 127" errors autonomously

## [1.0.0] - 2026-01-10

### Added

- Initial release
- Orchestrator loop with 7-state worker tracking
- iTerm automation via AppleScript
- Git worktree management for isolated development
- Slash commands: `/spawn`, `/plan`, `/status`, `/merge`, `/review`, `/deploy`
- Quality agents: QA Guardian, DevOps Engineer, Code Simplifier
- Automatic PR creation and CI monitoring
- Worker initialization and coordination
