# Architecture

This document explains how Claude Code Orchestrator works under the hood.

## Overview

The orchestrator system enables parallel AI development through:

1. **Git Worktrees** - Isolated working directories for each worker
2. **iTerm Automation** - AppleScript-based tab management
3. **State Machine** - Tracking worker progress through defined states
4. **Quality Gates** - Automated review before merging

```
┌──────────────────────────────────────────────────────────────────┐
│                        ORCHESTRATOR (Tab 1)                       │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   /spawn    │  │   /status   │  │  orchestrator-loop.sh   │  │
│  │  command    │  │   command   │  │   (automated mode)      │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                     │                 │
└─────────┼────────────────┼─────────────────────┼─────────────────┘
          │                │                     │
          ▼                ▼                     ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                     WORKER TABS (2, 3, 4...)                │
    │                                                             │
    │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │
    │  │ Worker 1 │  │ Worker 2 │  │ Worker 3 │  │ Worker N │       │
    │  │ worktree │  │ worktree │  │ worktree │  │ worktree │       │
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
    │   ├── src/
    │   └── ...
    ├── auth-api/             # Worktree 2
    │   ├── .git
    │   ├── src/
    │   └── ...
    └── auth-ui/              # Worktree 3
        ├── .git
        ├── src/
        └── ...
```

### Worktree Management

The `wt.sh` script handles worktree operations:

```bash
# Create a worktree
wt create my-project auth-feature main
# Creates ~/.worktrees/my-project/auth-feature on feature/auth-feature branch

# List worktrees
wt list my-project

# Remove a worktree
wt remove my-project auth-feature
```

## iTerm Automation

### AppleScript Integration

The orchestrator uses AppleScript to control iTerm2:

```applescript
-- Open new tab
tell application "iTerm"
    tell current window
        create tab with default profile
    end tell
end tell

-- Run command in tab
tell application "iTerm"
    tell session N of current tab of current window
        write text "cd ~/.worktrees/project/worker && claude"
    end tell
end tell

-- Read tab output
tell application "iTerm"
    tell session N of current tab of current window
        get contents
    end tell
end tell
```

### Tab Numbering

- Tab 1: Orchestrator (main session)
- Tab 2: Worker 1
- Tab 3: Worker 2
- Tab N+1: Worker N

## State Machine

### Worker States

Each worker progresses through defined states:

```
UNKNOWN → NEEDS_INIT → WORKING → PR_OPEN → MERGED → (closed)
              ↑                      ↓
              └──────── ERROR ←──────┘
```

| State | Description | Next Actions |
|-------|-------------|--------------|
| `UNKNOWN` | Tab just opened | Detect Claude prompt |
| `NEEDS_INIT` | Claude ready, awaiting task | Send initialization prompt |
| `WORKING` | Claude actively working | Monitor for PR creation |
| `PR_OPEN` | PR created, awaiting review | Monitor CI, run /review |
| `MERGED` | PR merged | Close tab, cleanup |
| `ERROR` | Something went wrong | Log error, notify |

### State Detection

The orchestrator loop reads tab output and uses regex patterns to detect states:

```bash
# Claude prompt detection
if [[ "$output" =~ "You:" || "$output" =~ ">" ]]; then
    state="NEEDS_INIT"
fi

# PR creation detection
if [[ "$output" =~ "PR created" || "$output" =~ "pull request" ]]; then
    state="PR_OPEN"
fi

# MCP prompt detection
if [[ "$output" =~ "Do you trust" || "$output" =~ "MCP" ]]; then
    # Send Enter to accept
fi
```

### State Persistence

State is persisted in files to survive script restarts:

```
~/.claude/worker-states/
├── tab2_state           # Current state: WORKING, PR_OPEN, etc.
├── tab2_initialized     # Boolean: has worker been initialized?
├── tab2_pr              # PR number if open
├── tab2_reviewed        # Boolean: has /review passed?
└── tab2_merged          # Boolean: has PR been merged?
```

## Orchestrator Loop

### Manual Mode

In manual mode, you control each step:

```
/spawn → (worker works) → /status → /review → gh pr merge → /merge
```

### Automated Mode

The orchestrator loop (`orchestrator-loop.sh`) automates the entire pipeline:

```bash
while true; do
    for tab in $(get_worker_tabs); do
        output=$(read_tab $tab)
        state=$(detect_state $output)

        case $state in
            NEEDS_INIT)
                send_init_prompt $tab
                ;;
            MCP_PROMPT)
                send_enter $tab
                ;;
            PR_OPEN)
                if ci_passed $tab; then
                    run_review $tab
                fi
                if review_passed $tab; then
                    merge_pr $tab
                fi
                ;;
            MERGED)
                close_tab $tab
                cleanup_worktree $tab
                ;;
        esac
    done

    sleep 5
done
```

### Loop Control

```bash
# Start the loop
orchestrator-start  # alias for: orchestrator-loop.sh &

# Check status
orchestrator-status  # Checks PID file

# Stop the loop
orchestrator-stop    # Sends SIGTERM to loop process
```

## Quality Gates

### Review Pipeline

Before a PR can be merged, it must pass quality gates:

```
CI Passes → QA Guardian → (DevOps Engineer)* → (Code Simplifier)* → Merge
                                ↑                      ↑
                         If infra files         If 100+ lines
```

### QA Guardian

Reviews code against project policies:
- Architecture compliance (5-layer boundaries)
- Test coverage (90%+ on new code)
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

Triggered for large PRs (100+ lines):
- Removes dead code
- Simplifies logic
- Improves naming
- Extracts duplicates
- NO behavior changes

## Communication

### Orchestrator → Worker

```bash
# Send text to worker tab
osascript <<EOF
tell application "iTerm"
    tell session 2 of current tab of current window
        write text "Your task: implement login API"
    end tell
end tell
EOF
```

### Worker → Orchestrator

Workers communicate via:
1. **Console output** - Orchestrator reads tab contents
2. **Git commits** - Orchestrator monitors branch activity
3. **PRs** - Orchestrator monitors via GitHub API

### Session Log

All worker activity is logged:

```
~/.claude/active-sessions.log
├── auth-db|feature/auth-db|~/.worktrees/project/auth-db|task description
├── auth-api|feature/auth-api|~/.worktrees/project/auth-api|task description
└── auth-ui|feature/auth-ui|~/.worktrees/project/auth-ui|task description
```

## Security Considerations

### Permission Isolation

Each worker only has access to its worktree. The main repository and other worktrees are not accessible from a worker session.

### Prompt Injection

Workers receive their task via the spawn command. The task description is sanitized before being sent to prevent prompt injection.

### Review Enforcement

All PRs must pass `/review` before merge. This prevents workers from merging code that violates project policies.

## Performance

### Parallel Execution

- Workers run truly in parallel (separate processes)
- No blocking between workers
- CI runs can be parallel per GitHub Actions limits

### Resource Usage

- Each Claude session: ~100MB memory
- Each worktree: ~50MB disk (shared .git)
- Orchestrator loop: ~10MB memory

### Limits

- Recommended max workers: 5-10 concurrent
- Limited by: Claude API rate limits, CI runner availability
- Worktrees: Essentially unlimited (disk space)
