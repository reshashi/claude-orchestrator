# Memory System Guide

## Three-Tier Architecture

### Seed Tier (`~/.claude/orchestrator/seed/`)
Built-in orchestrator training that ships with installation.
- Read-only orchestrator DNA
- Worker training templates
- Domain classifications
- Best practices

### User Tier (`~/.claude/memory/user/`)
Your cross-project preferences and standards.
- Coding style preferences
- Git workflows
- Testing standards
- Personal conventions

### Project Tier (`{project}/.claude/memory/`)
Project-specific learnings and patterns.
- Orchestrator's project-specific memory
- Domain-specific worker patterns
- Shared project facts
- Session summaries

## Memory Precedence

When loading memory: **Seed → User → Project**

- Seed provides base defaults
- User overrides with your preferences
- Project overrides with project-specific patterns

## API Reference

### Reading Memory
```bash
# Read from specific tier
~/.claude/scripts/memory-tier-read.sh seed orchestrator
~/.claude/scripts/memory-tier-read.sh user preferences
~/.claude/scripts/memory-tier-read.sh project domains frontend

# Read from all tiers (shows precedence)
~/.claude/scripts/memory-tier-read.sh all domains
```

### Writing Memory
```bash
# User preferences (cross-project)
~/.claude/scripts/memory-write.sh user preferences '{"style": "tabs"}'

# Project-specific facts
~/.claude/scripts/memory-write.sh project fact "Uses Railway deployment"

# Domain-specific patterns
~/.claude/scripts/memory-write.sh project domain frontend '{"pattern": "..."}'
```

### Commands
```bash
# Remember a fact (project-specific)
/assistant remember "API rate limit is 100 req/min"

# Recall facts (searches project memory)
/assistant recall "deployment"

# Session handoff
/assistant session-end
```

## For Orchestrator

At startup:
1. Load seed memory (your built-in training)
2. Load user memory (global preferences)
3. Load project memory (this project's learnings)
4. Merge with project taking precedence

When spawning workers:
1. Identify worker domain (frontend, backend, etc.)
2. Load seed worker training template
3. Load user preferences
4. Load project domain-specific memory
5. Load project shared memory
6. Inject all into worker initialization

## For Workers

At startup:
1. You receive pre-loaded context from all three tiers
2. Read your domain-specific memory first
3. Read shared project memory second
4. Start your task

During work:
1. Capture architectural decisions
2. Document patterns that worked
3. Note integration points
4. Store in appropriate tier (domain vs shared)

At completion:
1. Your learnings are persisted
2. Future workers benefit from your discoveries
