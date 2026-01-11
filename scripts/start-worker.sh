#!/bin/bash
# Start a Claude worker in a new iTerm tab
# Usage: start-worker.sh <worker-name> [repo-name]
# Example: start-worker.sh privacy-policy medicalbills

WORKER_NAME="$1"
REPO_NAME="${2:-medicalbills}"
WORKTREE_PATH="$HOME/.worktrees/$REPO_NAME/$WORKER_NAME"

if [ -z "$WORKER_NAME" ]; then
  echo "Usage: start-worker.sh <worker-name> [repo-name]"
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Error: Worktree not found at $WORKTREE_PATH"
  exit 1
fi

osascript << APPLESCRIPT
tell application "iTerm"
  activate
  tell current window
    create tab with default profile
    tell current session
      set name to "$WORKER_NAME"
      write text "cd $WORKTREE_PATH && claude"
    end tell
  end tell
end tell
APPLESCRIPT

echo "✓ Started worker '$WORKER_NAME' in new iTerm tab"
