#!/usr/bin/env bash
# Window management utilities for Claude Orchestrator
# Ensures all tab operations happen in the orchestrator's window

STATE_DIR="$HOME/.claude"
WINDOW_ID_FILE="$STATE_DIR/orchestrator-window-id"

# Get the orchestrator window ID
# Priority: 1) Environment variable, 2) File, 3) Current window (fallback)
get_window_id() {
    local WINDOW_ID

    # Check environment variable first
    if [ -n "$ORCHESTRATOR_WINDOW_ID" ]; then
        echo "$ORCHESTRATOR_WINDOW_ID"
        return 0
    fi

    # Check file
    if [ -f "$WINDOW_ID_FILE" ]; then
        WINDOW_ID=$(cat "$WINDOW_ID_FILE")
        if [ -n "$WINDOW_ID" ]; then
            # Verify window still exists
            local EXISTS
            EXISTS=$(osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm"
    try
        set w to window id $WINDOW_ID
        return "yes"
    on error
        return "no"
    end try
end tell
APPLESCRIPT
)
            if [ "$EXISTS" = "yes" ]; then
                echo "$WINDOW_ID"
                return 0
            fi
        fi
    fi

    # Fallback: get current window (legacy behavior)
    osascript << 'APPLESCRIPT' 2>/dev/null
tell application "iTerm"
    if (count of windows) > 0 then
        return id of current window
    else
        return ""
    end if
end tell
APPLESCRIPT
}

# Set the window ID (call this from orchestrator startup)
set_window_id() {
    local WINDOW_ID="$1"
    mkdir -p "$STATE_DIR"
    echo "$WINDOW_ID" > "$WINDOW_ID_FILE"
    export ORCHESTRATOR_WINDOW_ID="$WINDOW_ID"
}

# Clear the window ID (call on orchestrator shutdown)
clear_window_id() {
    rm -f "$WINDOW_ID_FILE"
    unset ORCHESTRATOR_WINDOW_ID
}

# Create a new tab in the orchestrator's window
# Usage: create_tab_in_window [tab_name]
create_tab_in_window() {
    local TAB_NAME="${1:-Worker}"
    local WINDOW_ID
    WINDOW_ID=$(get_window_id)

    if [ -z "$WINDOW_ID" ]; then
        echo "Error: No orchestrator window ID found" >&2
        return 1
    fi

    osascript << APPLESCRIPT
tell application "iTerm"
    tell window id $WINDOW_ID
        create tab with default profile
        tell current session
            set name to "$TAB_NAME"
        end tell
    end tell
end tell
APPLESCRIPT
}

# Get tab count in the orchestrator's window
get_tab_count() {
    local WINDOW_ID
    WINDOW_ID=$(get_window_id)

    if [ -z "$WINDOW_ID" ]; then
        echo "0"
        return 1
    fi

    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm"
    tell window id $WINDOW_ID
        return count of tabs
    end tell
end tell
APPLESCRIPT
}

# Get list of tab indices in the orchestrator's window (excluding tab 1)
get_worker_tabs() {
    local WINDOW_ID
    WINDOW_ID=$(get_window_id)

    if [ -z "$WINDOW_ID" ]; then
        echo ""
        return 1
    fi

    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm"
    tell window id $WINDOW_ID
        set tabCount to count of tabs
        set output to ""
        repeat with t from 2 to tabCount
            set output to output & t & " "
        end repeat
        return output
    end tell
end tell
APPLESCRIPT
}

# Read output from a specific tab in the orchestrator's window
read_tab_output() {
    local TAB="$1"
    local LINES="${2:-100}"
    local WINDOW_ID
    WINDOW_ID=$(get_window_id)

    if [ -z "$WINDOW_ID" ]; then
        return 1
    fi

    osascript << APPLESCRIPT 2>/dev/null | tail -"$LINES"
tell application "iTerm"
    tell window id $WINDOW_ID
        tell tab $TAB
            tell current session
                return contents
            end tell
        end tell
    end tell
end tell
APPLESCRIPT
}

# Send text to a specific tab in the orchestrator's window
send_to_tab() {
    local TAB="$1"
    local MESSAGE="$2"
    local WINDOW_ID
    WINDOW_ID=$(get_window_id)

    if [ -z "$WINDOW_ID" ]; then
        return 1
    fi

    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm"
    tell window id $WINDOW_ID
        tell tab $TAB
            tell current session
                write text "$MESSAGE"
            end tell
        end tell
    end tell
end tell
APPLESCRIPT
}

# Close a specific tab in the orchestrator's window
close_tab() {
    local TAB="$1"
    local WINDOW_ID
    WINDOW_ID=$(get_window_id)

    if [ -z "$WINDOW_ID" ]; then
        return 1
    fi

    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm"
    tell window id $WINDOW_ID
        tell tab $TAB
            close
        end tell
    end tell
end tell
APPLESCRIPT
}

# Export functions
export -f get_window_id set_window_id clear_window_id
export -f create_tab_in_window get_tab_count get_worker_tabs
export -f read_tab_output send_to_tab close_tab
export WINDOW_ID_FILE
