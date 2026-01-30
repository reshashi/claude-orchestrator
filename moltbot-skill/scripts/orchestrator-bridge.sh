#!/usr/bin/env bash
# orchestrator-bridge.sh
# Bridge script for Moltbot skill to interact with Claude Orchestrator
# Supports both CLI and HTTP API modes

set -euo pipefail

# Configuration
ORCHESTRATOR_PORT="${ORCHESTRATOR_PORT:-3001}"
ORCHESTRATOR_HOST="${ORCHESTRATOR_HOST:-localhost}"
ORCHESTRATOR_CLI="${ORCHESTRATOR_CLI:-claude-orchestrator}"
API_BASE="http://${ORCHESTRATOR_HOST}:${ORCHESTRATOR_PORT}/api"

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Check if API server is running
api_available() {
    curl -s --connect-timeout 1 "${API_BASE}/health" >/dev/null 2>&1
}

# Use API if available, otherwise fall back to CLI
use_api() {
    api_available
}

# Print error and exit
die() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Print success message
success() {
    echo -e "${GREEN}$1${NC}"
}

# Print info message
info() {
    echo -e "${BLUE}$1${NC}"
}

# Print warning message
warn() {
    echo -e "${YELLOW}$1${NC}"
}

# JSON helpers
json_get() {
    echo "$1" | jq -r "$2" 2>/dev/null || echo ""
}

# ===========================================
# COMMANDS
# ===========================================

cmd_spawn() {
    local name="${1:-}"
    local task="${2:-}"
    local repo="${3:-}"

    [[ -z "$name" ]] && die "Usage: orchestrator-bridge spawn <name> <task> [repo]"
    [[ -z "$task" ]] && die "Usage: orchestrator-bridge spawn <name> <task> [repo]"

    if use_api; then
        local payload
        if [[ -n "$repo" ]]; then
            payload=$(jq -n --arg name "$name" --arg task "$task" --arg repo "$repo" \
                '{name: $name, task: $task, repo: $repo}')
        else
            payload=$(jq -n --arg name "$name" --arg task "$task" \
                '{name: $name, task: $task}')
        fi

        local response
        response=$(curl -s -X POST "${API_BASE}/workers" \
            -H "Content-Type: application/json" \
            -d "$payload")

        local error
        error=$(json_get "$response" '.error // empty')
        if [[ -n "$error" ]]; then
            die "$error"
        fi

        local worker_id path branch pid
        worker_id=$(json_get "$response" '.id')
        path=$(json_get "$response" '.config.worktreePath')
        branch=$(json_get "$response" '.config.branchName')
        pid=$(json_get "$response" '.pid')

        success "Worker '${worker_id}' spawned!"
        echo "  Path: ${path}"
        echo "  Branch: ${branch}"
        echo "  PID: ${pid}"
        echo ""
        info "The worker is running in the background."
        info "Use 'orchestrator status ${worker_id}' to check progress."
    else
        local repo_flag=""
        [[ -n "$repo" ]] && repo_flag="--repo $repo"
        $ORCHESTRATOR_CLI spawn "$name" "$task" $repo_flag
    fi
}

cmd_list() {
    local all_flag="${1:-}"

    if use_api; then
        local endpoint="${API_BASE}/workers"
        [[ "$all_flag" == "--all" ]] && endpoint="${endpoint}?all=true"

        local response
        response=$(curl -s "$endpoint")

        local count
        count=$(echo "$response" | jq 'length')

        if [[ "$count" -eq 0 ]]; then
            echo "No workers found."
            return
        fi

        echo ""
        echo "Workers:"
        echo "────────────────────────────────────────────────────────────"

        echo "$response" | jq -r '.[] | "\(.state)\t\(.id)\t\(.prNumber // "-")\t\(.config.worktreePath)\t\(.config.task)"' | \
        while IFS=$'\t' read -r state id pr_num path task; do
            local emoji
            case "$state" in
                SPAWNING) emoji="⏳" ;;
                INITIALIZING) emoji="🔄" ;;
                WORKING) emoji="💻" ;;
                PR_OPEN) emoji="📬" ;;
                REVIEWING) emoji="🔍" ;;
                MERGING) emoji="🔀" ;;
                MERGED) emoji="✅" ;;
                ERROR) emoji="❌" ;;
                STOPPED) emoji="🛑" ;;
                *) emoji="❓" ;;
            esac

            local pr_info=""
            [[ "$pr_num" != "-" ]] && pr_info="PR #${pr_num}"

            printf "%s %-20s %-12s %s\n" "$emoji" "$id" "$state" "$pr_info"
            echo "   Path: ${path}"
            echo "   Task: ${task:0:60}..."
            echo ""
        done
    else
        local all_opt=""
        [[ "$all_flag" == "--all" ]] && all_opt="--all"
        $ORCHESTRATOR_CLI list $all_opt
    fi
}

