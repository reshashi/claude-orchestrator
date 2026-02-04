#!/usr/bin/env bash
# Get status of all worker tabs
# Usage: worker-status.sh

osascript << 'APPLESCRIPT'
tell application "iTerm"
    tell current window
        set tabCount to count of tabs
        set output to ""
        repeat with t from 1 to tabCount
            tell tab t
                tell current session
                    set tabName to name
                    set output to output & "Tab " & t & ": " & tabName & "\n"
                end tell
            end tell
        end repeat
        return output
    end tell
end tell
APPLESCRIPT
