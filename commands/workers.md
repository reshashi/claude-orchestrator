---
description: Manage and communicate with worker sessions (list, read, send, status)
allowed-tools: Bash(node:*), Bash(npx:*)
---

# Worker Management

Commands for managing Claude worker sessions running as background processes.

**Platform**: Cross-platform (macOS, Linux, Windows)

## Arguments
- $ARGUMENTS: Command and parameters

## Available Commands

### List all workers
```bash
cd ~/.claude-orchestrator && node dist/index.js list
```

### List all workers (including completed)
```bash
cd ~/.claude-orchestrator && node dist/index.js list --all
```

### Get worker status
```bash
# Summary of all workers
cd ~/.claude-orchestrator && node dist/index.js status

# Detailed status of specific worker
cd ~/.claude-orchestrator && node dist/index.js status worker-name
```

### Read output from a worker
```bash
# Read last 50 lines (default)
cd ~/.claude-orchestrator && node dist/index.js read worker-name

# Read last N lines
cd ~/.claude-orchestrator && node dist/index.js read worker-name --lines 100
```

### Send message to a worker
```bash
cd ~/.claude-orchestrator && node dist/index.js send worker-name "Your message here"
```

### Stop a worker
```bash
cd ~/.claude-orchestrator && node dist/index.js stop worker-name
```

### Trigger merge for a worker
```bash
cd ~/.claude-orchestrator && node dist/index.js merge worker-name
```

### Clean up completed workers
```bash
# Clean up specific worker
cd ~/.claude-orchestrator && node dist/index.js cleanup worker-name

# Clean up all completed workers
cd ~/.claude-orchestrator && node dist/index.js cleanup
```

### Run the monitoring loop
```bash
# Start monitoring loop (Ctrl+C to stop)
cd ~/.claude-orchestrator && node dist/index.js loop

# Custom poll interval (milliseconds)
cd ~/.claude-orchestrator && node dist/index.js loop --poll 10000
```

## Instructions

Parse `$ARGUMENTS` and execute the appropriate command:

1. If "list" or "ls" → run `node dist/index.js list`
2. If "status [name]" → run `node dist/index.js status [name]`
3. If "read <name>" → run `node dist/index.js read <name>`
4. If "send <name> <message>" → run `node dist/index.js send <name> "<message>"`
5. If "stop <name>" → run `node dist/index.js stop <name>`
6. If "merge <name>" → run `node dist/index.js merge <name>`
7. If "cleanup [name]" → run `node dist/index.js cleanup [name]`
8. If "loop" → run `node dist/index.js loop`

Report results back to the user.

## Worker States

Workers progress through these states:

| State | Emoji | Description |
|-------|-------|-------------|
| SPAWNING | 🚀 | Process starting |
| INITIALIZING | ⏳ | Claude loading |
| WORKING | ⚡ | Actively processing |
| PR_OPEN | 📝 | PR created, awaiting review |
| REVIEWING | 🔍 | QA review in progress |
| MERGING | 🔄 | PR being merged |
| MERGED | ✅ | Complete |
| ERROR | ❌ | Needs intervention |
| STOPPED | ⏹️ | Terminated |
