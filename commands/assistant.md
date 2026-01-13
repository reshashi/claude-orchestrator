---
description: Orchestrator's assistant for memory management and meta-tasks
allowed-tools: Bash(~/.claude/scripts/memory-*.sh:*), Bash(~/.claude/scripts/session-*.sh:*), Bash(jq:*), Bash(cat:*), Read, Write
---

# /assistant - Orchestrator Assistant

A lightweight helper for memory management, toolchain tracking, and session handoffs.

## Arguments
- $ARGUMENTS: Subcommand and parameters

## Subcommands

### remember "fact"
Store a fact to persistent memory.

```bash
~/.claude/scripts/memory-write.sh fact "your fact here"
```

**Examples:**
- `/assistant remember "Project uses Bun instead of npm"`
- `/assistant remember "API rate limit is 100 req/min"`
- `/assistant remember "Deploy key is in 1Password vault 'DevOps'"`

### recall "topic"
Search memory for relevant facts.

```bash
~/.claude/scripts/memory-read.sh facts "search term"
```

**Examples:**
- `/assistant recall "deployment"`
- `/assistant recall "api keys"`
- `/assistant recall "project conventions"`

### toolchain add <name> <repo>
Register a tool in the toolchain registry.

```bash
~/.claude/scripts/memory-write.sh toolchain "<name>" '{"repo": "<repo>"}'
```

**Examples:**
- `/assistant toolchain add claude-orchestrator https://github.com/reshashi/claude-orchestrator`
- `/assistant toolchain add my-cli ~/projects/my-cli`

### toolchain list
List all registered tools.

```bash
~/.claude/scripts/memory-read.sh toolchain
```

### repos add <name> <url>
Register a repository for quick reference.

```bash
~/.claude/scripts/memory-write.sh repos "<name>" '{"url": "<url>"}'
```

**Examples:**
- `/assistant repos add frontend https://github.com/org/frontend`
- `/assistant repos add backend ~/work/backend`

### repos list
List all registered repositories.

```bash
~/.claude/scripts/memory-read.sh repos
```

### session-end
Generate a session handoff summary for continuity.

```bash
~/.claude/scripts/session-summary.sh
```

This creates a summary of the current session including:
- Tasks completed
- Current state
- Pending items
- Important context for next session

## Instructions

Parse `$ARGUMENTS` and execute the appropriate command:

1. If `remember "..."` -> Run `~/.claude/scripts/memory-write.sh fact "fact text"`
2. If `recall "..."` -> Run `~/.claude/scripts/memory-read.sh facts "search term"`
3. If `toolchain add <name> <repo>` -> Run `~/.claude/scripts/memory-write.sh toolchain "<name>" '{"repo": "<repo>"}'`
4. If `toolchain list` -> Run `~/.claude/scripts/memory-read.sh toolchain`
5. If `repos add <name> <url>` -> Run `~/.claude/scripts/memory-write.sh repos "<name>" '{"url": "<url>"}'`
6. If `repos list` -> Run `~/.claude/scripts/memory-read.sh repos`
7. If `session-end` -> Run `~/.claude/scripts/session-summary.sh`

Report results back to the user with confirmation of what was stored/retrieved.
