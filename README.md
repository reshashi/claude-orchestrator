# Claude Code Orchestrator

> Parallel development superpowers for Claude Code. One orchestrator, many workers.

[![macOS](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.1.0-green.svg)](https://github.com/reshashi/claude-orchestrator/releases)

Based on [Boris Cherny's patterns](https://x.com/bcherny) (creator of Claude Code).

## What is this?

Claude Code Orchestrator enables **parallel AI development** by:

- **Taking conceptual project descriptions** and turning them into executed code
- **Generating comprehensive PRDs** with worker task breakdowns
- **Spawning multiple Claude sessions** as independent workers
- **Isolating each worker in git worktrees** (no merge conflicts)
- **Automating the full pipeline** (PRD → spawn → monitor → review → merge → deliver)
- **Built-in quality agents** (QA Guardian, DevOps Engineer, Code Simplifier)

## NEW in v2.0: Autonomous Planner Layer

**Give Claude a concept. Walk away. Come back to working code.**

```
┌─────────────────────────────────────────────────────────────┐
│   HUMAN: "/project Add user authentication with OAuth"      │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    PLANNER (New in v2.0)                    │
│  - Generates comprehensive PRD                              │
│  - Creates worker task breakdown                            │
│  - Reviews completed work                                   │
│  - Iterates with feedback (up to 3x)                        │
│  - Delivers summary + usage guide                           │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 ORCHESTRATOR                                │
│  - Creates worktrees for each task                          │
│  - Spawns workers in iTerm tabs                             │
│  - Monitors every 5 seconds                                 │
│  - Coordinates work, prevents conflicts                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ Worker 1 │ │ Worker 2 │ │ Worker 3 │
        │ auth-db  │ │ auth-api │ │ auth-ui  │
        └──────────┘ └──────────┘ └──────────┘
```

### Autonomous Project Execution

```bash
# Just describe what you want
/project "Add a dark mode toggle that persists user preference to localStorage"

# Claude will:
# 1. Generate a PRD with success criteria
# 2. Break it into worker tasks
# 3. Spawn workers in parallel
# 4. Monitor progress
# 5. Review against requirements
# 6. Iterate if needed (up to 3x)
# 7. Notify you when complete

# You come back to:
# - Working code merged to master
# - Summary with usage guide
# - macOS notification when done
```

## Quick Start

```bash
# 1. Install (one command)
curl -fsSL https://raw.githubusercontent.com/reshashi/claude-orchestrator/main/install.sh | bash

# 2. Restart your terminal
source ~/.zshrc

# 3. Start Claude in your project
cd your-project && claude

# 4. Run a full project autonomously
/project "Add user authentication with magic links"

# OR spawn workers manually
/spawn auth "implement user authentication"
/spawn api "create REST API endpoints"

# 5. Monitor progress
/status
```

## Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | Required (uses iTerm2 + AppleScript) |
| **[iTerm2](https://iterm2.com/)** | Required for multi-tab automation |
| **Git 2.20+** | Required for worktree support |
| **[Claude Code CLI](https://claude.ai/code)** | Required |
| **[GitHub CLI](https://cli.github.com/)** | Optional (for PR automation) |
| **jq** | Required for project state management |

## Installation

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/reshashi/claude-orchestrator/main/install.sh | bash
```

### Manual install

```bash
git clone https://github.com/reshashi/claude-orchestrator ~/.claude-orchestrator
~/.claude-orchestrator/install.sh
```

### Update

```bash
~/.claude-orchestrator/install.sh --update
```

### Uninstall

```bash
~/.claude-orchestrator/uninstall.sh
```

## Commands

### Slash Commands (use inside Claude)

| Command | Description |
|---------|-------------|
| `/project "description"` | **NEW** Full autonomous project execution |
| `/spawn <name> "task"` | Create worktree + start worker in new tab |
| `/status` | Check all worktrees, workers, and PRs |
| `/workers list` | List active worker tabs |
| `/workers read <tab>` | Read output from a worker tab |
| `/merge <name>` | Merge worker branch and cleanup worktree |
| `/plan "description"` | Create work breakdown for parallel execution |
| `/review` | Run QA Guardian agent on open PRs |
| `/deploy` | Run DevOps Engineer deployment checks |

### Shell Aliases (use in terminal)

| Alias | Description |
|-------|-------------|
| `wt create <repo> <name>` | Create git worktree manually |
| `wt list <repo>` | List worktrees for a repo |
| `wt remove <repo> <name>` | Remove worktree |
| `workers` | Master orchestrator control script |
| `orchestrator-start` | Start fully automated orchestrator loop |
| `orchestrator-stop` | Stop the orchestrator loop |
| `orchestrator-status` | Check if orchestrator is running |

## Built-in Agents

| Agent | Trigger | Purpose |
|-------|---------|---------|
| **Planner** | `/project` | PRD generation, work review, iterative feedback |
| **QA Guardian** | `/review` | Code quality, test coverage, policy compliance |
| **DevOps Engineer** | `/deploy` | CI/CD, infrastructure, deployment verification |
| **Code Simplifier** | `/qcode` | Clean up complex code, improve readability |
| **Verify App** | Manual | End-to-end verification and smoke tests |

### Agent Execution Flow (v2.1.0)

Agents run automatically at multiple checkpoints:

```
┌─────────────────────────────────────────────────────────────┐
│  1. PRE-PR (Worker)                                         │
│     - npm run type-check                                    │
│     - npm run lint                                          │
│     - npm run test                                          │
│     Workers must pass these BEFORE creating a PR            │
└─────────────────────────┬───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  2. POST-CI (Orchestrator)                                  │
│     After CI passes on a PR:                                │
│     - /review (QA Guardian) - Always                        │
│     - npm audit (Security) - Always                         │
│     - /qcode (Simplifier) - If 50+ lines changed            │
│     - /deploy (DevOps) - If infrastructure files changed    │
│     All required agents must pass before auto-merge         │
└─────────────────────────┬───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  3. POST-MERGE (Planner)                                    │
│     After all workers merge, Planner runs:                  │
│     - /review - Final quality check on combined changes     │
│     - /qcode - Clean up any redundancy from parallel work   │
│     - npm audit - Security scan                             │
│     - /deploy - Deployment readiness (if applicable)        │
│     Issues found here trigger a new iteration               │
└─────────────────────────────────────────────────────────────┘
```

### Agent Thresholds

| Agent | Threshold | Description |
|-------|-----------|-------------|
| **QA Guardian** | Always | Runs on every PR |
| **Security Scan** | Always | `npm audit` on every PR |
| **Code Simplifier** | 50+ lines | PRs with 50+ lines changed |
| **DevOps Engineer** | Infra files | `.github/`, `vercel.json`, `supabase/`, `Dockerfile`, etc. |

## Usage Patterns

### Autonomous Project (NEW in v2.0)

Let Claude handle everything from concept to completion:

```bash
# Single command to execute a full project
/project "Implement a rate limiter middleware that:
- Limits to 100 requests per minute per IP
- Returns 429 Too Many Requests when exceeded
- Stores counts in Redis"

# Claude will autonomously:
# 1. Generate PRD with success criteria
# 2. Create worker tasks (e.g., middleware, redis-client, tests)
# 3. Spawn workers in parallel
# 4. Monitor and coordinate
# 5. Review against PRD requirements
# 6. Iterate if requirements not met (max 3 times)
# 7. Generate summary and usage guide
# 8. Notify you via macOS notification + terminal bell
```

### Manual Orchestration

You control when workers spawn, what they work on, and when to merge:

```bash
# In Claude (orchestrator session)
/spawn auth-db "Create users table migration"
/spawn auth-api "Implement login/logout API routes"
/spawn auth-ui "Build login form component"

# Monitor workers
/workers list
/workers read 2

# When PRs are ready
/review           # QA Guardian reviews
gh pr merge 1     # Merge when approved
```

### Fully Automated Orchestration

The orchestrator loop handles everything automatically:

```bash
# Start the automation loop (runs in background)
orchestrator-start

# The loop will:
# - Initialize workers when Claude prompts appear
# - Answer MCP/trust prompts automatically
# - Monitor PRs for CI status
# - Run /review when CI passes
# - Run /deploy for infrastructure changes
# - Auto-merge when all checks pass
# - Close tabs when workers complete

# Check status
orchestrator-status

# Stop when done
orchestrator-stop
```

### Worker Role

Each worker automatically:

1. Reads its task from the spawn command
2. Works on an isolated feature branch in its worktree
3. Creates a PR when the task is complete
4. **Does NOT merge** (orchestrator handles merging)

## Project State (v2.0)

When using `/project`, state is tracked in `~/.claude/project-state.json`:

```json
{
  "project_name": "rate-limiter",
  "prd_path": "/path/to/prds/PRD-2026-01-13-rate-limiter.md",
  "status": "workers_active",
  "iteration": 1,
  "max_iterations": 3,
  "workers": [
    {"name": "middleware", "tab": 2, "status": "working"},
    {"name": "redis-client", "tab": 3, "status": "pr_open"},
    {"name": "tests", "tab": 4, "status": "merged"}
  ],
  "started_at": "2026-01-13T10:00:00Z"
}
```

Project states: `conceptualizing` → `spawning_workers` → `workers_active` → `all_merged` → `reviewing` → `complete`

## Project Configuration

Add permissions to your project's `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/scripts/*)",
      "Bash(git worktree:*)",
      "Bash(osascript:*)",
      "Bash(gh pr:*)",
      "Bash(jq:*)",
      "Skill(project)",
      "Skill(review)",
      "Skill(deploy)",
      "Skill(code-simplifier)",
      "SlashCommand(/spawn:*)",
      "SlashCommand(/workers:*)",
      "SlashCommand(/status:*)",
      "SlashCommand(/merge:*)",
      "SlashCommand(/project:*)"
    ]
  }
}
```

## Directory Structure

After installation:

```
~/.claude-orchestrator/        # Package source (for updates)
├── install.sh
├── uninstall.sh
├── version
├── CHANGELOG.md
├── scripts/
├── commands/
├── agents/
└── templates/                 # NEW in v2.0
    ├── prd-template.md
    └── summary-template.md

~/.claude/                     # Claude Code directory
├── scripts/                   # Symlinked scripts
│   ├── orchestrator.sh
│   ├── orchestrator-loop.sh
│   ├── start-worker.sh
│   └── wt.sh
├── commands/                  # Slash commands
│   ├── project.md             # NEW in v2.0
│   ├── spawn.md
│   ├── status.md
│   └── review.md
├── agents/                    # Built-in agents
│   ├── planner.md             # NEW in v2.0
│   ├── qa-guardian.md
│   ├── devops-engineer.md
│   └── code-simplifier.md
└── project-state.json         # NEW in v2.0

~/.worktrees/                  # Git worktrees
└── <repo-name>/
    ├── <worker-1>/           # feature/<worker-1> branch
    ├── <worker-2>/           # feature/<worker-2> branch
    └── ...

<your-project>/prds/           # Generated PRDs (NEW in v2.0)
└── PRD-YYYY-MM-DD-project-name.md
```

## How It Works

1. **Planner Layer (v2.0)**: Takes conceptual descriptions, generates PRDs with worker task breakdowns, reviews completed work, and iterates if requirements aren't met.

2. **Worktree Isolation**: Each worker operates in its own git worktree with a dedicated feature branch. This prevents merge conflicts between parallel workers.

3. **iTerm Automation**: Uses AppleScript to open new iTerm tabs, run Claude in each, and communicate between sessions.

4. **State Machine**: The orchestrator loop tracks each worker's state (NEEDS_INIT, WORKING, PR_OPEN, MERGED) and takes appropriate actions.

5. **Review Pipeline**: Before merging, PRs pass through quality gates:
   - CI must pass
   - QA Guardian reviews code quality
   - DevOps Engineer reviews infrastructure changes
   - Code Simplifier cleans up large PRs

6. **Completion Notification**: macOS notification + terminal bell when project completes.

## Troubleshooting

### Workers not starting

1. Ensure iTerm2 is installed at `/Applications/iTerm.app`
2. Grant Terminal/iTerm accessibility permissions in System Preferences
3. Check that the worktree was created: `wt list <repo>`

### Workers stuck waiting for input

This was fixed in v2.0. The orchestrator now properly submits messages with an explicit Return keystroke.

### False error detection interrupting workers

This was fixed in v2.0. The orchestrator now only triggers ERROR state for actual Claude/system errors (API errors, connection failures), not build/test failures that workers handle autonomously.

### AppleScript errors

macOS may require accessibility permissions:
- System Preferences → Security & Privacy → Privacy → Accessibility
- Add iTerm2 and Terminal to the allowed list

### Commands not found

After installation, restart your terminal or run:
```bash
source ~/.zshrc  # or ~/.bashrc
```

### Git worktree conflicts

If a worktree wasn't cleaned up properly:
```bash
git worktree list
git worktree remove <path> --force
```

### jq not found

Install jq for project state management:
```bash
brew install jq
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run the test workflow locally if possible
5. Submit a pull request

## License

MIT - see [LICENSE](LICENSE)

## Acknowledgments

- [Boris Cherny](https://x.com/bcherny) - Creator of Claude Code and the parallel development patterns
- [Anthropic](https://anthropic.com) - Claude AI
