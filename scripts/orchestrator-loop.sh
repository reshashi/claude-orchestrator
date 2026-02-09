#!/usr/bin/env bash
# Claude Orchestrator — Delivery Pipeline Loop
# Watches for open PRs and runs them through CI → quality gates → merge.
# No iTerm/AppleScript dependencies — works on any platform with gh CLI.
#
# Usage:
#   orchestrator-loop.sh              # foreground
#   orchestrator-loop.sh &            # background
#   POLL_INTERVAL=10 orchestrator-loop.sh

POLL_INTERVAL="${POLL_INTERVAL:-30}"
LOG_FILE="${LOG_FILE:-$HOME/.claude/orchestrator.log}"
PID_FILE="$HOME/.claude/orchestrator.pid"
PROJECT_STATE_FILE="$HOME/.claude/project-state.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$SCRIPT_DIR/../pipeline"

# Source structured logging
if [[ -f "$SCRIPT_DIR/logging.sh" ]]; then
    # shellcheck source=./logging.sh
    source "$SCRIPT_DIR/logging.sh"
    STRUCTURED_LOGGING=true
else
    STRUCTURED_LOGGING=false
fi

# Source pipeline scripts
# shellcheck source=../pipeline/delivery-state.sh
source "$PIPELINE_DIR/delivery-state.sh"
# shellcheck source=../pipeline/ci-monitor.sh
source "$PIPELINE_DIR/ci-monitor.sh"
# shellcheck source=../pipeline/gate-runner.sh
source "$PIPELINE_DIR/gate-runner.sh"
# shellcheck source=../pipeline/pr-manager.sh
source "$PIPELINE_DIR/pr-manager.sh"
# shellcheck source=./mode-detect.sh
source "$SCRIPT_DIR/mode-detect.sh"

mkdir -p "$(dirname "$LOG_FILE")"

# ============================================================
# LOGGING
# ============================================================

log() {
    if [[ "$STRUCTURED_LOGGING" == true ]]; then
        log_info "$*"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    fi
}

# ============================================================
# PROJECT MODE FUNCTIONS
# ============================================================

is_project_mode() {
    [[ -f "$PROJECT_STATE_FILE" ]]
}

get_project_status() {
    jq -r '.status' "$PROJECT_STATE_FILE" 2>/dev/null
}

get_project_name() {
    jq -r '.project_name' "$PROJECT_STATE_FILE" 2>/dev/null
}

update_project_status() {
    local new_status="$1"
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg status "$new_status" '.status = $status' "$PROJECT_STATE_FILE" > "$tmp_file" \
        && mv "$tmp_file" "$PROJECT_STATE_FILE"

    if [[ "$STRUCTURED_LOGGING" == true ]]; then
        local project_name
        project_name=$(get_project_name)
        log_project_status_change "$project_name" "$new_status"
    else
        log "Project status updated: $new_status"
    fi
}

check_all_project_workers_complete() {
    if ! is_project_mode; then return 1; fi

    local active
    active=$(jq '[.workers[] | select(.status != "merged")] | length' "$PROJECT_STATE_FILE" 2>/dev/null)

    if [[ -z "$active" || "$active" -eq 0 ]]; then
        return 0
    fi
    return 1
}

notify_human() {
    local title="$1"
    local message="$2"

    # Terminal bell
    echo -e "\a"

    # macOS notification (best-effort)
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || true

    if [[ "$STRUCTURED_LOGGING" == true ]]; then
        log_notification_sent "$title" "$message"
    else
        log "NOTIFICATION: $title - $message"
    fi
}

# ============================================================
# PID MANAGEMENT
# ============================================================

if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "Orchestrator already running (PID: $OLD_PID)"
        exit 1
    fi
fi

echo $$ > "$PID_FILE"
if [[ "$STRUCTURED_LOGGING" == true ]]; then
    log_orchestrator_started "$$"
else
    log "Orchestrator started (PID: $$)"
fi

