# Claude Code Orchestrator

> Parallel development superpowers for Claude Code. One orchestrator, many workers.

[![macOS](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.3-green.svg)](https://github.com/reshashi/claude-orchestrator/releases/latest)
[![Latest Release](https://img.shields.io/github/v/release/reshashi/claude-orchestrator?label=latest)](https://github.com/reshashi/claude-orchestrator/releases/latest)

Based on [Boris Cherny's patterns](https://x.com/bcherny) (creator of Claude Code).

---

## What is This?

Claude Code Orchestrator enables **parallel AI development** by:

- **Taking conceptual project descriptions** and turning them into executed code
- **Generating comprehensive PRDs** with worker task breakdowns
- **Spawning multiple Claude sessions** as independent workers
- **Isolating each worker in git worktrees** (no merge conflicts)
- **Automating the full pipeline** (PRD → spawn → monitor → review → merge → deliver)
- **Built-in quality agents** (QA Guardian, DevOps Engineer, Code Simplifier)

```
┌─────────────────────────────────────────────────────────────┐
│   HUMAN: "/project Add user authentication with OAuth"      │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                       PLANNER                               │
│  - Generates comprehensive PRD                              │
│  - Creates worker task breakdown                            │
│  - Reviews completed work                                   │
│  - Iterates with feedback (up to 3x)                        │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR                             │
│  - Creates worktrees for each task                          │
│  - Spawns workers in iTerm tabs                             │
│  - Monitors every 5 seconds (silently in background)        │
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

---

## How To Guide

### Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | Required (uses iTerm2 + AppleScript) |
| **[iTerm2](https://iterm2.com/)** | Required for multi-tab automation |
| **Git 2.20+** | Required for worktree support |
| **[Claude Code CLI](https://claude.ai/code)** | Required |
| **[GitHub CLI](https://cli.github.com/)** | Optional (for PR automation) |
| **jq** | Required (`brew install jq`) |

### Installation

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/reshashi/claude-orchestrator/main/install.sh | bash

# Restart your terminal
source ~/.zshrc
```

### Basic Usage

**Option 1: Full Autonomous Project** (recommended)

```bash
# Start Claude in your project
cd your-project && claude

# Give Claude a project description - it handles everything
/project "Add user authentication with magic links"

# Claude will:
# 1. Generate a PRD with success criteria
# 2. Break it into worker tasks
# 3. Spawn workers in parallel
# 4. Monitor progress (silently in background)
# 5. Review against requirements
# 6. Iterate if needed (up to 3x)
# 7. Notify you when complete (macOS notification)

# You can work in other apps while it runs!
```

**Option 2: Manual Worker Spawning**

```bash
# Spawn workers manually
/spawn auth-db "Create users table migration"
/spawn auth-api "Implement login/logout API routes"
/spawn auth-ui "Build login form component"

# Monitor progress
/status

# Merge when ready
/merge auth-db
```

**Option 3: Fully Automated Loop**

```bash
# Start automation loop (runs in background)
orchestrator-start

# Check status anytime
orchestrator-status

# Stop when done
orchestrator-stop
```

### Commands Reference

| Command | Description |
|---------|-------------|
| `/project "description"` | Full autonomous project execution |
| `/spawn <name> "task"` | Create worktree + start worker |
| `/status` | Check all worktrees, workers, PRs |
| `/merge <name>` | Merge worker branch + cleanup |
| `/review` | Run QA Guardian on PRs |
| `/deploy` | Run DevOps deployment checks |
| `/assistant remember "fact"` | Store facts to persistent memory |
| `/assistant recall "topic"` | Search memory for relevant facts |
| `/assistant session-end` | Generate session handoff summary |

See [docs/MEMORY.md](docs/MEMORY.md) for full memory system documentation.

### Update / Uninstall

```bash
# Update to latest version
~/.claude-orchestrator/install.sh --update

# Uninstall
~/.claude-orchestrator/uninstall.sh
```

---

## Release Notes

### v2.3 (Latest) — 2026-01-13

**🧠 Memory System** — Persistent memory across Claude sessions!

- **Memory System**: Store facts, tools, and context that persist across sessions
- **`/assistant` Command**: New command for memory management and meta-tasks
- **Session Summaries**: Generate handoff notes for next session
- **Toolchain Registry**: Track tools and CLIs you use regularly

---

### v2.2 — 2026-01-13

**🎯 Focus-Stealing Fix** — Work in other apps while orchestrator runs!

The orchestrator no longer steals window focus when sending input to workers.

**What was fixed:**
- ❌ **Before**: Every 5 seconds, iTerm would steal focus and interrupt your work
- ✅ **After**: Orchestrator sends commands silently without activating iTerm window

**Technical details:**
```applescript
# Before (v2.1 and earlier) - STEALS FOCUS
tell application "iTerm"
    activate  # <-- This brings iTerm to front
    ...
end tell

# After (v2.2) - SILENT BACKGROUND OPERATION
tell application "iTerm"
    -- No activate command
    tell current window
        tell tab N
            tell current session
                write text "..."  # Works without focus!
            end tell
        end tell
    end tell
end tell
```

**Also fixed:**
- `WORKER.md` → `WORKER_CLAUDE.md` filename reference

---

### v2.1 — 2026-01-13

**Enhanced Agent Usage**

- **Security Scanning on All PRs**: Every PR gets `npm audit` scan
- **Quality Agents in Planner Review Phase**: After all workers merge, runs `/review`, `/qcode`, `npm audit`, `/deploy`
- **Lowered Code Simplifier Threshold**: Triggers on 50+ lines (was 100+)
- **Pre-PR Quality Gates**: Workers run `type-check`, `lint`, `test` before creating PR
- **Enhanced Agent Completion Detection**: More robust pattern matching

---

### v2.0 — 2026-01-13

**Autonomous Planner Layer** — Give Claude a concept. Walk away. Come back to working code.

- **`/project` command**: Full autonomous project execution from concept to completion
- **PRD Generation**: Automatically generates Product Requirements Documents
- **Worker Task Breakdown**: Breaks projects into parallel worker tasks
- **Iterative Review**: Reviews completed work against PRD, iterates up to 3x if needed
- **Completion Notification**: macOS notification + terminal bell when done
- **Built-in Quality Agents**: QA Guardian, DevOps Engineer, Code Simplifier, Planner

---

### v1.0 — 2026-01-11

**Initial Release**

- Git worktree isolation for parallel workers
- iTerm tab automation via AppleScript
- `/spawn`, `/status`, `/merge` commands
- Orchestrator loop for automated monitoring
- Worker state machine (NEEDS_INIT → WORKING → PR_OPEN → MERGED)

---

## Troubleshooting

### iTerm stealing focus / interrupting work

**Fixed in v2.2!** Update to latest:
```bash
~/.claude-orchestrator/install.sh --update
```

### Workers not starting

1. Ensure iTerm2 is installed at `/Applications/iTerm.app`
2. Grant accessibility permissions: System Preferences → Security & Privacy → Privacy → Accessibility
3. Check worktree was created: `wt list <repo>`

### Workers stuck waiting for input

Fixed in v2.0. The orchestrator properly submits messages with Return keystroke.

### AppleScript errors

Grant accessibility permissions to iTerm2 and Terminal in System Preferences.

### Commands not found

Restart terminal or run: `source ~/.zshrc`

### Git worktree conflicts

```bash
git worktree list
git worktree remove <path> --force
```

---

## Documentation

For detailed documentation, see:

- [Architecture Overview](docs/ARCHITECTURE.md)
- [Quick Start Guide](docs/QUICK_START.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- [Changelog](CHANGELOG.md)

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

MIT - see [LICENSE](LICENSE)

---

## Acknowledgments

- [Boris Cherny](https://x.com/bcherny) - Creator of Claude Code and the parallel development patterns
- [Anthropic](https://anthropic.com) - Claude AI
