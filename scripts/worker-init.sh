#!/bin/bash
# Initialize a worker with its task prompt
# Usage: worker-init.sh <tab-number> <worker-name>

TAB="${1:-2}"
WORKER_NAME="$2"

MESSAGE="You are worker '$WORKER_NAME'. Read CLAUDE.md for your task and ownership rules. Enable auto-accept mode (Shift+Tab) and begin."

osascript << APPLESCRIPT
tell application "iTerm"
    tell current window
        tell tab $TAB
            tell current session
                write text "$MESSAGE"
            end tell
        end tell
    end tell
end tell
APPLESCRIPT
echo "Initialized worker '$WORKER_NAME' in tab $TAB"
