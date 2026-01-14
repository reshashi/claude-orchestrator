#!/bin/bash
# Structured JSON logging for Claude Orchestrator
# Usage: source this file, then call log_event or log_* functions

# Configuration
LOG_DIR="${LOG_DIR:-$HOME/.claude/logs}"
JSON_LOG_FILE="${JSON_LOG_FILE:-$LOG_DIR/orchestrator.jsonl}"
TEXT_LOG_FILE="${TEXT_LOG_FILE:-$HOME/.claude/orchestrator.log}"
LOG_LEVEL="${LOG_LEVEL:-info}"  # debug, info, warn, error

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log level priorities (lower = more verbose)
declare -A LOG_LEVELS=(
    ["debug"]=0
    ["info"]=1
    ["warn"]=2
    ["error"]=3
)

# Check if a level should be logged based on LOG_LEVEL setting
should_log() {
    local level="$1"
    local current_priority="${LOG_LEVELS[$LOG_LEVEL]:-1}"
    local level_priority="${LOG_LEVELS[$level]:-1}"
    [ "$level_priority" -ge "$current_priority" ]
}

# Core logging function - emits JSON to file and text to stderr
# Usage: log_event <event> <level> <message> [json_fields...]
# Example: log_event "worker_state_change" "info" "State changed" '{"worker": {"tab": 2}}'
log_event() {
    local event="$1"
    local level="$2"
    local message="$3"
    local extra_json="${4:-{}}"

    # Check if we should log at this level
    if ! should_log "$level"; then
        return 0
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build JSON event
    local json_event
    json_event=$(jq -n -c \
        --arg ts "$timestamp" \
        --arg event "$event" \
        --arg level "$level" \
        --arg msg "$message" \
        --argjson extra "$extra_json" \
        '{timestamp: $ts, event: $event, level: $level, message: $msg} + $extra' 2>/dev/null)

    # If jq fails, fallback to simple format
    if [ -z "$json_event" ]; then
        json_event="{\"timestamp\":\"$timestamp\",\"event\":\"$event\",\"level\":\"$level\",\"message\":\"$message\"}"
    fi

    # Write JSON to log file (atomic append)
    echo "$json_event" >> "$JSON_LOG_FILE"

    # Also write human-readable text to stderr and text log file (backward compatibility)
    local text_line
    text_line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
    echo "$text_line" >> "$TEXT_LOG_FILE"
    echo "$text_line" >&2
}

# Convenience functions for common events

log_debug() {
    log_event "generic" "debug" "$1" "${2:-{}}"
}

log_info() {
    log_event "generic" "info" "$1" "${2:-{}}"
}

log_warn() {
    log_event "generic" "warn" "$1" "${2:-{}}"
}

log_error() {
    log_event "error" "error" "$1" "${2:-{}}"
}

# Orchestrator lifecycle events
log_orchestrator_started() {
    local pid="$1"
    log_event "orchestrator_started" "info" "Orchestrator started (PID: $pid)" \
        "$(jq -n --arg pid "$pid" '{metadata: {pid: $pid}}')"
}

log_orchestrator_stopped() {
    log_event "orchestrator_stopped" "info" "Orchestrator stopped" "{}"
}

# Worker state events
log_worker_state_change() {
    local tab="$1"
    local from_state="$2"
    local to_state="$3"
    local worker_name="${4:-}"
    local branch="${5:-}"

    local extra
    extra=$(jq -n -c \
        --argjson tab "$tab" \
        --arg from "$from_state" \
        --arg to "$to_state" \
        --arg name "$worker_name" \
        --arg branch "$branch" \
        '{
            worker: {tab: $tab, name: (if $name == "" then null else $name end), branch: (if $branch == "" then null else $branch end)},
            state: {from: $from, to: $to}
        }')

    log_event "worker_state_change" "info" "Tab $tab: $from_state -> $to_state" "$extra"
}

log_worker_initialized() {
    local tab="$1"
    local worker_name="${2:-}"

    local extra
    extra=$(jq -n -c --argjson tab "$tab" --arg name "$worker_name" \
        '{worker: {tab: $tab, name: (if $name == "" then null else $name end)}}')

    log_event "worker_initialized" "info" "Tab $tab initialized" "$extra"
}

log_worker_nudged() {
    local tab="$1"
    local state="$2"
    local action="$3"

    local extra
    extra=$(jq -n -c --argjson tab "$tab" --arg state "$state" --arg action "$action" \
        '{worker: {tab: $tab}, state: {to: $state}, metadata: {action: $action}}')

    log_event "worker_nudged" "debug" "Tab $tab nudged ($state): $action" "$extra"
}

# PR events
log_pr_detected() {
    local tab="$1"
    local pr_num="$2"
    local branch="${3:-}"

    local extra
    extra=$(jq -n -c --argjson tab "$tab" --argjson pr "$pr_num" --arg branch "$branch" \
        '{worker: {tab: $tab, branch: (if $branch == "" then null else $branch end)}, pr: {number: $pr}}')

    log_event "pr_detected" "info" "Tab $tab has PR #$pr_num" "$extra"
}

