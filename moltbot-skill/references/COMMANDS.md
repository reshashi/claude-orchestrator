# Claude Orchestrator Command Reference

Complete documentation for all orchestrator commands.

## spawn

Create a worktree and spawn a Claude worker.

**Syntax:**
```bash
orchestrator spawn <name> <task> [options]
```

**Arguments:**
- `name` - Unique worker identifier (kebab-case recommended)
- `task` - Description of what the worker should accomplish

**Options:**
- `-r, --repo <name>` - Repository name (defaults to current directory)
- `--no-start` - Create worktree only, don't start Claude process

**Examples:**
```bash
# Basic spawn
orchestrator spawn auth-flow "Implement user authentication with JWT"

# Specify repository
orchestrator spawn dark-mode "Add theme switching" --repo my-app

# Create worktree without starting
orchestrator spawn refactor-db "Optimize database queries" --no-start
```

**What it does:**
1. Creates git worktree at `~/.worktrees/<repo>/<name>`
2. Creates branch `feature/<name>`
3. Writes `WORKER_CLAUDE.md` with task instructions
4. Starts Claude Code in background with task prompt
5. Registers worker in state manager

---

## list (ls)

List all workers.

**Syntax:**
```bash
orchestrator list [options]
orchestrator ls [options]
```

**Options:**
- `-a, --all` - Include completed/stopped workers

**Examples:**
```bash
# Active workers only
orchestrator list

# All workers including completed
orchestrator list --all
```

**Output format:**
```
Workers:
────────────────────────────────────────────────
💻 auth-api            WORKING
   Path: ~/.worktrees/myapp/auth-api
   Task: Implement user authentication...

📬 dark-mode           PR_OPEN       PR #42
   Path: ~/.worktrees/myapp/dark-mode
   Task: Add theme switching...
```

---

## status

Get detailed status of a worker or overall summary.

**Syntax:**
```bash
orchestrator status [worker-id]
```

**Arguments:**
- `worker-id` - Optional. Specific worker to check.

**Examples:**
```bash
# Overall summary
orchestrator status

# Specific worker
orchestrator status auth-api
```

**Summary output:**
```
Orchestrator Status
────────────────────────────────────
Total Workers: 5
Working:       2
PR Open:       1
Reviewing:     1
Merged:        1
Errors:        0
```

**Worker detail output:**
```
💻 Worker: auth-api
──────────────────────────────────────────────────
State:       WORKING
Description: Worker is actively processing the task
Branch:      feature/auth-api
Path:        ~/.worktrees/myapp/auth-api
Task:        Implement user authentication with JWT
Last Active: 2026-01-28T10:30:45Z
```

---

## read

Read output from a worker.

**Syntax:**
```bash
orchestrator read <worker-id> [options]
```

**Arguments:**
- `worker-id` - Worker to read output from

**Options:**
- `-n, --lines <number>` - Number of lines to show (default: 50)

**Examples:**
```bash
# Last 50 lines
orchestrator read auth-api

# Last 100 lines
orchestrator read auth-api --lines 100
```

---

## send

Send a message to a worker.

**Syntax:**
```bash
orchestrator send <worker-id> <message>
```

**Arguments:**
- `worker-id` - Target worker
- `message` - Message to send (quote if contains spaces)

**Examples:**
```bash
# Simple message
orchestrator send auth-api "Also add password reset functionality"

# Send command
orchestrator send auth-api "/review"

# Nudge stuck worker
orchestrator send auth-api "Please continue with the task"
```

---

## stop

Stop a worker.

**Syntax:**
```bash
orchestrator stop <worker-id>
```

**Arguments:**
- `worker-id` - Worker to stop

**Examples:**
```bash
orchestrator stop auth-api
```

**Notes:**
- Sends SIGTERM to Claude process
- Transitions worker to STOPPED state
- Does not delete worktree or state

---

## merge

Manually trigger merge for a worker's PR.

**Syntax:**
```bash
orchestrator merge <worker-id>
```

**Arguments:**
- `worker-id` - Worker whose PR to merge

**Examples:**
```bash
orchestrator merge auth-api
```

**Prerequisites:**
- Worker must have created a PR (`prNumber` set)
- CI should have passed (recommended)

**Behavior:**
- Uses squash merge by default
- Deletes branch after merge
- Transitions worker to MERGED state

---

## cleanup

Clean up completed workers.

**Syntax:**
```bash
orchestrator cleanup [worker-id] [options]
```

**Arguments:**
- `worker-id` - Optional. Specific worker to clean up.

**Options:**
- `--force` - Remove all non-running workers

**Examples:**
```bash
# Clean up specific worker
orchestrator cleanup auth-api

# Clean up all completed
orchestrator cleanup

# Force cleanup all stopped
orchestrator cleanup --force
```

**What it cleans:**
- Worker state from `~/.claude/workers/<id>/`
- Registry entry
- Note: Does NOT remove git worktree (use `git worktree remove`)

---

## loop

Run the orchestrator monitoring loop.

**Syntax:**
```bash
orchestrator loop [options]
```

**Options:**
- `--poll <ms>` - Poll interval in milliseconds (default: 5000)

**Examples:**
```bash
# Default polling
orchestrator loop

# Faster polling (1 second)
orchestrator loop --poll 1000
```

**What it monitors:**
- Worker state changes
- PR CI status
- Review completion
- Merge opportunities

**Actions it takes:**
- Initiates QA review when CI passes
- Runs security scans
- Auto-merges approved PRs (if enabled)
- Nudges stuck workers

---

## serve (API Server)

Start the HTTP/WebSocket API server.

**Syntax:**
```bash
orchestrator serve [options]
```

**Options:**
- `-p, --port <number>` - Port number (default: 3001)
- `-h, --host <string>` - Host to bind (default: localhost)

**Examples:**
```bash
# Default settings
orchestrator serve

# Custom port
orchestrator serve --port 8080

# Bind to all interfaces
orchestrator serve --host 0.0.0.0
```

**Endpoints:**
- `GET /api/workers` - List all workers
- `GET /api/workers/:id` - Get worker status
- `POST /api/workers` - Spawn new worker
- `POST /api/workers/:id/send` - Send message
- `POST /api/workers/:id/stop` - Stop worker
- `POST /api/workers/:id/merge` - Merge PR
- `DELETE /api/workers/:id` - Cleanup worker
- `WS /ws/status` - Real-time updates
