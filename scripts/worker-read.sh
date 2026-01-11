#!/bin/bash
# Read output from a worker tab
# Usage: worker-read.sh <tab-number>

TAB="${1:-2}"

osascript << APPLESCRIPT
tell application "iTerm"
    tell current window
        tell tab $TAB
            tell current session
                return contents
            end tell
        end tell
    end tell
end tell
APPLESCRIPT