cleanup() {
    if [[ "$STRUCTURED_LOGGING" == true ]]; then
        log_orchestrator_stopped
    else
        log "Orchestrator stopping..."
    fi
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM

# ============================================================
# THREE-TIER MEMORY LOADING
# ============================================================

log "Loading orchestrator memory..."

SEED_DIR="$HOME/.claude/orchestrator/seed"
USER_DIR="$HOME/.claude/orchestrator/user"
PROJECT_DIR="$PWD/.claude/memory"

if [[ -f "$SEED_DIR/orchestrator-onboarding.md" ]]; then
    log "Loaded seed memory (orchestrator training)"
fi

if [[ -f "$USER_DIR/preferences.json" ]]; then
    log "Loaded user preferences"
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
    log "Initializing project memory for first time..."
    "$HOME/.claude/scripts/init-project-memory.sh" "$PWD" 2>/dev/null || true
fi

if [[ -d "$PROJECT_DIR/orchestrator" ]]; then
    log "Loaded project orchestrator memory"
fi

log "Three-tier memory loaded"

# ============================================================
# LOAD MERGE SETTINGS
# ============================================================

MERGE_METHOD="squash"
DELETE_BRANCH_ON_MERGE=true

_load_loop_settings() {
    local gates_file="${GATES_CONFIG:-$HOME/.claude-orchestrator/config/gates.yaml}"
    if [[ ! -f "$gates_file" ]]; then
        gates_file="$PIPELINE_DIR/../config/gates.yaml"
    fi
    if [[ -f "$gates_file" ]]; then
        local val
        val=$(grep 'merge_method:' "$gates_file" 2>/dev/null | awk '{print $2}')
        [[ -n "$val" ]] && MERGE_METHOD="$val"
        val=$(grep 'delete_branch_on_merge:' "$gates_file" 2>/dev/null | awk '{print $2}')
        [[ "$val" == "false" ]] && DELETE_BRANCH_ON_MERGE=false
    fi
    return 0
}
_load_loop_settings

# ============================================================
# AUTO-DETECT REPO
# ============================================================

REPO_FULL=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
if [[ -z "$REPO_FULL" ]]; then
    log "Warning: Could not detect repository. Ensure you're in a git repo with a GitHub remote."
fi

# ============================================================
# MAIN DELIVERY LOOP
# ============================================================

log "Starting delivery pipeline loop (polling every ${POLL_INTERVAL}s)"

while true; do
    # Find all open PRs in this repo
    OPEN_PRS=$(gh pr list --state open --json number,headRefName \
        --jq '.[] | "\(.number)|\(.headRefName)"' 2>/dev/null || echo "")

    for PR_LINE in $OPEN_PRS; do
        PR_NUM="${PR_LINE%%|*}"
        BRANCH="${PR_LINE#*|}"

        [[ -z "$PR_NUM" || -z "$BRANCH" ]] && continue

        # Skip if already in terminal state
        DELIVERY_STATE=$(delivery_get "$BRANCH" 2>/dev/null | jq -r '.state' 2>/dev/null || echo "")
        [[ "$DELIVERY_STATE" == "MERGED" ]] && continue

        # Initialize delivery tracking if new
        if [[ -z "$DELIVERY_STATE" ]]; then
            delivery_init "$BRANCH" "$BRANCH" >/dev/null 2>&1 || true
            delivery_set_pr "$BRANCH" "$PR_NUM" >/dev/null 2>&1 || true
            delivery_transition "$BRANCH" "PR_CREATING" >/dev/null 2>&1 || true
            delivery_transition "$BRANCH" "CI_RUNNING" >/dev/null 2>&1 || true
            DELIVERY_STATE="CI_RUNNING"
            log "Tracking new PR #${PR_NUM} (branch: ${BRANCH})"
        fi

        # Check CI
        CI=$(ci_status "$PR_NUM" 2>/dev/null || echo "unknown")
        case "$CI" in
            passed)
                if [[ "$DELIVERY_STATE" != "REVIEWING" && "$DELIVERY_STATE" != "APPROVED" && "$DELIVERY_STATE" != "MERGING" ]]; then
                    delivery_transition "$BRANCH" "REVIEWING" 2>/dev/null || true
                    log "PR #${PR_NUM} CI passed, running quality gates..."

                    if run_gates "$PR_NUM" "$BRANCH" 2>/dev/null; then
                        delivery_transition "$BRANCH" "APPROVED" 2>/dev/null || true
                        delivery_transition "$BRANCH" "MERGING" 2>/dev/null || true

                        MERGE_ARGS=("$PR_NUM" "--method" "$MERGE_METHOD")
                        if [[ "$DELETE_BRANCH_ON_MERGE" == true ]]; then
                            MERGE_ARGS+=(--delete-branch)
                        fi

                        if pr_merge "${MERGE_ARGS[@]}" 2>/dev/null; then
                            delivery_transition "$BRANCH" "MERGED" 2>/dev/null || true
                            log "PR #${PR_NUM} merged successfully"

                            if [[ "$STRUCTURED_LOGGING" == true ]]; then
                                log_pr_merged "$PR_NUM"
                            fi
                        else
                            delivery_transition "$BRANCH" "BLOCKED" 2>/dev/null || true
                            log "PR #${PR_NUM} merge failed"
                        fi
                    else
                        delivery_transition "$BRANCH" "BLOCKED" 2>/dev/null || true
                        log "PR #${PR_NUM} blocked by quality gates"
                    fi
                fi
                ;;
            failed)
                if [[ "$DELIVERY_STATE" != "BLOCKED" ]]; then
                    delivery_transition "$BRANCH" "BLOCKED" 2>/dev/null || true
                    log "PR #${PR_NUM} CI failed"
                fi
                ;;
            pending|unknown)
                log "PR #${PR_NUM} CI: ${CI}"
                ;;
        esac
    done

    # ============================================================
    # PROJECT MODE: Check if all workers are complete
    # ============================================================
    if is_project_mode; then
        PROJECT_STATUS=$(get_project_status)

        if [[ "$PROJECT_STATUS" == "workers_active" ]]; then
            if check_all_project_workers_complete; then
                PROJECT_NAME=$(get_project_name)
                if [[ "$STRUCTURED_LOGGING" == true ]]; then
                    log_project_workers_complete "$PROJECT_NAME"
                else
                    log "PROJECT MODE: All workers have merged for project: $PROJECT_NAME"
                fi
                update_project_status "all_merged"
                notify_human "Project Complete" "All workers merged for: $PROJECT_NAME"
                log "Project $PROJECT_NAME complete — notified human"
            fi
        fi
    fi

    sleep "$POLL_INTERVAL"
done