log_pr_ci_status() {
    local pr_num="$1"
    local status="$2"

    local extra
    extra=$(jq -n -c --argjson pr "$pr_num" --arg status "$status" \
        '{pr: {number: $pr, status: $status}}')

    log_event "pr_ci_status" "info" "PR #$pr_num CI status: $status" "$extra"
}

log_pr_merged() {
    local pr_num="$1"
    local tab="${2:-}"

    local extra
    extra=$(jq -n -c --argjson pr "$pr_num" --argjson tab "${tab:-null}" \
        '{pr: {number: $pr}, worker: {tab: $tab}}')

    log_event "pr_merged" "info" "PR #$pr_num merged" "$extra"
}

# Review/Agent events
log_review_started() {
    local pr_num="$1"
    local branch="$2"
    local tab="$3"

    local extra
    extra=$(jq -n -c --argjson pr "$pr_num" --arg branch "$branch" --argjson tab "$tab" \
        '{pr: {number: $pr}, worker: {tab: $tab, branch: $branch}, agent: {name: "qa_guardian", result: "pending"}}')

    log_event "review_started" "info" "Running /review for PR #$pr_num (branch: $branch)" "$extra"
}

log_review_completed() {
    local pr_num="$1"
    local result="$2"

    local extra
    extra=$(jq -n -c --argjson pr "$pr_num" --arg result "$result" \
        '{pr: {number: $pr}, agent: {name: "qa_guardian", result: $result}}')

    log_event "review_completed" "info" "PR #$pr_num review: $result" "$extra"
}

log_agent_started() {
    local agent_name="$1"
    local pr_num="$2"
    local tab="${3:-}"

    local extra
    extra=$(jq -n -c --arg agent "$agent_name" --argjson pr "$pr_num" --argjson tab "${tab:-null}" \
        '{agent: {name: $agent, result: "pending"}, pr: {number: $pr}, worker: {tab: $tab}}')

    log_event "agent_started" "info" "Running $agent_name for PR #$pr_num" "$extra"
}

log_agent_completed() {
    local agent_name="$1"
    local pr_num="$2"
    local result="$3"

    local extra
    extra=$(jq -n -c --arg agent "$agent_name" --argjson pr "$pr_num" --arg result "$result" \
        '{agent: {name: $agent, result: $result}, pr: {number: $pr}}')

    log_event "agent_completed" "info" "$agent_name for PR #$pr_num: $result" "$extra"
}

# Worker lifecycle
log_worker_closed() {
    local tab="$1"
    local worker_name="${2:-}"

    local extra
    extra=$(jq -n -c --argjson tab "$tab" --arg name "$worker_name" \
        '{worker: {tab: $tab, name: (if $name == "" then null else $name end)}}')

    log_event "worker_closed" "info" "Tab $tab closed" "$extra"
}

# Project mode events
log_project_status_change() {
    local project_name="$1"
    local status="$2"
    local iteration="${3:-1}"

    local extra
    extra=$(jq -n -c --arg name "$project_name" --arg status "$status" --argjson iter "$iteration" \
        '{project: {name: $name, status: $status, iteration: $iter}}')

    log_event "project_status_change" "info" "Project $project_name status: $status" "$extra"
}

log_project_workers_complete() {
    local project_name="$1"

    local extra
    extra=$(jq -n -c --arg name "$project_name" \
        '{project: {name: $name, status: "all_merged"}}')

    log_event "project_workers_complete" "info" "All workers merged for project: $project_name" "$extra"
}

# Notifications
log_notification_sent() {
    local title="$1"
    local message="$2"

    local extra
    extra=$(jq -n -c --arg title "$title" --arg msg "$message" \
        '{metadata: {notification_title: $title, notification_message: $msg}}')

    log_event "notification_sent" "info" "Notification: $title" "$extra"
}

# Log rotation utility
rotate_logs() {
    local max_size="${1:-10485760}"  # 10MB default
    local max_files="${2:-5}"

    if [ -f "$JSON_LOG_FILE" ]; then
        local size
        size=$(stat -f%z "$JSON_LOG_FILE" 2>/dev/null || stat -c%s "$JSON_LOG_FILE" 2>/dev/null)

        if [ "$size" -gt "$max_size" ]; then
            for i in $(seq $((max_files - 1)) -1 1); do
                [ -f "${JSON_LOG_FILE}.$i" ] && mv "${JSON_LOG_FILE}.$i" "${JSON_LOG_FILE}.$((i + 1))"
            done
            mv "$JSON_LOG_FILE" "${JSON_LOG_FILE}.1"
            log_info "Log rotated: $JSON_LOG_FILE"
        fi
    fi
}

# Export functions for subshells
export -f log_event log_debug log_info log_warn log_error
export -f log_orchestrator_started log_orchestrator_stopped
export -f log_worker_state_change log_worker_initialized log_worker_nudged log_worker_closed
export -f log_pr_detected log_pr_ci_status log_pr_merged
export -f log_review_started log_review_completed
export -f log_agent_started log_agent_completed
export -f log_project_status_change log_project_workers_complete
export -f log_notification_sent rotate_logs should_log
export LOG_DIR JSON_LOG_FILE TEXT_LOG_FILE LOG_LEVEL
