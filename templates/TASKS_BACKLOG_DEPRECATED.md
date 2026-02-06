# Tasks Backlog (DEPRECATED)

**This file format is deprecated.** Tasks have been migrated to the SQLite database.

## Migration Notice

As of orchestrator v3.5, the tasks backlog is stored in a SQLite database for:
- Better querying and filtering
- Structured metadata (priority, source, status)
- Integration with the memory system
- Full-text search

## Using the New System

**CLI Commands:**
```bash
# List pending tasks
~/.claude/scripts/backlog.sh list

# Add a task
~/.claude/scripts/backlog.sh add "Task description" --priority important

# Complete a task
~/.claude/scripts/backlog.sh complete 42

# Search tasks
~/.claude/scripts/backlog.sh search "validation"
```

**Slash Command:**
```
/backlog list
/backlog add "Task description"
/backlog complete 42
```

## Migration Details

- Migration occurred: $(date +%Y-%m-%d)
- Original file backed up as: TASKS_BACKLOG.md.pre-migration
- Tasks imported to: ~/.claude/orchestrator/global/memory.db

## Questions?

See the orchestrator documentation: https://github.com/reshashi/claude-orchestrator
