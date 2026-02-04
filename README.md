# Claude Code Orchestrator

> Parallel development superpowers for Claude Code. One orchestrator, many workers.

[![Cross-Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-blue.svg)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-3.1-green.svg)](https://github.com/reshashi/claude-orchestrator/releases/latest)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18.0.0-brightgreen.svg)](https://nodejs.org/)

---

## TL;DR

**What it does:** Runs multiple Claude Code sessions in parallel, each working on a different part of your project simultaneously.

**How it works:** Each worker gets its own isolated git worktree (separate directory, separate branch). Workers run as background processes. An orchestrator monitors them, runs QA reviews, and merges their PRs automatically.

**How to use it:**

```bash
# Install
git clone https://github.com/reshashi/claude-orchestrator.git ~/.claude-orchestrator
cd ~/.claude-orchestrator && npm install && npm run build
export PATH="$HOME/.claude-orchestrator/bin:$PATH"

# Use (from inside Claude Code)
/project "Add user authentication with OAuth"   # Full autonomous mode
# OR
/spawn auth-db "Create users table"             # Manual worker spawning
/spawn auth-api "Build login API"
/spawn auth-ui "Create login form"
```

That's it. Claude handles the rest.

---

## What Problem Does This Solve?

When building features, you often need to work on multiple parts simultaneously:
- Database migrations
- Backend API routes
- Frontend components
- Tests

Normally, you'd do these sequentially. With the orchestrator, Claude works on all of them **at the same time** in separate git branches, then merges them together.

**Before:** 4 tasks × 30 min each = 2 hours
**After:** 4 tasks in parallel = 30-40 minutes

---

## How It Actually Works

### The Architecture

```
┌─────────────────────────────────────────────────────────────┐
│   YOU: "Add user authentication"                            │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR                              │
│                                                              │
│  1. Creates a PRD (what to build, success criteria)         │
│  2. Breaks it into parallel tasks                           │
│  3. Creates git worktrees (isolated directories)            │
│  4. Spawns Claude workers (background processes)            │
│  5. Monitors progress via JSONL streaming                   │
│  6. Runs QA reviews on each PR                              │
│  7. Merges PRs when they pass                               │
│  8. Notifies you when done                                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │ Worker 1 │     │ Worker 2 │     │ Worker 3 │
    │ auth-db  │     │ auth-api │     │ auth-ui  │
    │          │     │          │     │          │
    │ Branch:  │     │ Branch:  │     │ Branch:  │
    │ feature/ │     │ feature/ │     │ feature/ │
    │ auth-db  │     │ auth-api │     │ auth-ui  │
    └──────────┘     └──────────┘     └──────────┘
         │                │                │
         ▼                ▼                ▼
       PR #1            PR #2            PR #3
         │                │                │
         └────────────────┼────────────────┘
                          ▼
                    All merged to main
```

### Git Worktrees: The Secret Sauce

Each worker operates in a **git worktree** — a separate working directory with its own branch, but sharing the same git history. This means:

- **No merge conflicts** between workers (they're on different branches)
- **Full isolation** (each worker has its own `node_modules`, etc.)
- **Easy cleanup** (just delete the worktree directory)

Worktrees live in `~/.worktrees/<repo-name>/<worker-name>/`.

### Worker Lifecycle

Workers progress through these states:

| State | Emoji | What's Happening |
|-------|-------|------------------|
| `SPAWNING` | ⏳ | Process starting up |
| `INITIALIZING` | 🔄 | Claude loading context |
| `WORKING` | 💻 | Actively writing code |
| `PR_OPEN` | 📬 | PR created, CI running |
| `REVIEWING` | 🔍 | QA Guardian checking code |
| `MERGING` | 🔀 | PR being merged |
| `MERGED` | ✅ | Done! |
| `ERROR` | ❌ | Something went wrong |
| `STOPPED` | 🛑 | Manually stopped |

### Automated Quality Gates

Before any PR gets merged, it goes through:

1. **CI checks** (your existing GitHub Actions)
2. **QA Guardian** (code review agent)
3. **Security scan** (`npm audit`)
4. **DevOps review** (if infrastructure files changed)
5. **Code simplifier** (if PR is large)

All automatic. All in the background.

---

## Installation

### Prerequisites

| Requirement | Why |
|-------------|-----|
| **Node.js 18+** | Orchestrator runtime |
| **Bash 4.0+** | Required for associative arrays in scripts |
| **Git 2.20+** | Worktree support |
| **[Claude Code CLI](https://claude.ai/code)** | The AI that does the work |
| **[GitHub CLI](https://cli.github.com/)** | PR automation (optional but recommended) |

> **macOS users:** macOS ships with Bash 3.2 (from 2007) due to GPL licensing. Install modern Bash via Homebrew:
> ```bash
> brew install bash
> # Bash 5.x will be installed to /opt/homebrew/bin/bash (Apple Silicon) or /usr/local/bin/bash (Intel)
> # The installer will detect it automatically via PATH
> ```

### Install the Orchestrator

```bash
# Clone it
git clone https://github.com/reshashi/claude-orchestrator.git ~/.claude-orchestrator

# Build it
cd ~/.claude-orchestrator
npm install
npm run build

# Add to your PATH (add this line to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.claude-orchestrator/bin:$PATH"

# Verify it works
claude-orchestrator --version
```

---

## Usage Guide

### Option 1: Full Autonomous Mode (Recommended)

Let Claude handle everything from concept to completion.

```bash
# Start Claude in your project
cd your-project
claude

# Give it a high-level description
/project "Add user authentication with email magic links"
```

What happens next:

1. **PRD Generation**: Claude creates a Product Requirements Document with:
   - Feature description
   - Technical approach
   - Success criteria
   - Worker task breakdown

2. **Worker Spawning**: Creates worktrees and starts workers:
   ```
   Spawning workers:
     ⏳ auth-db    → Create users and sessions tables
     ⏳ auth-api   → Implement magic link endpoints
     ⏳ auth-ui    → Build login/signup components
   ```

3. **Monitoring**: Orchestrator watches progress silently

4. **Review & Merge**: When workers create PRs:
   - Runs CI
   - Runs QA Guardian
   - Merges when ready

5. **Completion**: Notifies you when everything is merged

### Option 2: Manual Worker Spawning

More control over individual tasks.

```bash
# Inside Claude Code, spawn workers one by one
/spawn auth-db "Create users table with email, created_at, updated_at columns"
/spawn auth-api "Implement POST /auth/magic-link and GET /auth/verify endpoints"
/spawn auth-ui "Build LoginForm component with email input and loading state"

# Check on them
claude-orchestrator status

# Output:
# 💻 auth-db     WORKING
# 💻 auth-api    WORKING
# 📬 auth-ui     PR_OPEN   PR #42

# Read a worker's output
claude-orchestrator read auth-db

# Send additional instructions
claude-orchestrator send auth-api "Also add rate limiting to the endpoints"

# Merge when ready
/merge auth-ui
```

### Option 3: CLI-Only (No Claude Code)

Use the orchestrator directly from your terminal.

```bash
# Spawn a worker
claude-orchestrator spawn auth-db "Create users table migration"

# Monitor all workers
claude-orchestrator loop

# In another terminal, check status
claude-orchestrator status
claude-orchestrator list --all
```

---

## CLI Reference

### Core Commands

| Command | Description |
|---------|-------------|
| `spawn <name> <task>` | Create worktree + start worker |
| `list [--all]` | List workers (add `--all` for completed) |
| `status [worker-id]` | Detailed status of one or all workers |
| `read <worker-id>` | Read worker's output log |
| `send <worker-id> <msg>` | Send message to worker |
| `stop <worker-id>` | Stop a worker |
| `merge <worker-id>` | Trigger PR merge |
| `cleanup [worker-id]` | Remove completed worker state |
| `loop` | Run monitoring loop |
| `serve` | Start HTTP/WebSocket API server |

### Claude Code Slash Commands

| Command | Description |
|---------|-------------|
| `/project "description"` | Full autonomous project |
| `/spawn <name> "task"` | Spawn a worker |
| `/status` | Check all workers |
| `/merge <name>` | Merge a worker's PR |
| `/review` | Run QA Guardian |
| `/deploy` | Run deployment checks |

### Examples

```bash
# Spawn with specific repo
claude-orchestrator spawn dark-mode "Add theme toggle" --repo my-app

# Create worktree without starting worker
claude-orchestrator spawn refactor "Optimize queries" --no-start

# Read last 100 lines of output
claude-orchestrator read auth-api --lines 100

# Run loop with faster polling
claude-orchestrator loop --poll 2000

# Start API server on custom port
claude-orchestrator serve --port 8080 --host 0.0.0.0
```

---

## HTTP API & Moltbot Integration

The orchestrator includes a full HTTP API, enabling control from:
- **Moltbot** (Discord, Slack, Telegram, WhatsApp, etc.)
- **Custom scripts**
- **CI/CD pipelines**
- **Mobile apps**

### Starting the API Server

```bash
claude-orchestrator serve --port 3001
```

Output:
```
Claude Orchestrator API Server
══════════════════════════════════════════════
HTTP API:    http://localhost:3001/api
WebSocket:   ws://localhost:3001/ws/status
Health:      http://localhost:3001/api/health

Endpoints:
  GET    /api/workers          - List all workers
  GET    /api/workers/:id      - Get worker status
  POST   /api/workers          - Spawn new worker
  POST   /api/workers/:id/send - Send message
  POST   /api/workers/:id/stop - Stop worker
  POST   /api/workers/:id/merge - Merge PR
  DELETE /api/workers/:id      - Cleanup worker
  WS     /ws/status            - Real-time updates
```

### API Examples

```bash
# Health check
curl http://localhost:3001/api/health
# {"status":"healthy","version":"3.1.0","activeWorkers":2,"totalWorkers":5}

# List workers
curl http://localhost:3001/api/workers
# [{"id":"auth-api","state":"WORKING",...}, ...]

# Spawn a worker
curl -X POST http://localhost:3001/api/workers \
  -H "Content-Type: application/json" \
  -d '{"name":"dark-mode","task":"Add theme toggle to settings page"}'

# Send message to worker
curl -X POST http://localhost:3001/api/workers/auth-api/send \
  -H "Content-Type: application/json" \
  -d '{"message":"Also add password reset functionality"}'

# Stop a worker
curl -X POST http://localhost:3001/api/workers/auth-api/stop

# Merge PR
curl -X POST http://localhost:3001/api/workers/auth-api/merge
```

### WebSocket Real-Time Updates

Connect to `ws://localhost:3001/ws/status` for live events:

```javascript
const ws = new WebSocket('ws://localhost:3001/ws/status');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log(data);
};

// Events you'll receive:
// {"type":"initial_state","workers":[...]}
// {"type":"state_change","workerId":"auth-api","from":"WORKING","to":"PR_OPEN"}
// {"type":"pr_detected","workerId":"auth-api","prNumber":42,"prUrl":"..."}
// {"type":"pr_merged","workerId":"auth-api","prNumber":42}
```

### Moltbot Skill

Control from Discord, Slack, or any Moltbot-supported platform:

```bash
# Install the skill
cp -r ~/.claude-orchestrator/moltbot-skill ~/.clawdbot/skills/claude-orchestrator
```

Then in Discord/Slack:
```
You:  spawn a worker called auth-api to implement JWT authentication
Bot:  Worker 'auth-api' spawned! Starting authentication implementation...

You:  what's the status?
Bot:  Workers:
      💻 auth-api        WORKING
      📬 dark-mode       PR_OPEN   PR #42

You:  merge dark-mode
Bot:  PR #42 merged successfully!
```

---

## File Structure

```
~/.claude-orchestrator/
├── bin/
│   └── claude-orchestrator      # CLI entry point
├── src/
│   ├── cli.ts                   # Command definitions
│   ├── orchestrator.ts          # Main orchestration loop
│   ├── worker-manager.ts        # Worker process management
│   ├── state-manager.ts         # State persistence
│   ├── state-machine.ts         # Worker state transitions
│   ├── server.ts                # HTTP/WebSocket API
│   ├── github.ts                # GitHub CLI integration
│   ├── jsonl-parser.ts          # Claude output parsing
│   └── types.ts                 # TypeScript types
├── commands/                    # Slash command definitions
├── agents/                      # QA Guardian, DevOps, etc.
├── moltbot-skill/              # Moltbot integration
│   ├── SKILL.md                # Skill definition
│   ├── scripts/
│   │   └── orchestrator-bridge.sh
│   └── references/
│       ├── COMMANDS.md
│       └── EXAMPLES.md
└── scripts/                     # Legacy bash scripts

~/.claude/workers/               # Worker state storage
├── registry.json               # All workers registry
└── <worker-id>/
    ├── state.json              # Worker state
    └── output.jsonl            # Worker output log

~/.worktrees/<repo>/<worker>/   # Git worktrees
└── WORKER_CLAUDE.md            # Worker instructions
```

---

## Troubleshooting

### Workers not starting

```bash
# Check Claude CLI is installed
which claude

# Check Node.js version (needs 18+)
node --version

# Check worktree was created
ls ~/.worktrees/<repo-name>/

# Check orchestrator logs
cat ~/.claude/orchestrator.log
```

### Worker stuck in WORKING state

```bash
# Read its output
claude-orchestrator read <worker-id>

# Nudge it
claude-orchestrator send <worker-id> "Please continue with the task"

# Or stop and restart
claude-orchestrator stop <worker-id>
claude-orchestrator spawn <worker-id> "<original-task>"
```

### PR not merging

```bash
# Check CI status
gh pr checks <pr-number>

# Check review status
claude-orchestrator status <worker-id>

# Force merge (bypasses auto-review)
claude-orchestrator merge <worker-id>
```

### Git worktree conflicts

```bash
# List all worktrees
git worktree list

# Remove a stuck worktree
git worktree remove ~/.worktrees/<repo>/<worker> --force

# Prune orphaned worktrees
git worktree prune
```

### API server won't start

```bash
# Check if port is in use
lsof -i :3001

# Kill existing process
kill $(lsof -ti :3001)

# Try a different port
claude-orchestrator serve --port 3002
```

### Build errors

```bash
cd ~/.claude-orchestrator
npm run clean
rm -rf node_modules
npm install
npm run build
```

---

## Release Notes

### v3.1 (Latest) — 2026-01-28

**Moltbot Integration** — Control from any messaging platform!

- HTTP API server (Fastify)
- WebSocket real-time updates
- Moltbot skill package
- Bridge script for CLI-to-API

New command: `claude-orchestrator serve`

### v3.0 — 2026-01-22

**Cross-Platform Support** — macOS, Linux, Windows!

- Node.js backend (replaced bash/AppleScript)
- Background processes (no iTerm required)
- JSONL streaming for real-time monitoring
- State persistence across restarts

### v2.3 — 2026-01-13

**Memory System** — Persistent context across sessions

### v2.0 — 2026-01-13

**Autonomous Planner** — `/project` command for full automation

### v1.0 — 2026-01-11

**Initial Release** — Git worktrees + iTerm automation

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-thing`
3. Make your changes
4. Run checks: `npm run build && npm run test`
5. Submit a pull request

---

## License

MIT — see [LICENSE](LICENSE)

---

## Acknowledgments

- [Boris Cherny](https://x.com/bcherny) — Creator of Claude Code and the parallel development patterns that inspired this project
- [Anthropic](https://anthropic.com) — Claude AI

---

## Questions?

- **Issues**: [GitHub Issues](https://github.com/reshashi/claude-orchestrator/issues)
- **Discussions**: [GitHub Discussions](https://github.com/reshashi/claude-orchestrator/discussions)