cmd_status() {
    local worker_id="${1:-}"

    if use_api; then
        if [[ -n "$worker_id" ]]; then
            local response
            response=$(curl -s "${API_BASE}/workers/${worker_id}")

            local error
            error=$(json_get "$response" '.error // empty')
            if [[ -n "$error" ]]; then
                die "Worker '${worker_id}' not found."
            fi

            local state emoji description branch path task last_active pr_num pr_url review_status agents_run err
            state=$(json_get "$response" '.state')
            case "$state" in
                SPAWNING) emoji="⏳"; description="Process starting" ;;
                INITIALIZING) emoji="🔄"; description="Claude loading" ;;
                WORKING) emoji="💻"; description="Actively processing the task" ;;
                PR_OPEN) emoji="📬"; description="PR created, awaiting CI/review" ;;
                REVIEWING) emoji="🔍"; description="QA review in progress" ;;
                MERGING) emoji="🔀"; description="PR being merged" ;;
                MERGED) emoji="✅"; description="Complete" ;;
                ERROR) emoji="❌"; description="Something went wrong" ;;
                STOPPED) emoji="🛑"; description="Terminated" ;;
                *) emoji="❓"; description="Unknown state" ;;
            esac

            branch=$(json_get "$response" '.config.branchName')
            path=$(json_get "$response" '.config.worktreePath')
            task=$(json_get "$response" '.config.task')
            last_active=$(json_get "$response" '.lastActivity')
            pr_num=$(json_get "$response" '.prNumber // empty')
            pr_url=$(json_get "$response" '.prUrl // empty')
            review_status=$(json_get "$response" '.reviewStatus')
            agents_run=$(json_get "$response" '.agentsRun | join(", ")')
            err=$(json_get "$response" '.error // empty')

            echo ""
            echo "${emoji} Worker: ${worker_id}"
            echo "──────────────────────────────────────────────────"
            echo "State:       ${state}"
            echo "Description: ${description}"
            echo "Branch:      ${branch}"
            echo "Path:        ${path}"
            echo "Task:        ${task}"
            echo "Last Active: ${last_active}"

            [[ -n "$pr_num" ]] && echo "PR:          #${pr_num} - ${pr_url}"
            [[ "$review_status" != "none" ]] && echo "Review:      ${review_status}"
            [[ -n "$agents_run" ]] && echo "Agents Run:  ${agents_run}"
            [[ -n "$err" ]] && echo "Error:       ${err}"
        else
            # Summary
            local response
            response=$(curl -s "${API_BASE}/workers")

            local total working pr_open reviewing merged errors
            total=$(echo "$response" | jq 'length')
            working=$(echo "$response" | jq '[.[] | select(.state == "WORKING")] | length')
            pr_open=$(echo "$response" | jq '[.[] | select(.state == "PR_OPEN")] | length')
            reviewing=$(echo "$response" | jq '[.[] | select(.state == "REVIEWING")] | length')
            merged=$(echo "$response" | jq '[.[] | select(.state == "MERGED")] | length')
            errors=$(echo "$response" | jq '[.[] | select(.state == "ERROR")] | length')

            echo ""
            echo "Orchestrator Status"
            echo "────────────────────────────────────"
            echo "Total Workers: ${total}"
            echo "Working:       ${working}"
            echo "PR Open:       ${pr_open}"
            echo "Reviewing:     ${reviewing}"
            echo "Merged:        ${merged}"
            echo "Errors:        ${errors}"
        fi
    else
        $ORCHESTRATOR_CLI status $worker_id
    fi
}

cmd_read() {
    local worker_id="${1:-}"
    local lines="${2:-50}"

    [[ -z "$worker_id" ]] && die "Usage: orchestrator-bridge read <worker-id> [lines]"

    if use_api; then
        local response
        response=$(curl -s "${API_BASE}/workers/${worker_id}/output?lines=${lines}")

        local error
        error=$(json_get "$response" '.error // empty')
        if [[ -n "$error" ]]; then
            die "$error"
        fi

        echo "$response" | jq -r '.output[]' 2>/dev/null || echo "No output found."
    else
        $ORCHESTRATOR_CLI read "$worker_id" --lines "$lines"
    fi
}

cmd_send() {
    local worker_id="${1:-}"
    local message="${2:-}"

    [[ -z "$worker_id" ]] && die "Usage: orchestrator-bridge send <worker-id> <message>"
    [[ -z "$message" ]] && die "Usage: orchestrator-bridge send <worker-id> <message>"

    if use_api; then
        local payload
        payload=$(jq -n --arg msg "$message" '{message: $msg}')

        local response
        response=$(curl -s -X POST "${API_BASE}/workers/${worker_id}/send" \
            -H "Content-Type: application/json" \
            -d "$payload")

        local error
        error=$(json_get "$response" '.error // empty')
        if [[ -n "$error" ]]; then
            die "$error"
        fi

        success "Message sent to ${worker_id}"
    else
        $ORCHESTRATOR_CLI send "$worker_id" "$message"
    fi
}

