#!/usr/bin/env bash
# Send a command/message to a worker tab
# Usage: worker-send.sh <tab-number> "message"

TAB="${1:-2}"
MESSAGE="$2"

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
echo "Sent to tab $TAB: $MESSAGE"
