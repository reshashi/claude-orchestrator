#!/usr/bin/env bash
# Per-project state management with file locking
# Supports concurrent /project sessions with isolated state files.
#
# Usage:
#   project-state.sh init <project-id>
#   project-state.sh get <project-id>
#   project-state.sh update <project-id> <jq-filter>
#   project-state.sh list [--status <status>]
#   project-state.sh cleanup <project-id>
#   project-state.sh migrate-legacy

set -eo pipefail

PROJECT_STATE_BASE="${PROJECT_STATE_BASE:-$HOME/.claude/projects}"
LOCK_BASE="${LOCK_BASE:-$HOME/.claude-orchestrator/locks}"

# ============================================================
# LOCKING (portable, macOS-compatible using mkdir)
# ============================================================

_acquire_lock() {
    local name="$1"
    local timeout="${2:-30}"
    local lock_dir="${LOCK_BASE}/${name}.lock"
    local deadline=$(( $(date +%s) + timeout ))

    mkdir -p "$LOCK_BASE"

    while ! mkdir "$lock_dir" 2>/dev/null; do
        # Stale lock check: if PID is dead, remove lock
        local pid
        pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            rm -rf "$lock_dir"
            continue
        fi

        if [[ $(date +%s) -ge $deadline ]]; then
            echo "Error: Timed out acquiring lock '$name'" >&2
            return 1
        fi
        sleep 1
    done

    echo $$ > "$lock_dir/pid"
}

_release_lock() {
    local name="$1"
    local lock_dir="${LOCK_BASE}/${name}.lock"
    rm -rf "$lock_dir"
}

# ============================================================
# PROJECT STATE FUNCTIONS
# ============================================================

project_init() {
    local project_id="$1"
    if [[ -z "$project_id" ]]; then
        echo "Usage: project_init <project-id>" >&2
        return 1
    fi

    local state_dir="${PROJECT_STATE_BASE}/${project_id}"
    local state_file="${state_dir}/state.json"

    mkdir -p "$state_dir"

    if [[ -f "$state_file" ]]; then
        echo "Project '$project_id' already exists" >&2
        return 1
    fi

    cat > "$state_file" << JSONEOF
{
  "project_id": "${project_id}",
  "project_name": "",
  "prd_path": "",
  "worktree_path": "",
  "branch": "",
  "status": "initializing",
  "iteration": 1,
  "max_iterations": 3,
  "is_simple": false,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "completed_at": null,
  "workers": [],
  "feedback_history": []
}
JSONEOF

    echo "$state_file"
}

project_get() {
    local project_id="$1"
    if [[ -z "$project_id" ]]; then
        echo "Usage: project_get <project-id>" >&2
        return 1
    fi

    local state_file="${PROJECT_STATE_BASE}/${project_id}/state.json"

    if [[ ! -f "$state_file" ]]; then
        echo "No project found: $project_id" >&2
        return 1
    fi

    cat "$state_file"
}

project_update() {
    local project_id="$1"
    local jq_filter="$2"

    if [[ -z "$project_id" || -z "$jq_filter" ]]; then
        echo "Usage: project_update <project-id> <jq-filter>" >&2
        return 1
    fi

    local state_file="${PROJECT_STATE_BASE}/${project_id}/state.json"

    if [[ ! -f "$state_file" ]]; then
        echo "No project found: $project_id" >&2
        return 1
    fi

    _acquire_lock "project-${project_id}"

    local tmp_file
    tmp_file=$(mktemp)
    if jq "$jq_filter" "$state_file" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$state_file"
    else
        rm -f "$tmp_file"
        _release_lock "project-${project_id}"
        echo "Error: Invalid jq filter" >&2
        return 1
    fi

    _release_lock "project-${project_id}"
    cat "$state_file"
}

project_list() {
    local filter_status=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) filter_status="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ ! -d "$PROJECT_STATE_BASE" ]]; then
        echo "[]"
        return 0
    fi

    local results="[]"

    for state_file in "$PROJECT_STATE_BASE"/*/state.json; do
        [[ -f "$state_file" ]] || continue

        if [[ -n "$filter_status" ]]; then
            local file_status
            file_status=$(jq -r '.status // empty' "$state_file" 2>/dev/null)
            [[ "$file_status" != "$filter_status" ]] && continue
        fi

        results=$(echo "$results" | jq --slurpfile entry "$state_file" '. + $entry')
    done

    echo "$results" | jq '.'
}

project_cleanup() {
    local project_id="$1"
    if [[ -z "$project_id" ]]; then
        echo "Usage: project_cleanup <project-id>" >&2
        return 1
    fi

    local state_file="${PROJECT_STATE_BASE}/${project_id}/state.json"

    if [[ ! -f "$state_file" ]]; then
        echo "No project found: $project_id" >&2
        return 1
    fi

    # Read worktree path and branch before cleanup
    local worktree_path branch
    worktree_path=$(jq -r '.worktree_path // empty' "$state_file" 2>/dev/null)
    branch=$(jq -r '.branch // empty' "$state_file" 2>/dev/null)

    # Remove git worktree if it exists
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
        git worktree remove "$worktree_path" --force 2>/dev/null || true
    fi

    # Delete branch if it exists
    if [[ -n "$branch" ]]; then
        git branch -D "$branch" 2>/dev/null || true
    fi

    # Remove state directory
    rm -rf "${PROJECT_STATE_BASE:?}/${project_id:?}"

    # Release any stale locks
    _release_lock "project-${project_id}" 2>/dev/null || true

    echo "Cleaned up project: $project_id"
}

project_migrate_legacy() {
    local legacy_file="$HOME/.claude/project-state.json"

    if [[ ! -f "$legacy_file" ]]; then
        echo "No legacy project-state.json found" >&2
        return 0
    fi

    local project_name
    project_name=$(jq -r '.project_name // "legacy"' "$legacy_file" 2>/dev/null)
    local project_id="${project_name}-legacy"
    local state_dir="${PROJECT_STATE_BASE}/${project_id}"

    # Don't migrate if already done
    if [[ -f "${state_dir}/state.json" ]]; then
        echo "Already migrated: $project_id"
        return 0
    fi

    mkdir -p "$state_dir"

    # Copy legacy state and add new fields
    jq --arg id "$project_id" --arg wt "" --arg br "" \
        '. + {project_id: $id, worktree_path: $wt, branch: $br, workers: (.workers // [])}' \
        "$legacy_file" > "${state_dir}/state.json"

    # Rename legacy file to indicate migration
    mv "$legacy_file" "${legacy_file}.migrated"

    echo "Migrated legacy state to: $state_dir"
}

# ============================================================
# CLI DISPATCH
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        init)           shift; project_init "$@" ;;
        get)            shift; project_get "$@" ;;
        update)         shift; project_update "$@" ;;
        list)           shift; project_list "$@" ;;
        cleanup)        shift; project_cleanup "$@" ;;
        migrate-legacy) shift; project_migrate_legacy "$@" ;;
        *)
            echo "Usage: project-state.sh {init|get|update|list|cleanup|migrate-legacy} [args...]" >&2
            exit 1
            ;;
    esac
fi
