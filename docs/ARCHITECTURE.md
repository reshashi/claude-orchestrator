# Architecture

This document explains how Claude Code Orchestrator works under the hood.

## Overview

The orchestrator system enables parallel AI development through:

1. **Git Worktrees** - Isolated working directories for each worker
2. **Node.js Process Management** - Cross-platform background process spawning
3. **JSONL Streaming** - Real-time output parsing from Claude CLI
4. **State Machine** - Tracking worker progress through defined states
5. **Quality Gates** - Automated review before merging

```
┌──────────────────────────────────────────────────────────────────┐
│                        ORCHESTRATOR                               │
│                   (Node.js Background Process)                    │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   /spawn    │  │   /status   │  │   orchestrator loop     │  │
│  │  command    │  │   command   │  │   (automated mode)      │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                     │                 │
└─────────┼────────────────┼─────────────────────┼─────────────────┘
          │                │                     │
          ▼                ▼                     ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                  WORKER PROCESSES                            │
    │             (Claude CLI with --print mode)                   │
    │                                                             │
    │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │
    │  │ Worker 1 │  │ Worker 2 │  │ Worker 3 │  │ Worker N │       │
    │  │ worktree │  │ worktree │  │ worktree │  │ worktree │       │
    │  │ stdout→  │  │ stdout→  │  │ stdout→  │  │ stdout→  │       │
    │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘       │
    │       │            │            │            │             │
    └───────┼────────────┼────────────┼────────────┼─────────────┘
            │            │            │            │
            ▼            ▼            ▼            ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                    GIT REPOSITORY                           │
    │                                                             │
    │   main ────┬──────┬──────┬──────┬──────────────────────    │
    │            │      │      │      │                          │
    │            ▼      ▼      ▼      ▼                          │
    │       feature/ feature/ feature/ feature/                  │
    │       worker1  worker2  worker3  workerN                   │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘
```

## Process Model

### Previous (macOS-only)
- Workers ran in iTerm tabs
- AppleScript used for terminal automation
- State detected via regex on terminal output
- macOS-specific, no Linux/Windows support

### Current (Cross-platform)
- Workers spawn via `child_process.spawn()`
- Claude CLI runs with `--print --output-format stream-json`
- State detected via JSONL message parsing
- Works on macOS, Linux, and Windows

### Spawning a Worker

```typescript
const proc = spawn('claude', [
  '--print',
  '--output-format', 'stream-json',
  '--dangerously-skip-permissions',
  task,
], {
  cwd: worktreePath,
  stdio: ['pipe', 'pipe', 'pipe'],
});
```

### Communication Channels

| Direction | Channel | Format |
|-----------|---------|--------|
| Claude → Orchestrator | stdout | JSONL stream |
| Orchestrator → Claude | stdin | Plain text |
| Errors | stderr | Plain text |

## Git Worktrees

### What is a Worktree?

A git worktree is an additional working directory linked to a repository. Each worktree:
- Has its own branch
- Has its own working directory
- Shares the same `.git` repository

This allows multiple Claude sessions to work on different branches simultaneously without interference.

### Worktree Structure

```
~/.worktrees/
└── my-project/
    ├── auth-db/              # Worktree 1
    │   ├── .git              # Link to main repo
    │   ├── WORKER_CLAUDE.md  # Worker-specific instructions
    │   ├── src/
    │   └── ...
    ├── auth-api/             # Worktree 2
    │   ├── .git
    │   ├── WORKER_CLAUDE.md
    │   ├── src/
    │   └── ...
    └── auth-ui/              # Worktree 3
        ├── .git
        ├── WORKER_CLAUDE.md
        ├── src/
        └── ...
```

## State Machine

### Worker States

Each worker progresses through defined states:

```
SPAWNING → INITIALIZING → WORKING → PR_OPEN → REVIEWING → MERGING → MERGED
              ↑              ↓          ↓          ↓
              └──────────── ERROR ←─────┴──────────┘
```

| State | Description | Next Actions |
|-------|-------------|--------------|
| `SPAWNING` | Process starting | Wait for Claude to load |
| `INITIALIZING` | Claude loading, reading instructions | Detect first tool use |
| `WORKING` | Claude actively working | Monitor for PR creation |
| `PR_OPEN` | PR created, awaiting CI/review | Check CI, run /review |
| `REVIEWING` | QA review in progress | Wait for review result |
| `MERGING` | PR being merged | Execute merge |
| `MERGED` | PR merged, complete | Cleanup |
| `ERROR` | Something went wrong | Intervention required |
| `STOPPED` | Process terminated | Restart or cleanup |

### State Detection (JSONL)

The orchestrator parses Claude's JSON output to detect state transitions:

```typescript
// Tool use indicates active work
if (message.type === 'assistant' && hasToolUse(message)) {
  transitionState(workerId, 'WORKING');
}

// PR URL detection
const prUrl = extractPrUrl(message);
if (prUrl) {
  transitionState(workerId, 'PR_OPEN');
}

// Review completion
const reviewResult = isReviewComplete(message);
if (reviewResult === 'passed') {
  transitionState(workerId, 'MERGING');
}
```

