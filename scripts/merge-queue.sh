#!/usr/bin/env bash
# Merge queue with auto-rebase for serialized PR merges
# Prevents concurrent merges from causing cascading conflicts.
#
# Usage:
#   merge-queue.sh process <pr-number> [--method squash|merge|rebase] [--delete-branch]
#   merge-queue.sh status

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$SCRIPT_DIR/../pipeline"
CONFIG_DIR="$SCRIPT_DIR/../config"

LOCK_BASE="${LOCK_BASE:-$HOME/.claude-orchestrator/locks}"
MERGE_LOCK_NAME="merge-queue"

# Load config
MERGE_QUEUE_ENABLED=true
LOCK_TIMEOUT=120
AUTO_REBASE=true
CI_WAIT_SECONDS=300
CONFLICT_ACTION="notify"

_load_merge_queue_config() {
    local config_file="${ORCHESTRATOR_CONFIG:-$CONFIG_DIR/orchestrator.yaml}"
    if [[ -f "$config_file" ]]; then
        local val
        val=$(grep 'lock_timeout_seconds:' "$config_file" 2>/dev/null | awk '{print $2}')
        [[ -n "$val" ]] && LOCK_TIMEOUT="$val"
        val=$(grep 'auto_rebase:' "$config_file" 2>/dev/null | awk '{print $2}')
        [[ "$val" == "false" ]] && AUTO_REBASE=false
        val=$(grep 'ci_wait_after_rebase_seconds:' "$config_file" 2>/dev/null | awk '{print $2}')
        [[ -n "$val" ]] && CI_WAIT_SECONDS="$val"
        val=$(grep 'conflict_action:' "$config_file" 2>/dev/null | awk '{print $2}')
        [[ -n "$val" ]] && CONFLICT_ACTION="$val"
        # Check if merge queue is explicitly disabled
        val=$(grep -A1 'merge_queue:' "$config_file" 2>/dev/null | grep 'enabled:' | awk '{print $2}')
        [[ "$val" == "false" ]] && MERGE_QUEUE_ENABLED=false
    fi
    return 0
}
_load_merge_queue_config

# Source pr-manager for merge and update-branch functions
if [[ -f "$PIPELINE_DIR/pr-manager.sh" ]]; then
    # shellcheck source=../pipeline/pr-manager.sh
    source "$PIPELINE_DIR/pr-manager.sh"
fi

# Source ci-monitor for CI status checking
if [[ -f "$PIPELINE_DIR/ci-monitor.sh" ]]; then
    # shellcheck source=../pipeline/ci-monitor.sh
    source "$PIPELINE_DIR/ci-monitor.sh"
fi

# ============================================================
# LOCKING (same portable pattern as project-state.sh)
# ============================================================

_acquire_merge_lock() {
    local timeout="${1:-$LOCK_TIMEOUT}"
    local lock_dir="${LOCK_BASE}/${MERGE_LOCK_NAME}.lock"
    local deadline=$(( $(date +%s) + timeout ))

    mkdir -p "$LOCK_BASE"

    while ! mkdir "$lock_dir" 2>/dev/null; do
        # Stale lock check
        local pid
        pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            rm -rf "$lock_dir"
            continue
        fi

        if [[ $(date +%s) -ge $deadline ]]; then
            echo "Error: Timed out waiting for merge queue lock (${timeout}s)" >&2
            return 1
        fi
        sleep 2
    done

    echo $$ > "$lock_dir/pid"
}

_release_merge_lock() {
    local lock_dir="${LOCK_BASE}/${MERGE_LOCK_NAME}.lock"
    rm -rf "$lock_dir"
}

# ============================================================
# MERGE QUEUE FUNCTIONS
# ============================================================

# Try to update the PR branch via GitHub API, fallback to local rebase
_rebase_pr_branch() {
    local pr_number="$1"

    # Try GitHub API first (cleanest approach)
    local api_result
    api_result=$(pr_update_branch "$pr_number" 2>&1) || true

    if echo "$api_result" | grep -q '"message"'; then
        local message
        message=$(echo "$api_result" | jq -r '.message // empty' 2>/dev/null)

        if [[ "$message" == *"merge conflict"* || "$message" == *"Merge conflict"* ]]; then
            echo "CONFLICT" >&2
            return 2
        fi

        # If the message indicates success or already up to date
        if [[ "$message" == *"Updating"* || "$message" == *"already up-to-date"* ]]; then
            return 0
        fi
    fi

    # Check if the API call succeeded (HTTP 202)
    if echo "$api_result" | grep -q '"url"'; then
        return 0
    fi

    # Fallback: local rebase in temp worktree
    _local_rebase_fallback "$pr_number"
}

