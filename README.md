# Claude Code Orchestrator

> Parallel development superpowers for Claude Code. One orchestrator, many workers.

[![Cross-Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-blue.svg)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-3.0-green.svg)](https://github.com/reshashi/claude-orchestrator/releases/latest)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18.0.0-brightgreen.svg)](https://nodejs.org/)

Based on [Boris Cherny's patterns](https://x.com/bcherny) (creator of Claude Code).

---

## What is This?

Claude Code Orchestrator enables **parallel AI development** by:

- **Taking conceptual project descriptions** and turning them into executed code
- **Generating comprehensive PRDs** with worker task breakdowns
- **Spawning multiple Claude sessions** as independent background processes
- **Isolating each worker in git worktrees** (no merge conflicts)
- **Automating the full pipeline** (PRD → spawn → monitor → review → merge → deliver)
- **Built-in quality agents** (QA Guardian, DevOps Engineer, Code Simplifier)

**v3.0**: Now cross-platform! Works on macOS, Linux, and Windows.

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
│  - Spawns workers as background processes                   │
│  - Monitors via JSONL stream parsing                        │
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
| **Node.js 18+** | Required for orchestrator |
| **Git 2.20+** | Required for worktree support |
| **[Claude Code CLI](https://claude.ai/code)** | Required |
| **[GitHub CLI](https://cli.github.com/)** | Optional (for PR automation) |

### Installation

```bash
# Clone the orchestrator
git clone https://github.com/reshashi/claude-orchestrator.git ~/.claude-orchestrator

# Install dependencies and build
cd ~/.claude-orchestrator
npm install
npm run build

# Add to PATH (add to your shell profile)
export PATH="$HOME/.claude-orchestrator/bin:$PATH"
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
# 7. Notify you when complete
```

**Option 2: Manual Worker Spawning**

```bash
# Spawn workers manually (creates worktree + starts background process)
/spawn auth-db "Create users table migration"
/spawn auth-api "Implement login/logout API routes"
/spawn auth-ui "Build login form component"

# Monitor progress
claude-orchestrator status

# List all workers
claude-orchestrator list

# Read worker output
claude-orchestrator read auth-db

# Merge when ready
/merge auth-db
```

**Option 3: Fully Automated Loop**

```bash
# Start automation loop (monitors all workers)
claude-orchestrator loop

# Check status anytime
claude-orchestrator status

# Stop with Ctrl+C
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

### CLI Commands

```bash
# Spawn a new worker
claude-orchestrator spawn <name> <task> [--repo <name>] [--no-start]

# List workers
claude-orchestrator list [--all]

# Check status
claude-orchestrator status [worker-id]

# Read output
claude-orchestrator read <worker-id> [--lines N]

# Send message to worker
claude-orchestrator send <worker-id> <message>

# Stop worker
claude-orchestrator stop <worker-id>

# Merge PR
claude-orchestrator merge <worker-id>

# Cleanup completed workers
claude-orchestrator cleanup [worker-id]

# Run monitoring loop
claude-orchestrator loop [--poll <ms>]
```

---

## Release Notes

### v3.0 (Latest) — 2026-01-22

**🌍 Cross-Platform Support** — Now works on macOS, Linux, and Windows!

- **Node.js Backend**: Replaced bash/AppleScript with TypeScript
- **Background Processes**: Workers run as child processes, not iTerm tabs
- **JSONL Streaming**: Parse Claude's `--print` output in real-time
- **State Persistence**: Worker state survives orchestrator restarts
- **Cleaner CLI**: `claude-orchestrator` command with subcommands

**Breaking Changes:**
- No longer requires iTerm2 (or any specific terminal)
- Workers run in background, not visible tabs
- New CLI interface (see Commands Reference)

---

### v2.3 — 2026-01-13

**🧠 Memory System** — Persistent memory across Claude sessions!

- **Memory System**: Store facts, tools, and context that persist across sessions
- **`/assistant` Command**: New command for memory management
- **Session Summaries**: Generate handoff notes for next session

---

### v2.0 — 2026-01-13

**Autonomous Planner Layer** — Give Claude a concept. Walk away. Come back to working code.

- **`/project` command**: Full autonomous project execution
- **PRD Generation**: Automatically generates Product Requirements Documents
- **Iterative Review**: Reviews completed work against PRD

---

### v1.0 — 2026-01-11

**Initial Release**

- Git worktree isolation for parallel workers
- iTerm tab automation via AppleScript
- Orchestrator loop for automated monitoring

---

## Troubleshooting

### Workers not starting

1. Ensure Claude CLI is installed and in PATH
2. Check worktree was created: `ls ~/.worktrees/<repo>/`
3. Check Node.js version: `node --version` (needs 18+)

### Cannot connect to worker

Workers run in background. Use `claude-orchestrator read <name>` to see output.

### Git worktree conflicts

```bash
git worktree list
git worktree remove <path> --force
```

### Build errors

```bash
cd ~/.claude-orchestrator
npm run clean
npm install
npm run build
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
4. Run `npm run build` and `npm run test`
5. Submit a pull request

---

## License

MIT - see [LICENSE](LICENSE)

---

## Acknowledgments

- [Boris Cherny](https://x.com/bcherny) - Creator of Claude Code and the parallel development patterns
- [Anthropic](https://anthropic.com) - Claude AI