### State Persistence

State is persisted to disk for recovery:

```
~/.claude/workers/
├── registry.json             # All workers index
└── <worker-id>/
    ├── state.json            # Current state + metadata
    ├── output.jsonl          # Captured stdout
    └── errors.log            # Captured stderr
```

## Orchestrator Loop

The main loop monitors all workers and manages their lifecycle:

```typescript
while (running) {
  for (const worker of workers) {
    // Skip terminal states
    if (isTerminalState(worker.state)) continue;

    // Check for intervention needs
    if (needsIntervention(worker)) {
      await handleIntervention(worker);
      continue;
    }

    // State-specific handling
    switch (worker.state) {
      case 'PR_OPEN':
        await handlePrOpen(worker);  // Check CI, run review
        break;
      case 'REVIEWING':
        await handleReviewing(worker);  // Wait for review
        break;
      case 'MERGING':
        await handleMerging(worker);  // Execute merge
        break;
    }
  }

  await sleep(pollInterval);
}
```

## Quality Gates

### Review Pipeline

Before a PR can be merged, it must pass quality gates:

```
CI Passes → QA Guardian → (DevOps Engineer)* → (Code Simplifier)* → Merge
                                ↑                      ↑
                         If infra files         If 50+ lines
```

### QA Guardian

Reviews code against project policies:
- Architecture compliance (layer boundaries)
- Test coverage
- Code quality (TypeScript, error handling)
- Security (RLS, input validation)
- Git workflow (conventional commits)

### DevOps Engineer

Triggered for infrastructure changes:
- `.github/workflows/` - CI/CD pipelines
- `vercel.json` - Deployment config
- `supabase/` - Database migrations
- `Dockerfile`, `docker-compose.yml`
- Environment files

### Code Simplifier

Triggered for large PRs (50+ lines):
- Removes dead code
- Simplifies logic
- Improves naming
- Extracts duplicates
- NO behavior changes

## File Structure (Node.js Implementation)

```
~/.claude-orchestrator/
├── package.json              # Node.js project
├── tsconfig.json             # TypeScript config
├── src/
│   ├── index.ts              # Entry point & exports
│   ├── types.ts              # Type definitions
│   ├── orchestrator.ts       # Main orchestration loop
│   ├── worker-manager.ts     # Process spawning & lifecycle
│   ├── state-manager.ts      # Persistence & recovery
│   ├── state-machine.ts      # State transitions
│   ├── jsonl-parser.ts       # Claude output parsing
│   ├── github.ts             # GitHub PR operations
│   ├── logger.ts             # Structured logging
│   └── cli.ts                # CLI commands
├── dist/                     # Compiled JavaScript
├── bin/
│   └── claude-orchestrator   # CLI executable
├── commands/                 # Skill definitions
├── agents/                   # Agent definitions
└── docs/                     # Documentation
```

## Security Considerations

### Permission Isolation

Each worker only has access to its worktree. The main repository and other worktrees are not accessible from a worker session.

### Dangerous Permissions

The `--dangerously-skip-permissions` flag is used for background workers. For security:
- Workers only operate in isolated worktrees
- PR review gates catch issues before merge
- Worktrees can be deleted without affecting main repo

### Review Enforcement

All PRs must pass QA review before merge. This prevents workers from merging code that violates project policies.

## CLI Commands

```bash
# Spawn a new worker
claude-orchestrator spawn <name> <task> [--repo <name>] [--no-start]

# List workers
claude-orchestrator list [--all]

# Check status
claude-orchestrator status [worker-id]

# Read output
claude-orchestrator read <worker-id> [--lines N]

# Send message
claude-orchestrator send <worker-id> <message>

# Stop worker
claude-orchestrator stop <worker-id>

# Merge PR
claude-orchestrator merge <worker-id>

# Cleanup
claude-orchestrator cleanup [worker-id]

# Run monitoring loop
claude-orchestrator loop [--poll <ms>]
```

## Performance

### Parallel Execution

- Workers run truly in parallel (separate processes)
- No blocking between workers
- CI runs can be parallel per GitHub Actions limits

### Resource Usage

- Each Claude process: ~100MB memory
- Each worktree: ~50MB disk (shared .git)
- Orchestrator: ~20MB memory

### Limits

- Recommended max workers: 5-10 concurrent
- Limited by: Claude API rate limits, CI runner availability
- Worktrees: Essentially unlimited (disk space)

## Migration from v1 (Bash/AppleScript)

The v2 Node.js implementation replaces the bash scripts:

| v1 (Bash) | v2 (Node.js) |
|-----------|--------------|
| `start-worker.sh` | `WorkerManager.spawn()` |
| `orchestrator-loop.sh` | `Orchestrator.start()` |
| `worker-status.sh` | `orchestrator status` |
| `worker-read.sh` | `orchestrator read` |
| `worker-send.sh` | `orchestrator send` |
| iTerm tabs | Background processes |
| AppleScript | child_process.spawn |
| Regex parsing | JSONL parsing |

The bash scripts in `scripts/` are kept for backwards compatibility but are no longer required.
