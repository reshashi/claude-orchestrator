---
description: Create a new worktree and spawn a Claude worker session with a specific task
allowed-tools: Bash(git:*), Bash(mkdir:*), Bash(echo:*), Bash(cat:*), Bash(~/.claude/scripts/start-worker.sh:*), Bash(~/.claude/scripts/orchestrator.sh:*), Bash(sleep:*)
---

# Spawn Worker Session

Create an isolated worktree for parallel development, then automatically start and initialize a Claude worker in a new iTerm tab.

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

4. Create a session-specific CLAUDE.md in the worktree that:
   - States this worker's specific task
   - Lists which files/directories this worker OWNS (can modify)
   - Lists which files/directories are OFF-LIMITS
   - References the main CLAUDE.md for coding standards

5. Update the orchestrator's tracking file:
```bash
echo "$1|$BRANCH_NAME|$WORKTREE_PATH|$(date)|$2" >> ~/.claude/active-sessions.log
```

6. **Automatically start the worker** in a new iTerm tab:
```bash
~/.claude/scripts/start-worker.sh "$1" "$REPO_NAME"
```

7. **Wait for Claude to load, then initialize with task**:
```bash
sleep 5  # Wait for Claude to start and show MCP prompt
# Get the tab number (newest tab)
TAB_NUM=$(osascript -e 'tell application "iTerm" to tell current window to return count of tabs')
# Send Enter to confirm MCP servers, then send task prompt
~/.claude/scripts/orchestrator.sh send $TAB_NUM ""
sleep 2
~/.claude/scripts/orchestrator.sh init $TAB_NUM "$1"
```

8. Output confirmation:
```
✓ Worker '$1' spawned, started, and initialized!

Session: $1
Branch: feature/$1
Path: ~/.worktrees/[repo]/$1
Task: [task description]

The worker is running in iTerm tab $TAB_NUM and has received its task.
Worker will read CLAUDE.md and begin working autonomously.
```
