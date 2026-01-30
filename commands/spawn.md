---
description: Create a new worktree and spawn a Claude worker session with a specific task
allowed-tools: Bash(git:*), Bash(mkdir:*), Bash(echo:*), Bash(cat:*), Bash(node:*), Bash(npx:*)
---

# Spawn Worker Session

Create an isolated worktree for parallel development, then start a Claude worker as a background process.

**Platform**: Cross-platform (macOS, Linux, Windows)

## Arguments
- $1: Session name (e.g., "auth-flow", "billing-parser")
- $2: Task description (quoted string describing what this worker should do)

## Current Repository
- Repo root: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`

## Instructions

1. Extract the session name from $1: `$1`
2. Extract the task description: `$ARGUMENTS`

3. Create the worktree:
```bash
REPO_NAME=$(basename $(git rev-parse --show-toplevel))
WORKTREE_PATH="$HOME/.worktrees/$REPO_NAME/$1"
BRANCH_NAME="feature/$1"

mkdir -p "$HOME/.worktrees/$REPO_NAME"
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" HEAD
```

4. Create a session-specific WORKER_CLAUDE.md in the worktree with memory context:
```bash
# Classify worker domain and build three-tier memory context
WORKER_DOMAIN=$(~/.claude/scripts/classify-domain.sh "$2")
PROJECT_ROOT=$(git rev-parse --show-toplevel)

# Build comprehensive memory context from seed/user/project tiers
WORKER_CONTEXT=$(~/.claude/scripts/build-worker-context.sh "$1" "$WORKER_DOMAIN" "$2" "$PROJECT_ROOT")

# Create worker instructions file with memory context
cat > "$WORKTREE_PATH/WORKER_CLAUDE.md" <<EOF
$WORKER_CONTEXT

---

## Files You Own
[List which files/directories this worker can modify]

## Off-Limits Files
[List which files/directories are forbidden]

## Project Standards
See main CLAUDE.md in project root for architecture and quality standards.
EOF
```

The WORKER_CLAUDE.md file:
- States this worker's specific task
- Lists which files/directories this worker OWNS (can modify)
- Lists which files/directories are OFF-LIMITS
- References the main CLAUDE.md for coding standards
- Includes memory context from three tiers (seed/user/project)

5. **Spawn the worker using the new Node.js orchestrator**:
```bash
cd ~/.claude-orchestrator && node dist/index.js spawn "$1" "$2" --repo "$REPO_NAME" --no-start
```

Or if you want to also start the worker process immediately:
```bash
cd ~/.claude-orchestrator && node dist/index.js spawn "$1" "$2" --repo "$REPO_NAME"
```

Note: Using `--no-start` creates only the worktree. The worker can be started later manually.

6. Output confirmation:
```
Worker '$1' spawned!

Session: $1
Branch: feature/$1
Path: ~/.worktrees/[repo]/$1
Task: [task description]

To check status: claude-orchestrator status $1
To read output:  claude-orchestrator read $1
To send message: claude-orchestrator send $1 "message"
```

## Alternative: Manual Worker Start

If spawned with `--no-start`, start the worker manually:

```bash
cd ~/.worktrees/$REPO_NAME/$1 && claude
```

## Monitoring Workers

Use these commands to monitor background workers:

```bash
# List all workers
claude-orchestrator list

# Check specific worker status
claude-orchestrator status $1

# Read worker output
claude-orchestrator read $1 --lines 100

# Send message to worker
claude-orchestrator send $1 "Please continue"

# Stop a worker
claude-orchestrator stop $1

# Run monitoring loop (watches all workers)
claude-orchestrator loop
```
