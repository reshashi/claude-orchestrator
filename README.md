# Claude Code Orchestrator

> Automated delivery pipeline for Claude Code. PR creation, CI monitoring, quality gates, and merge — hands-free.

[![Cross-Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue.svg)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-4.0.0--alpha.4-green.svg)](https://github.com/reshashi/claude-orchestrator/releases/latest)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18.0.0-brightgreen.svg)](https://nodejs.org/)

---

## TL;DR

**What it does:** Watches your open PRs and automatically runs them through CI, quality gates, and merge. Also provides parallel Claude Code workers via git worktrees.

**How it works:** A delivery pipeline state machine tracks each PR through `WORKING → PR_CREATING → CI_RUNNING → REVIEWING → APPROVED → MERGING → MERGED`. Quality agents review every PR. Stall detection catches stuck work.

**How to use it:**

```bash
# Install
git clone https://github.com/reshashi/claude-orchestrator.git ~/.claude-orchestrator
cd ~/.claude-orchestrator && bash install.sh -y

# Use (from inside Claude Code)
/deliver feature/my-branch      # Push a branch through the delivery pipeline
/project "Add user auth"        # Full autonomous mode: plan → spawn → deliver
/status                         # See pipeline state + active deliveries
/backlog list                   # View tracked suggestions and future work
```

---

## What Problem Does This Solve?

**The pain:** You open 5 iTerm tabs, run `/project` in each one, and everything falls apart. Every project writes to the same repo checkout, so files get stomped. They all share a single `project-state.json`, so whichever project writes last wins. When PRs start landing, each merge shifts `main` out from under the others — causing cascading merge conflicts, failed CI, and hours of manual cleanup. The more tabs you open, the worse it gets.

**The fix:** Claude Orchestrator gives each `/project` its own git worktree, its own state file, and feeds all PRs through a merge queue that auto-rebases before merging. You open N tabs, run `/project` in each, and everything just works.

Beyond multi-project isolation, Claude Code Agent Teams does **not** natively provide:

- **A delivery pipeline** — PR creation, CI monitoring, quality review gates, merge automation
- **Git worktree isolation** — conflict-free parallel branches for write-heavy tasks
- **Persistent quality agents** — QA Guardian, DevOps Engineer, Code Simplifier with review mandates
- **Stall detection** — identify stuck PRs and crashed sessions
- **Task Backlog** — SQLite database for tracking suggestions and future work

Claude Orchestrator v4.0 fills these gaps. It integrates with Agent Teams when available, and works standalone when not.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  CLAUDE-ORCHESTRATOR v4.0                                    │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Delivery   │  │   Worktree   │  │  Automation  │       │
│  │   Pipeline   │  │  Isolation   │  │    Loop      │       │
│  │              │  │              │  │              │       │
│  │ PR → CI →    │  │ git worktree │  │ Poll PRs     │       │
│  │ Review →     │  │ per worker   │  │ Stall detect │       │
│  │ Merge        │  │              │  │ AT health    │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                 │               │
│  ┌──────┴─────────────────┴─────────────────┴───────┐       │
│  │              Quality Agents                       │       │
│  │  QA Guardian · DevOps · Code Simplifier · Verify  │       │
│  └───────────────────────────────────────────────────┘       │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ Worker 1 │ │ Worker 2 │ │ Worker 3 │
        │ worktree │ │ worktree │ │ worktree │
        │ branch A │ │ branch B │ │ branch C │
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             │             │             │
             ▼             ▼             ▼
           PR #1         PR #2         PR #3
             │             │             │
             └─────────────┼─────────────┘
                           ▼
                    All merged to main
```

### Delivery Pipeline

Every PR goes through a state machine:

| State | What's Happening |
|-------|------------------|
| `WORKING` | Code being written |
| `PR_CREATING` | PR being opened |
| `CI_RUNNING` | GitHub Actions running |
| `REVIEWING` | Quality agents checking code |
| `APPROVED` | All gates passed |
| `MERGING` | PR being merged |
| `MERGED` | Done |
| `BLOCKED` | CI failed or gate blocked |

The delivery pipeline is configured via `config/gates.yaml`:

```yaml
gates:
  qa-guardian:
    enabled: true
    blocking: true       # Must pass to merge
    trigger: always
  devops-engineer:
    enabled: true
    blocking: false      # Advisory only
    trigger:
      files_match:
        - ".github/**"
        - "Dockerfile*"
  code-simplifier:
    enabled: true
    blocking: false
    trigger:
      min_lines_changed: 50
settings:
  merge_method: squash
  delete_branch_on_merge: true
  auto_merge: true
```

### Quality Agents

| Agent | Blocking | Trigger | What it Does |
|-------|----------|---------|--------------|
| **QA Guardian** | Yes | Always | Policy compliance, test coverage, code quality |
| **Security** | Yes | Always | Secret detection, eval/XSS checks, HIPAA compliance |
| **DevOps Engineer** | No | Infra files | CI/CD, Dockerfile, deployment config review |
| **Code Simplifier** | No | 50+ lines | Readability, complexity reduction |
| **Verify App** | Yes | Always | Build, type-check, test verification |

### Stall Detection

The automation loop monitors PR progress and alerts when a delivery stalls:

```yaml
# config/orchestrator.yaml
loop:
  stall_timeout_minutes: 15
  stall_action: notify    # notify | retry | skip
```

When a PR has been in the same state for longer than the timeout, the orchestrator takes the configured action (macOS notification, retry the pipeline stage, or skip it).

### Agent Teams Integration

When Claude Code Agent Teams is enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), the orchestrator:

- Delegates session spawning and task management to Agent Teams
- Provides delivery pipeline capabilities that Agent Teams lacks
- Monitors teammate health (Claude processes, tmux sessions)
- Detects crashed sessions and alerts the user

### Tasks Backlog

All suggestions from code reviews, quality gates, and manual entries are stored in a SQLite database:

```bash
/backlog list                          # View pending tasks
/backlog add "Refactor auth" --priority important
/backlog complete 42
/backlog search "validation"
/backlog stats
```

The `/review` and `/qcode` commands (and their automated counterparts) **always** record findings to the backlog. Future work proposals never get lost.

---

## Installation

### Prerequisites

| Requirement | Why |
|-------------|-----|
| **Bash 4.0+** | Required for associative arrays |
| **Node.js 18+** | Orchestrator runtime |
| **Git 2.20+** | Worktree support |
| **[Claude Code CLI](https://claude.ai/code)** | The AI that does the work |
| **[GitHub CLI](https://cli.github.com/)** | PR automation |

> **macOS users:** macOS ships with Bash 3.2. Install modern Bash:
> ```bash
> brew install bash
> ```

### Install

```bash
git clone https://github.com/reshashi/claude-orchestrator.git ~/.claude-orchestrator
cd ~/.claude-orchestrator
bash install.sh -y
```

The installer:
1. Checks bash 4+ and required tools
2. Builds the TypeScript orchestrator (`npm install && npm run build`)
3. Installs pipeline scripts to `~/.claude-orchestrator/pipeline/`
4. Installs config files to `~/.claude-orchestrator/config/`
5. Sets up shell aliases and commands
6. Migrates any existing v3.x memory data

### Uninstall

```bash
bash ~/.claude-orchestrator/install.sh --uninstall
```

---

## Usage

### Delivery Pipeline

Push any branch through the automated pipeline:

```bash
# From inside Claude Code
/deliver feature/my-branch

# Or from the command line
~/.claude-orchestrator/scripts/orchestrator.sh deliver feature/my-branch
```

The pipeline will:
1. Create a PR (or find an existing one)
2. Poll CI until it passes or fails
3. Run quality agents (QA Guardian, Security, etc.)
4. Merge the PR if all blocking gates pass
5. Record any suggestions to the backlog

### Autonomous Project Mode

Let Claude handle everything:

```bash
/project "Add user authentication with magic links"
```

This creates a PRD, breaks it into tasks, spawns parallel workers in git worktrees, and delivers each one through the pipeline.

### Manual Worker Spawning

```bash
/spawn auth-db "Create users table migration"
/spawn auth-api "Build login API endpoints"
/spawn auth-ui "Create login form component"

/status          # Check all workers and deliveries
/merge auth-ui   # Manually trigger merge
```

### Background Automation Loop

Run the loop to automatically process all open PRs:

```bash
# Start the delivery loop
~/.claude-orchestrator/scripts/orchestrator-loop.sh &

# Check status
~/.claude-orchestrator/scripts/orchestrator-status.sh

# Stop
kill $(cat ~/.claude/orchestrator.pid)
```

The loop:
- Polls for open PRs every 5 seconds (configurable)
- Runs CI monitoring and quality gates
- Auto-merges approved PRs
- Detects stalled deliveries
- Monitors Agent Teams health (when enabled)

---

## Commands Reference

### Claude Code Slash Commands

| Command | Description |
|---------|-------------|
| `/project "desc"` | Full autonomous project execution |
| `/deliver [branch]` | Push a branch through the delivery pipeline |
| `/spawn <name> "task"` | Spawn a worker in a git worktree |
| `/status` | Pipeline state, deliveries, and worker status |
| `/merge <name>` | Merge a worker's PR |
| `/review` | Run QA Guardian review (records findings to backlog) |
| `/backlog [cmd]` | Manage the tasks backlog |
| `/hooks [cmd]` | Install/manage git hooks |
| `/deploy` | Run deployment checklist |
| `/mem-search "query"` | Search worker memory |

### CLI Commands

```bash
# Delivery pipeline
orchestrator.sh deliver <branch>     # Run pipeline for a branch
orchestrator.sh deliveries           # List active deliveries
orchestrator.sh prs                  # List open PRs
orchestrator.sh status <task-id>     # Delivery detail
orchestrator.sh resume <task-id>     # Resume blocked delivery

# Worker management
claude-orchestrator spawn <name> <task>
claude-orchestrator list
claude-orchestrator status [worker]
claude-orchestrator read <worker>
claude-orchestrator send <worker> <msg>
claude-orchestrator stop <worker>
claude-orchestrator merge <worker>

# Automation
orchestrator-loop.sh                 # Start delivery loop
orchestrator-status.sh               # Show loop + delivery status
```

---

## Configuration

### `config/orchestrator.yaml`

```yaml
version: 3
mode: auto                          # auto | agent-teams | pipeline

worktrees:
  base_dir: ~/.worktrees
  auto_cleanup: true

pipeline:
  enabled: true
  gates_config: ~/.claude-orchestrator/config/gates.yaml

loop:
  poll_interval_seconds: 5
  stall_timeout_minutes: 15
  stall_action: notify              # notify | retry | skip

merge_queue:
  enabled: true
  lock_timeout_seconds: 120
  auto_rebase: true
  ci_wait_after_rebase_seconds: 300
  conflict_action: notify             # notify | skip

agent_teams:
  health_check_interval_seconds: 60
  session_timeout_minutes: 30
  auto_restart_crashed: false

backlog:
  enabled: true
  auto_record_review: true
  auto_record_qcode: true
```

### `config/gates.yaml`

Controls which quality agents run, whether they block merges, and their trigger conditions. See the [Quality Agents](#quality-agents) section above.

---

## File Structure

```
~/.claude-orchestrator/
├── bin/
│   └── claude-orchestrator         # Node.js CLI entry point
├── src/                            # TypeScript orchestrator
│   ├── orchestrator.ts             # Main orchestration
│   ├── worker-manager.ts           # Worker process management
│   ├── state-manager.ts            # State persistence
│   ├── mode.ts                     # Mode detection (pipeline/agent-teams)
│   ├── types.ts                    # TypeScript types
│   └── memory/                     # SQLite memory service
├── pipeline/                       # Delivery pipeline scripts
│   ├── run.sh                      # End-to-end pipeline runner
│   ├── delivery-state.sh           # State machine persistence
│   ├── pr-manager.sh               # PR create/merge via gh CLI
│   ├── ci-monitor.sh               # CI polling
│   ├── gate-runner.sh              # Quality gate orchestrator
│   └── agent-registry.sh           # Agent metadata/prompt loader
├── scripts/                        # Orchestrator shell scripts
│   ├── orchestrator-loop.sh        # Background delivery loop
│   ├── orchestrator.sh             # CLI wrapper for pipeline
│   ├── orchestrator-status.sh      # Status display
│   ├── project-state.sh             # Per-project state CRUD + locking
│   ├── merge-queue.sh              # Merge queue with auto-rebase
│   ├── mode-detect.sh              # Mode detection (bash)
│   ├── auto-review.sh              # Heuristic code review
│   ├── auto-qcode.sh               # Heuristic code quality
│   ├── backlog.sh                  # Task backlog CLI
│   ├── memory-*.sh                 # Memory read/write
│   └── logging.sh                  # Structured logging
├── config/                         # Configuration
│   ├── orchestrator.yaml           # Global settings
│   └── gates.yaml                  # Quality gate settings
├── agents/                         # Agent definitions (YAML+MD)
│   ├── qa-guardian.md              # QA specialist
│   ├── devops-engineer.md          # Infrastructure reviewer
│   ├── code-simplifier.md          # Complexity reducer
│   └── verify-app.md               # Build/test verifier
├── commands/                       # Claude Code slash commands
│   ├── deliver.md                  # /deliver
│   ├── review.md                   # /review
│   ├── backlog.md                  # /backlog
│   ├── status.md                   # /status
│   └── ...
├── templates/                      # Hook and workflow templates
├── tests/                          # Test suites
│   ├── test-pipeline.sh            # Pipeline tests (94 tests)
│   └── test-memory.sh              # Memory tests (10 tests)
├── install.sh                      # Installer
├── uninstall.sh                    # Uninstaller
└── version                         # Current version
```

---

## Migrating from v3.x

v4.0 removes the iTerm2/AppleScript dependency and replaces the tab-based worker model with a delivery pipeline.

### What Changed

| v3.x | v4.0 |
|------|------|
| iTerm2 required | Any terminal (no iTerm dependency) |
| Tab-based worker management | Background process workers |
| Inline PR/CI/merge logic | Dedicated pipeline scripts |
| Manual quality review | Automated quality gates |
| `legacy` mode | `pipeline` mode (default) |
| Suggestions printed to console | Suggestions persisted to backlog |

### Migration Steps

1. **Update**: `cd ~/.claude-orchestrator && git pull && bash install.sh --update`
2. **Memory**: Existing 3-tier memory is preserved automatically
3. **Backlog**: Existing SQLite backlog database is preserved
4. **Hooks**: Re-run `/hooks install` in your projects to update git hooks
5. **Config**: Review `config/orchestrator.yaml` for new v3 settings

### Removed Scripts

These iTerm-specific scripts were removed:
- `window-utils.sh`, `start-worker.sh`, `start-all-workers.sh`
- `worker-init.sh`, `worker-read.sh`, `worker-send.sh`, `worker-status.sh`

---

## Troubleshooting

### Delivery pipeline stuck

```bash
# Check pipeline state
~/.claude-orchestrator/scripts/orchestrator.sh deliveries

# Check specific delivery
~/.claude-orchestrator/pipeline/delivery-state.sh get <task-id>

# Resume a blocked delivery
~/.claude-orchestrator/scripts/orchestrator.sh resume <task-id>
```

### CI not detected

```bash
# Verify gh CLI is authenticated
gh auth status

# Check PR status manually
gh pr checks <pr-number>
```

### Quality gates failing

```bash
# Run gates manually
~/.claude-orchestrator/pipeline/gate-runner.sh run-all <pr-number> <branch>

# Check gate config
cat ~/.claude-orchestrator/config/gates.yaml
```

### Backlog issues

```bash
# Check backlog database
~/.claude/scripts/backlog.sh stats

# Search for specific items
~/.claude/scripts/backlog.sh search "auth"
```

### Build errors

```bash
cd ~/.claude-orchestrator
npm run clean && rm -rf node_modules
npm install && npm run build
```

---

## Release Notes

### v4.0.0-alpha.4 (Current)

**Multi-Project Isolation & Merge Queue**

- **Per-project worktrees** — each `/project` gets its own git worktree, so concurrent projects never touch the same files
- **Per-project state** — `~/.claude/projects/{id}/state.json` replaces the singleton `project-state.json`, eliminating overwrite races
- **Merge queue with auto-rebase** — PRs merge sequentially through a lock; branches auto-rebase onto latest `main` via GitHub API (with local fallback)
- **Conflict detection** — merge conflicts are caught and reported with file lists instead of silently failing
- **Orchestrator loop** scans all active projects, uses merge queue, migrates legacy state at startup
- `/spawn` detects project context and branches off the project branch
- `/merge` auto-rebases before merging
- `/status` shows active projects table
- Backlog enforcement across all worktrees
- 27 new tests (94 total)

### v4.0.0-alpha.2

**Backlog Enforcement + Phase 3**

- `/review` and `/qcode` now always record findings to the Task Backlog database
- Stall detection in the automation loop (configurable timeout + notify/retry/skip)
- Agent Teams health monitoring (Claude process + tmux session checks)
- Config v3 with new stall, agent-teams, and backlog sections
- TypeScript mode detection updated (legacy -> pipeline)

### v4.0.0-alpha.1

**Delivery Pipeline + iTerm Removal**

- Delivery pipeline: PR creation, CI monitoring, quality gates, merge automation
- Removed all iTerm2/AppleScript dependencies (7 scripts deleted)
- New pipeline scripts: `run.sh`, `delivery-state.sh`, `pr-manager.sh`, `ci-monitor.sh`, `gate-runner.sh`, `agent-registry.sh`
- Config-driven quality gates via `gates.yaml`
- `/deliver` command for manual pipeline trigger
- Mode detection: `pipeline` (default) and `agent-teams` (experimental)

### v3.5.0

- SQLite Tasks Backlog Database
- Automated quality enforcement via git hooks
- Heuristic quality scripts (auto-review.sh, auto-qcode.sh)
- `/backlog` and `/hooks` commands

### v3.4.0

- CI fix + release (all PRs merged, build green)
- 3-tier memory + bash 4+ requirement + migration

### v3.2.0

- Persistent memory system (SQLite, FTS5 search)

### v3.1.0

- HTTP API server + Moltbot integration

### v3.0.0

- Cross-platform Node.js rewrite (replaced bash/AppleScript)

### v2.0.0

- Autonomous planner (`/project` command)

### v1.0.0

- Initial release (git worktrees + iTerm automation)

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-thing`
3. Make your changes
4. Run checks: `bash tests/test-pipeline.sh && bash tests/test-memory.sh && npm run test:run`
5. Submit a pull request

---

## License

MIT — see [LICENSE](LICENSE)

---

## Acknowledgments

- [Boris Cherny](https://x.com/bcherny) — Creator of Claude Code and the parallel development patterns that inspired this project
- [Alex Newman / thedotmack](https://github.com/thedotmack/claude-mem) — Creator of claude-mem, whose persistent memory system inspired the memory integration
- [Anthropic](https://anthropic.com) — Claude AI

---

## Questions?

- **Issues**: [GitHub Issues](https://github.com/reshashi/claude-orchestrator/issues)
- **Discussions**: [GitHub Discussions](https://github.com/reshashi/claude-orchestrator/discussions)
