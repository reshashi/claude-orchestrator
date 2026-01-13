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

### Improved

- Better integration of QA Guardian, DevOps Engineer, and Code Simplifier agents
- More thorough quality checks throughout the development lifecycle
- Agents now run at multiple checkpoints: pre-PR (worker), post-CI (orchestrator), and post-merge (planner)

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
