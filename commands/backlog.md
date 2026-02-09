---
description: Manage the tasks backlog - add, list, complete, and search tasks
allowed-tools: Bash(~/.claude/scripts/backlog.sh:*), Read
---

# /backlog - Tasks Backlog Management

Manage suggestions, important issues, and future work items captured during development.

## Arguments
- $ARGUMENTS: Subcommand and arguments (e.g., "add 'Fix validation'", "list", "complete 42")

## Current State
!`~/.claude/scripts/backlog.sh list --limit 10 2>/dev/null || echo "Backlog database not initialized"`

## Instructions

Parse the arguments to determine the subcommand:

### list (default)
Show pending tasks, optionally filtered:
```bash
~/.claude/scripts/backlog.sh list [--status pending|completed|all] [--priority critical|important|suggestion] [--limit N]
```

### add <title>
Add a new task to the backlog:
```bash
~/.claude/scripts/backlog.sh add "Task title" --priority suggestion --source manual
```

Priority levels:
- `critical` - Must fix before merge/deploy
- `important` - Should fix soon
- `suggestion` - Nice to have, future improvement

Source types:
- `project` - From /project execution
- `review` - From /review findings
- `manual` - Manually added

### complete <id>
Mark a task as completed:
```bash
~/.claude/scripts/backlog.sh complete 42
```

### delete <id>
Remove a task from the backlog (soft delete):
```bash
~/.claude/scripts/backlog.sh delete 42
```

### search <query>
Search tasks by title or description:
```bash
~/.claude/scripts/backlog.sh search "validation"
```

### get <id>
Get full details of a specific task:
```bash
~/.claude/scripts/backlog.sh get 42
```

### stats
Show backlog statistics by status, priority, and source:
```bash
~/.claude/scripts/backlog.sh stats
```

## Examples

```
/backlog                           # List pending tasks
/backlog list                      # Same as above
/backlog list --status all         # Show all tasks including completed
/backlog add "Add input validation to user form"
/backlog add "Refactor auth service" --priority important --source review
/backlog complete 15
/backlog search "authentication"
/backlog stats
```

## Integration with /review

When running `/review`, suggestions and important findings should be added to the backlog:

```bash
# For suggestions from review
~/.claude/scripts/backlog.sh add "Consider using shared Card component" --priority suggestion --source review

# For important issues from review
~/.claude/scripts/backlog.sh add "Missing Zod validation on API endpoint" --priority important --source review --file "src/api/users.ts" --line 45
```

## Integration with /qcode

When running `/qcode` (auto-qcode.sh), all unfixed code quality issues are automatically recorded:

```bash
# Auto-qcode findings (added automatically)
~/.claude/scripts/backlog.sh add "qcode: 3 file(s) with trailing whitespace" --priority suggestion --source review
```

To disable backlog recording: `auto-qcode.sh --no-backlog`

## Integration with /project

During `/project` execution, any suggestions from quality gates that aren't critical should be added:

```bash
# Add project backlog items
~/.claude/scripts/backlog.sh add "Add E2E tests for new feature" --priority suggestion --source project
```
