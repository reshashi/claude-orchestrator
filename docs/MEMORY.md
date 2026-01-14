# Memory System

The Memory System provides persistent storage for the orchestrator to remember facts, tools, and context across sessions.

## Overview

When you start a new Claude session, the orchestrator can recall:
- Tools and CLIs you use regularly
- Repositories you work with
- Facts and preferences you've told it
- What happened in previous sessions

## Directory Structure

```
~/.claude/memory/
├── toolchain.json      # Tools and CLIs used across projects
├── repos.json          # Known repositories
├── facts.json          # General facts to remember
├── projects/           # Per-project persistent context
│   └── {project}.json
└── sessions/           # Session handoff summaries
    └── {date}-{repo}.md
```

## Using the /assistant Command

### Store a Fact
```bash
/assistant remember "The API rate limit is 100 requests per minute"
```

### Recall Information
```bash
/assistant recall "rate limit"
```

### Register a Tool
```bash
/assistant toolchain add claude-orchestrator https://github.com/reshashi/claude-orchestrator
```

### List Tools
```bash
/assistant toolchain list
```

### Register a Repository
```bash
/assistant repos add frontend https://github.com/myorg/frontend
```

### List Repositories
```bash
/assistant repos list
```

### Generate Session Summary
```bash
/assistant session-end
```

## Decision Rubric

Use this guide to decide where information should be stored:

| Store in... | When... | Examples |
|-------------|---------|----------|
| `toolchain.json` | It's a tool/CLI used across projects | claude-orchestrator, gh CLI, npm packages |
| `repos.json` | It's a repository you work with | Project repos, forks, dependencies |
| `facts.json` | It's context the orchestrator should remember | "John prefers tabs", "Always run tests before PR" |
| `projects/{name}.json` | It's specific to one project | Sprint status, branch naming, team contacts |
| `sessions/*.md` | It's a handoff for next session | What was done, what's pending, blockers |

**Rule of thumb:** If you'd tell a new team member on day 1, it's global. If you'd only mention it when working on a specific project, it's per-repo.

## File Formats

### toolchain.json
```json
{
  "claude-orchestrator": {
    "repo": "https://github.com/reshashi/claude-orchestrator",
    "version": "2.4",
    "install": "curl -fsSL ... | bash",
    "update": "curl -fsSL ... | bash -s -- -y",
    "docs": "https://github.com/reshashi/claude-orchestrator#readme"
  }
}
```

### repos.json
```json
{
  "frontend": {
    "url": "https://github.com/myorg/frontend",
    "default_branch": "main",
    "description": "React frontend application"
  }
}
```

### facts.json
```json
{
  "facts": [
    {
      "text": "Project uses Borda count for voting",
      "added": "2026-01-13T10:30:00Z",
      "tags": ["voting", "algorithm"]
    }
  ]
}
```

### Session Summary (sessions/*.md)
```markdown
# Session Summary: 2026-01-13 - contested

## Completed
- Sprint 5 Phase 6: Testing & Documentation
- All 57 backend tests passing
- Frontend builds successfully

## Pending
- Sprint 6: Comments System

## Context for Next Session
- Main branch is up to date
- Ready to start new feature work
```

## Scripts

The memory system uses these scripts:

- `~/.claude/scripts/memory-read.sh` - Read from memory files
- `~/.claude/scripts/memory-write.sh` - Write to memory files
- `~/.claude/scripts/session-summary.sh` - Generate session summaries

### Direct Script Usage

```bash
# Read all toolchain entries
~/.claude/scripts/memory-read.sh toolchain

# Read a specific tool
~/.claude/scripts/memory-read.sh toolchain claude-orchestrator

# Search facts
~/.claude/scripts/memory-read.sh facts "rate limit"

# Add a fact
~/.claude/scripts/memory-write.sh fact "The API uses JWT tokens"

# Add a tool
~/.claude/scripts/memory-write.sh toolchain my-tool '{"repo": "https://github.com/user/my-tool"}'

# Generate session summary
~/.claude/scripts/session-summary.sh
```

## Troubleshooting

### Memory files not found
Run the installer again to create the directory structure:
```bash
curl -fsSL https://raw.githubusercontent.com/reshashi/claude-orchestrator/main/install.sh | bash
```

### jq not installed
The memory scripts require jq for JSON manipulation:
```bash
brew install jq
```

### Facts not persisting
Check that `~/.claude/memory/facts.json` exists and is valid JSON:
```bash
cat ~/.claude/memory/facts.json | jq .
```