cmd_stop() {
    local worker_id="${1:-}"

    [[ -z "$worker_id" ]] && die "Usage: orchestrator-bridge stop <worker-id>"

    if use_api; then
        local response
        response=$(curl -s -X POST "${API_BASE}/workers/${worker_id}/stop")

        local error
        error=$(json_get "$response" '.error // empty')
        if [[ -n "$error" ]]; then
            die "$error"
        fi

        success "Worker ${worker_id} stopped"
    else
        $ORCHESTRATOR_CLI stop "$worker_id"
    fi
}

cmd_merge() {
    local worker_id="${1:-}"

    [[ -z "$worker_id" ]] && die "Usage: orchestrator-bridge merge <worker-id>"

    if use_api; then
        local response
        response=$(curl -s -X POST "${API_BASE}/workers/${worker_id}/merge")

        local error
        error=$(json_get "$response" '.error // empty')
        if [[ -n "$error" ]]; then
            die "$error"
        fi

        local merged
        merged=$(json_get "$response" '.merged')
        if [[ "$merged" == "true" ]]; then
            success "PR for ${worker_id} merged successfully"
        else
            die "Failed to merge PR for ${worker_id}"
        fi
    else
        $ORCHESTRATOR_CLI merge "$worker_id"
    fi
}

cmd_cleanup() {
    local worker_id="${1:-}"

    if use_api; then
        if [[ -n "$worker_id" ]]; then
            local response
            response=$(curl -s -X DELETE "${API_BASE}/workers/${worker_id}")

            local error
            error=$(json_get "$response" '.error // empty')
            if [[ -n "$error" ]]; then
                die "$error"
            fi

            success "Cleaned up ${worker_id}"
        else
            local response
            response=$(curl -s -X POST "${API_BASE}/cleanup")

            local cleaned
            cleaned=$(json_get "$response" '.cleaned | length')
            success "Cleaned up ${cleaned} workers"
        fi
    else
        $ORCHESTRATOR_CLI cleanup $worker_id
    fi
}

cmd_project() {
    local description="${1:-}"

    [[ -z "$description" ]] && die "Usage: orchestrator-bridge project <description>"

    if use_api; then
        local payload
        payload=$(jq -n --arg desc "$description" '{description: $desc}')

        local response
        response=$(curl -s -X POST "${API_BASE}/project" \
            -H "Content-Type: application/json" \
            -d "$payload")

        local error
        error=$(json_get "$response" '.error // empty')
        if [[ -n "$error" ]]; then
            die "$error"
        fi

        local project_id
        project_id=$(json_get "$response" '.projectId')

        success "Project started: ${project_id}"
        info "Use 'orchestrator status' to monitor progress."
    else
        warn "Project mode requires the API server to be running."
        warn "Start it with: orchestrator serve"
        exit 1
    fi
}

cmd_health() {
    if api_available; then
        local response
        response=$(curl -s "${API_BASE}/health")
        echo "$response" | jq .
        success "API server is healthy"
    else
        warn "API server is not running"
        info "Start it with: orchestrator serve"
    fi
}

cmd_help() {
    cat <<EOF
Claude Orchestrator Bridge

Usage: orchestrator-bridge <command> [options]

Commands:
  spawn <name> <task> [repo]   Create a new worker
  list [--all]                 List workers
  status [worker-id]           Get worker status
  read <worker-id> [lines]     Read worker output
  send <worker-id> <message>   Send message to worker
  stop <worker-id>             Stop a worker
  merge <worker-id>            Merge worker's PR
  cleanup [worker-id]          Clean up workers
  project <description>        Start autonomous project
  health                       Check API server status
  help                         Show this help

Environment Variables:
  ORCHESTRATOR_PORT   API server port (default: 3001)
  ORCHESTRATOR_HOST   API server host (default: localhost)
  ORCHESTRATOR_CLI    Path to CLI binary (default: claude-orchestrator)

Examples:
  orchestrator-bridge spawn auth-api "Implement JWT authentication"
  orchestrator-bridge list
  orchestrator-bridge status auth-api
  orchestrator-bridge send auth-api "Also add password reset"
  orchestrator-bridge merge auth-api

EOF
}

# ===========================================
# MAIN
# ===========================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        spawn)
            cmd_spawn "$@"
            ;;
        list|ls)
            cmd_list "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        read)
            cmd_read "$@"
            ;;
        send)
            cmd_send "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        merge)
            cmd_merge "$@"
            ;;
        cleanup)
            cmd_cleanup "$@"
            ;;
        project)
            cmd_project "$@"
            ;;
        health)
            cmd_health
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            die "Unknown command: ${command}. Use 'orchestrator-bridge help' for usage."
            ;;
    esac
}

main "$@"
