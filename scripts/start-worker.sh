#!/usr/bin/env bash
# Start a Claude worker in a new iTerm tab within the orchestrator's window
# Usage: start-worker.sh <worker-name> [repo-name]
# Example: start-worker.sh privacy-policy medicalbills

WORKER_NAME="$1"
REPO_NAME="${2:-medicalbills}"
WORKTREE_PATH="$HOME/.worktrees/$REPO_NAME/$WORKER_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source window utilities
if [ -f "$SCRIPT_DIR/window-utils.sh" ]; then
    source "$SCRIPT_DIR/window-utils.sh"
fi

if [ -z "$WORKER_NAME" ]; then
    echo "Usage: start-worker.sh <worker-name> [repo-name]"
    exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
    echo "Error: Worktree not found at $WORKTREE_PATH"
    exit 1
fi

# Get the orchestrator window ID
WINDOW_ID=$(get_window_id 2>/dev/null)

if [ -z "$WINDOW_ID" ]; then
    echo "Warning: No orchestrator window ID found, using current window"
    # Fallback to current window behavior
    osascript << APPLESCRIPT
tell application "iTerm"
    tell current window
        create tab with default profile
        tell current session
            set name to "$WORKER_NAME"
            write text "cd $WORKTREE_PATH && claude"
        end tell
    end tell
end tell
APPLESCRIPT
else
    # Use the specific orchestrator window
    osascript << APPLESCRIPT
tell application "iTerm"
    tell window id $WINDOW_ID
        create tab with default profile
        tell current session
            set name to "$WORKER_NAME"
            write text "cd $WORKTREE_PATH && claude"
        end tell
    end tell
end tell
APPLESCRIPT
fi

echo "✓ Started worker '$WORKER_NAME' in new iTerm tab (window: ${WINDOW_ID:-current})"
