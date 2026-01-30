---
name: claude-orchestrator
description: Spawn and manage parallel Claude workers for software development. Use for parallel feature development, multi-agent coordination, or autonomous project execution.
metadata: {"moltbot":{"requires":{"bins":["node","git","gh"],"env":[]}}}
---

# Claude Orchestrator

Manage parallel Claude Code workers from any messaging platform. Spawn isolated workers, monitor their progress, and merge their PRs—all through natural conversation.

## Quick Reference

| Command | What it Does |
|---------|--------------|
| `orchestrator spawn <name> <task>` | Create a new worker |
| `orchestrator list` | Show all active workers |
| `orchestrator status [id]` | Get detailed worker status |
| `orchestrator send <id> <message>` | Send message to worker |
| `orchestrator stop <id>` | Stop a worker |
| `orchestrator merge <id>` | Merge worker's PR |
| `orchestrator project <description>` | Full autonomous project |

## Natural Language Examples

Users can speak naturally. Recognize these patterns:

### Spawning Workers

- "spawn a worker called auth-api to implement user authentication"
- "create 3 workers to build the payment system"
- "start a worker named dark-mode to add theme switching"
- "I need workers for config, API routes, and UI for OAuth"

**Action**: Parse worker names and tasks, then call:
```bash
orchestrator-bridge spawn <name> "<task>"
```

For multiple workers, spawn each one:
```bash
orchestrator-bridge spawn oauth-config "Set up OAuth provider configuration"
orchestrator-bridge spawn oauth-api "Implement OAuth callback routes"
orchestrator-bridge spawn oauth-ui "Build login/logout UI components"
```

### Checking Status

- "what's the status of my workers?"
- "show orchestrator status"
- "list workers"
- "how is the auth worker doing?"

**Action**: Call `orchestrator-bridge list` or `orchestrator-bridge status <id>`

### Sending Messages

- "tell the auth worker to also add password reset"
- "send 'fix the tests' to my-feature"
- "update the api worker about the new requirements"

**Action**: `orchestrator-bridge send <worker-id> "<message>"`

### Merging and Stopping

- "merge the auth-db worker"
- "stop all workers"
- "merge my-feature"
- "cleanup completed workers"

**Action**: `orchestrator-bridge merge <id>` or `orchestrator-bridge stop <id>`

### Full Project Mode

- "orchestrator project: build a dark mode toggle with tests"
- "create a project to add user notifications"
- "I need a complete feature for Stripe payments"

**Action**: `orchestrator-bridge project "<description>"`

This triggers the full autonomous workflow:
1. Generate PRD and break into tasks
2. Spawn workers for each task
3. Monitor progress and run reviews
4. Merge PRs when ready
5. Report completion

## Worker States

Workers progress through these states:

| State | Emoji | Description |
|-------|-------|-------------|
| SPAWNING | ⏳ | Process starting |
| INITIALIZING | 🔄 | Claude loading |
| WORKING | 💻 | Actively coding |
| PR_OPEN | 📬 | PR created, awaiting CI |
| REVIEWING | 🔍 | QA review in progress |
| MERGING | 🔀 | PR being merged |
| MERGED | ✅ | Complete |
| ERROR | ❌ | Needs intervention |
| STOPPED | 🛑 | Terminated |

## Response Formatting

When listing workers, format like:
```
Workers:
────────────────────────────────────────
💻 auth-api            WORKING
   Path: ~/.worktrees/myapp/auth-api
   Task: Implement user authentication...

📬 dark-mode           PR_OPEN       PR #42
   Path: ~/.worktrees/myapp/dark-mode
   Task: Add theme switching...

✅ db-migration        MERGED        PR #38
   Path: ~/.worktrees/myapp/db-migration
   Task: Add user profile fields...
```

When spawning, confirm:
```
Worker 'auth-api' spawned!
  Path: ~/.worktrees/myapp/auth-api
  Branch: feature/auth-api
  PID: 12345

The worker is running in the background.
Use 'orchestrator status auth-api' to check progress.
```

## API Mode

If the orchestrator HTTP server is running (port 3001 by default), use the REST API:

```bash
# Spawn worker
curl -X POST http://localhost:3001/api/workers \
  -H "Content-Type: application/json" \
  -d '{"name":"auth-api","task":"Implement authentication"}'

# List workers
curl http://localhost:3001/api/workers

# Get status
curl http://localhost:3001/api/workers/auth-api

# Send message
curl -X POST http://localhost:3001/api/workers/auth-api/send \
  -H "Content-Type: application/json" \
  -d '{"message":"Also add password reset"}'

# Stop worker
curl -X POST http://localhost:3001/api/workers/auth-api/stop

# Merge PR
curl -X POST http://localhost:3001/api/workers/auth-api/merge
```

## WebSocket Updates

Connect to `ws://localhost:3001/ws/status` for real-time updates:

```json
{"type":"state_change","workerId":"auth-api","from":"WORKING","to":"PR_OPEN"}
{"type":"pr_detected","workerId":"auth-api","prNumber":42,"prUrl":"..."}
{"type":"pr_merged","workerId":"auth-api","prNumber":42}
```

## Prerequisites

- Node.js 18+
- Git with worktree support
- GitHub CLI (`gh`) authenticated
- Claude Code CLI installed

## Installation

```bash
# Install orchestrator globally
cd ~/.claude-orchestrator
npm install
npm run build
npm link

# Or install skill via ClawdHub
clawdhub install claude-orchestrator
```

## Tips

1. **Worker names should be descriptive** - Use kebab-case like `auth-flow`, `dark-mode`, `db-migration`
2. **Tasks should be clear** - Give workers specific, actionable tasks
3. **Monitor with status** - Check progress before asking for updates
4. **Let workers finish** - Workers will create PRs when ready
5. **Trust the process** - The orchestrator handles CI, reviews, and merging

## Troubleshooting

**Worker stuck in WORKING?**
- Check status: `orchestrator status <id>`
- Read output: `orchestrator-bridge read <id>`
- Nudge if needed: `orchestrator send <id> "continue"`

**PR not merging?**
- Check CI status: `gh pr checks <pr-number>`
- Verify review passed
- Manual merge: `orchestrator merge <id>`

**Worker in ERROR state?**
- Read the error: `orchestrator status <id>`
- Fix and restart or cleanup

## Integration Notes

This skill works through:
1. **CLI wrapper** (`orchestrator-bridge.sh`) - Translates commands
2. **HTTP API** (port 3001) - REST endpoints for all operations
3. **WebSocket** - Real-time status updates

The orchestrator manages:
- Git worktrees for isolation
- Claude Code background processes
- State persistence across restarts
- GitHub PR lifecycle
- QA reviews and security scans
