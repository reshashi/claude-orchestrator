---
description: Manage and communicate with worker sessions (list, read, send, init)
allowed-tools: Bash(~/.claude/scripts/orchestrator.sh:*), Bash(osascript:*)
---

# Worker Management

Orchestrator commands for managing Claude worker sessions in iTerm tabs.

## Arguments
- $ARGUMENTS: Command and parameters

## Available Commands

### List all workers
```bash
~/.claude/scripts/orchestrator.sh list
```

### Read output from a worker tab
```bash
# Read last 50 lines from tab 2
~/.claude/scripts/orchestrator.sh read 2 50
```

### Send message to a worker
```bash
~/.claude/scripts/orchestrator.sh send 2 "Your message here"
```

### Initialize a worker with its task
```bash
~/.claude/scripts/orchestrator.sh init 2 "worker-name"
```

### Initialize all workers from session log
```bash
~/.claude/scripts/orchestrator.sh init-all
```

### List open PRs
```bash
~/.claude/scripts/orchestrator.sh prs
```

## Instructions

Parse `$ARGUMENTS` and execute the appropriate command:

1. If "list" or "status" → run `~/.claude/scripts/orchestrator.sh list`
2. If "read <tab>" → run `~/.claude/scripts/orchestrator.sh read <tab> 50`
3. If "send <tab> <message>" → run `~/.claude/scripts/orchestrator.sh send <tab> "<message>"`
4. If "init <tab> <name>" → run `~/.claude/scripts/orchestrator.sh init <tab> "<name>"`
5. If "init-all" → run `~/.claude/scripts/orchestrator.sh init-all`
6. If "prs" → run `~/.claude/scripts/orchestrator.sh prs`

Report results back to the user.
