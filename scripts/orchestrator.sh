#!/bin/bash
# Orchestrator utilities for managing Claude worker sessions
# Source this or use individual functions

REPO_NAME="${REPO_NAME:-medicalbills}"

# List all worker tabs and their status
workers_list() {
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
}

# Read output from a worker tab (last N lines)
worker_read() {
    local TAB="${1:-2}"
    local LINES="${2:-50}"
    osascript << APPLESCRIPT | tail -$LINES
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
}

# Send a message to a worker tab
# Uses keystroke approach to ensure the message is properly submitted
worker_send() {
    local TAB="${1:-2}"
    local MESSAGE="$2"

    # First, type the message character by character using keystroke
    # Then press Return to submit
    osascript << APPLESCRIPT
tell application "iTerm"
    activate
    tell current window
        -- Select the target tab
        select tab $TAB
        delay 0.2
        tell tab $TAB
            tell current session
                -- Write the text (this puts it in the input)
                write text "$MESSAGE"
            end tell
        end tell
    end tell
end tell
-- Small delay then press Return to ensure submission
delay 0.3
tell application "System Events"
    tell process "iTerm2"
        keystroke return
    end tell
end tell
APPLESCRIPT
    echo "Sent to tab $TAB"
}

# Initialize a worker with its task prompt
worker_init() {
    local TAB="${1:-2}"
    local WORKER_NAME="$2"
    local MESSAGE="You are worker '$WORKER_NAME'. Read CLAUDE.md for your task and ownership rules. Enable auto-accept mode (Shift+Tab) and begin."
    worker_send "$TAB" "$MESSAGE"
    echo "Initialized worker '$WORKER_NAME' in tab $TAB"
}

# Initialize all workers from active-sessions.log
workers_init_all() {
    local TAB=2
    while IFS='|' read -r name branch path date task; do
        if [ -n "$name" ]; then
            worker_init "$TAB" "$name"
            ((TAB++))
            sleep 1
        fi
    done < <(tail -n 10 ~/.claude/active-sessions.log 2>/dev/null | grep "$REPO_NAME")
}

# Check for open PRs
prs_list() {
    gh pr list --state open --repo "Mudunuri-Ventures/$REPO_NAME" 2>/dev/null
}

# Show command help
show_help() {
    echo "Orchestrator Commands:"
    echo "  workers_list          - List all iTerm tabs"
    echo "  worker_read <tab> [n] - Read last n lines from tab"
    echo "  worker_send <tab> msg - Send message to tab"
    echo "  worker_init <tab> name - Initialize worker with task"
    echo "  workers_init_all      - Initialize all workers from log"
    echo "  prs_list              - List open PRs"
}

# If sourced, export functions; if run directly, execute command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        list) workers_list ;;
        read) worker_read "$2" "$3" ;;
        send) worker_send "$2" "$3" ;;
        init) worker_init "$2" "$3" ;;
        init-all) workers_init_all ;;
        prs) prs_list ;;
        *) show_help ;;
    esac
fi
