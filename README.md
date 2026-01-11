# Claude Code Orchestrator

> Parallel development superpowers for Claude Code. One orchestrator, many workers.

[![macOS](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/[org]/claude-orchestrator/releases)

Based on [Boris Cherny's patterns](https://x.com/bcherny) (creator of Claude Code).

## What is this?

Claude Code Orchestrator enables **parallel AI development** by:

- **Spawning multiple Claude sessions** as independent workers
- **Isolating each worker in git worktrees** (no merge conflicts)
- **Automating the PR pipeline** (review → verify → merge)
- **Built-in quality agents** (QA Guardian, DevOps Engineer, Code Simplifier)

```
┌─────────────────────────────────────────────────────────┐
│   Tab 1: ORCHESTRATOR (You)                             │
│   /spawn auth "implement authentication"                │
│   /spawn api "create REST API"                          │
│   /spawn tests "write test suite"                       │
└─────────────────────────────────────────────────────────┘
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  Tab 2: auth │ │  Tab 3: api  │ │ Tab 4: tests │
│  (working)   │ │  (working)   │ │  (working)   │
│      ↓       │ │      ↓       │ │      ↓       │
│  (PR ready)  │ │  (PR ready)  │ │  (PR ready)  │
└──────────────┘ └──────────────┘ └──────────────┘
```

## Quick Start

```bash
# 1. Install (one command)
curl -fsSL https://raw.githubusercontent.com/[org]/claude-orchestrator/main/install.sh | bash

# 2. Restart your terminal
source ~/.zshrc

# 3. Start Claude in your project
cd your-project && claude

# 4. Spawn parallel workers
/spawn auth "implement user authentication"
/spawn api "create REST API endpoints"
/spawn tests "write comprehensive test suite"

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

## Installation

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/[org]/claude-orchestrator/main/install.sh | bash
```

### Manual install

```bash
git clone https://github.com/[org]/claude-orchestrator ~/.claude-orchestrator
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
| **QA Guardian** | `/review` | Code quality, test coverage, policy compliance |
| **DevOps Engineer** | `/deploy` | CI/CD, infrastructure, deployment verification |
| **Code Simplifier** | Large PRs | Clean up complex code, improve readability |
| **Verify App** | Manual | End-to-end verification and smoke tests |

## Usage Patterns

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
      "Skill(review)",
      "Skill(deploy)",
      "Skill(code-simplifier)",
      "SlashCommand(/spawn:*)",
      "SlashCommand(/workers:*)",
      "SlashCommand(/status:*)",
      "SlashCommand(/merge:*)"
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
├── scripts/
├── commands/
└── agents/

~/.claude/                     # Claude Code directory
├── scripts/                   # Symlinked scripts
│   ├── orchestrator.sh
│   ├── orchestrator-loop.sh
│   ├── start-worker.sh
│   └── wt.sh
├── commands/                  # Slash commands
│   ├── spawn.md
│   ├── status.md
│   └── review.md
└── agents/                    # Built-in agents
    ├── qa-guardian.md
    ├── devops-engineer.md
    └── code-simplifier.md

~/.worktrees/                  # Git worktrees
└── <repo-name>/
    ├── <worker-1>/           # feature/<worker-1> branch
    ├── <worker-2>/           # feature/<worker-2> branch
    └── ...
```

## How It Works

1. **Worktree Isolation**: Each worker operates in its own git worktree with a dedicated feature branch. This prevents merge conflicts between parallel workers.

2. **iTerm Automation**: Uses AppleScript to open new iTerm tabs, run Claude in each, and communicate between sessions.

3. **State Machine**: The orchestrator loop tracks each worker's state (NEEDS_INIT, WORKING, PR_OPEN, MERGED) and takes appropriate actions.

4. **Review Pipeline**: Before merging, PRs pass through quality gates:
   - CI must pass
   - QA Guardian reviews code quality
   - DevOps Engineer reviews infrastructure changes
   - Code Simplifier cleans up large PRs

## Troubleshooting

### Workers not starting

1. Ensure iTerm2 is installed at `/Applications/iTerm.app`
2. Grant Terminal/iTerm accessibility permissions in System Preferences
3. Check that the worktree was created: `wt list <repo>`

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
