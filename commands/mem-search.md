# /mem-search - Search Worker Memory

Search the orchestrator's persistent memory for past worker observations, events, and activities.

## Usage

```bash
/mem-search <query> [options]
```

## Description

The memory system automatically captures worker lifecycle events, PR activities, errors, and task completions. Use `/mem-search` to query this history and recall what workers have done in past sessions.

## Examples

### Basic search
```bash
/mem-search "authentication"
# Finds all observations containing "authentication"
```

### Search by worker
```bash
/mem-search "error" --worker auth-api
# Find errors specific to the auth-api worker
```

### Search recent activity
```bash
/mem-search "merged" --since 2024-01-01
# Find all merged PRs since January 2024
```

### Search by event type
```bash
/mem-search "failed" --type error
# Find only error observations
```

## Options

| Option | Description |
|--------|-------------|
| `--worker <id>` | Filter by worker ID |
| `--type <type>` | Filter by observation type: `state_change`, `pr_event`, `error`, `task_complete`, `custom` |
| `--session <id>` | Filter by session ID |
| `--since <date>` | Only show results after this date (ISO format) |
| `--limit <n>` | Maximum number of results (default: 20) |

## Observation Types

| Type | Description |
|------|-------------|
| `state_change` | Worker state transitions (SPAWNING → WORKING → MERGED) |
| `pr_event` | PR created, reviewed, merged, or closed |
| `error` | Errors and failures |
| `task_complete` | Successful task completions |
| `message_sent` | Messages sent to workers |
| `custom` | Custom observations added via API |

## API Endpoint

The memory search is also available via HTTP API:

```bash
# Search via API
curl "http://localhost:3001/api/memory/search?q=authentication&limit=10"

# Get memory stats
curl "http://localhost:3001/api/memory/stats"

# List recent sessions
curl "http://localhost:3001/api/memory/sessions"
```

## How Memory Works

1. **Automatic Capture**: The orchestrator automatically captures:
   - Worker state transitions
   - PR events (created, merged, reviewed)
   - Errors and failures
   - Process exits

2. **Session-Based**: Each orchestrator run creates a new session. Sessions group related observations together.

3. **Full-Text Search**: Uses SQLite FTS5 for fast keyword search with ranking and snippets.

4. **Persistent Storage**: Memory is stored in `~/.claude/memory/memory.db` and persists across restarts.

## Use Cases

### Debugging
```bash
# What errors has this worker had?
/mem-search "error" --worker problematic-worker

# What happened in the last session?
/mem-search "" --session <session-id>
```

### Review History
```bash
# What PRs were created today?
/mem-search "PR" --type pr_event --since today

# How did the auth feature get implemented?
/mem-search "authentication" --limit 50
```

### Knowledge Recall
```bash
# Have we worked on caching before?
/mem-search "cache" --type task_complete

# What approach did we use for the database?
/mem-search "database migration"
```

## Related Commands

- `/status` - View current worker status
- `/workers` - List active workers
- `/project` - Start a new autonomous project