_local_rebase_fallback() {
    local pr_number="$1"
    local branch
    branch=$(gh pr view "$pr_number" --json headRefName -q '.headRefName' 2>/dev/null)

    if [[ -z "$branch" ]]; then
        echo "Error: Cannot determine branch for PR #${pr_number}" >&2
        return 1
    fi

    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    local repo_name
    repo_name=$(basename "$repo_root")

    local tmp_worktree="$HOME/.worktrees/${repo_name}/.merge-queue-${pr_number}"

    # Create temp worktree
    git worktree add "$tmp_worktree" "$branch" 2>/dev/null || {
        git worktree remove "$tmp_worktree" --force 2>/dev/null || true
        git worktree add "$tmp_worktree" "$branch" 2>/dev/null
    }

    # Fetch and rebase
    git -C "$tmp_worktree" fetch origin main 2>/dev/null

    if ! git -C "$tmp_worktree" rebase origin/main 2>/dev/null; then
        git -C "$tmp_worktree" rebase --abort 2>/dev/null || true
        git worktree remove "$tmp_worktree" --force 2>/dev/null || true
        echo "CONFLICT: Cannot rebase $branch onto main" >&2
        return 2
    fi

    # Force-push with lease (safe)
    git -C "$tmp_worktree" push --force-with-lease origin "$branch" 2>/dev/null

    # Cleanup temp worktree
    git worktree remove "$tmp_worktree" --force 2>/dev/null || true

    return 0
}

# Wait for CI to pass after rebase
_wait_for_ci() {
    local pr_number="$1"
    local max_wait="${2:-$CI_WAIT_SECONDS}"
    local deadline=$(( $(date +%s) + max_wait ))
    local poll_interval=15

    echo "Waiting for CI on PR #${pr_number} (max ${max_wait}s)..."

    while [[ $(date +%s) -lt $deadline ]]; do
        local ci_state
        ci_state=$(ci_status "$pr_number" 2>/dev/null || echo "unknown")

        case "$ci_state" in
            passed)
                echo "CI passed for PR #${pr_number}"
                return 0
                ;;
            failed)
                echo "CI failed for PR #${pr_number}" >&2
                return 1
                ;;
            *)
                sleep "$poll_interval"
                ;;
        esac
    done

    echo "CI timed out for PR #${pr_number} after ${max_wait}s" >&2
    return 1
}

# Main merge queue entry point
# Returns: 0=success, 1=error, 2=conflict
merge_queue_process() {
    local pr_number="" method="squash" delete_branch=false

    if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        pr_number="$1"; shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --method) method="$2"; shift 2 ;;
            --delete-branch) delete_branch=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$pr_number" ]]; then
        echo "Usage: merge_queue_process <pr-number> [--method squash|merge|rebase] [--delete-branch]" >&2
        return 1
    fi

    if [[ "$MERGE_QUEUE_ENABLED" != true ]]; then
        # Fallback to direct merge when queue is disabled
        local merge_args=("$pr_number" "--method" "$method")
        [[ "$delete_branch" == true ]] && merge_args+=(--delete-branch)
        pr_merge "${merge_args[@]}"
        return $?
    fi

    echo "Merge queue: processing PR #${pr_number}..."

    # Step 1: Acquire the merge lock
    if ! _acquire_merge_lock; then
        echo "Error: Could not acquire merge queue lock" >&2
        return 1
    fi

    # Ensure we release the lock on exit
    trap '_release_merge_lock' RETURN

    # Step 2: Auto-rebase if enabled
    if [[ "$AUTO_REBASE" == true ]]; then
        echo "Rebasing PR #${pr_number} onto latest main..."
        local rebase_exit=0
        _rebase_pr_branch "$pr_number" || rebase_exit=$?

        if [[ $rebase_exit -eq 2 ]]; then
            # Conflict
            echo "CONFLICT: PR #${pr_number} cannot be rebased" >&2
            if [[ "$CONFLICT_ACTION" == "notify" ]]; then
                # List conflicting files if possible
                local files
                files=$(gh pr diff "$pr_number" --name-only 2>/dev/null | head -20)
                echo "Files in PR: $files" >&2
            fi
            return 2
        elif [[ $rebase_exit -ne 0 ]]; then
            echo "Error: Rebase failed for PR #${pr_number}" >&2
            return 1
        fi

        # Step 3: Wait for CI after rebase
        if ! _wait_for_ci "$pr_number" "$CI_WAIT_SECONDS"; then
            echo "Error: CI did not pass after rebase for PR #${pr_number}" >&2
            return 1
        fi
    fi

    # Step 4: Merge
    local merge_args=("$pr_number" "--method" "$method")
    if [[ "$delete_branch" == true ]]; then
        merge_args+=(--delete-branch)
    fi

    if pr_merge "${merge_args[@]}" 2>/dev/null; then
        echo "PR #${pr_number} merged successfully via merge queue"
        return 0
    else
        echo "Error: Merge failed for PR #${pr_number}" >&2
        return 1
    fi
}

# Show merge queue status
merge_queue_status() {
    local lock_dir="${LOCK_BASE}/${MERGE_LOCK_NAME}.lock"

    if [[ -d "$lock_dir" ]]; then
        local pid
        pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "unknown")
        echo "Merge queue: LOCKED (PID: $pid)"
    else
        echo "Merge queue: idle"
    fi

    echo "Config: auto_rebase=$AUTO_REBASE, lock_timeout=${LOCK_TIMEOUT}s, ci_wait=${CI_WAIT_SECONDS}s, conflict_action=$CONFLICT_ACTION"
}

# ============================================================
# CLI DISPATCH
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        process) shift; merge_queue_process "$@" ;;
        status)  shift; merge_queue_status "$@" ;;
        *)
            echo "Usage: merge-queue.sh {process|status} [args...]" >&2
            exit 1
            ;;
    esac
fi
