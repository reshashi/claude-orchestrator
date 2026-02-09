#!/usr/bin/env bash
# Orchestrator utilities for delivery pipeline management
# Source this or use individual functions / run as CLI

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$SCRIPT_DIR/../pipeline"

# Source pipeline scripts for function access
# shellcheck source=../pipeline/delivery-state.sh
source "$PIPELINE_DIR/delivery-state.sh"
# shellcheck source=../pipeline/pr-manager.sh
source "$PIPELINE_DIR/pr-manager.sh"
# shellcheck source=../pipeline/run.sh
source "$PIPELINE_DIR/run.sh"

# List active deliveries
delivery_list_pretty() {
    local deliveries
    deliveries=$(delivery_list 2>/dev/null)

    if [[ -z "$deliveries" || "$deliveries" == "[]" ]]; then
        echo "No active deliveries."
        return 0
    fi

    echo "Active Deliveries:"
    echo "$deliveries" | jq -r '.[] | "  PR #\(.prNumber // "—") | \(.branch) | \(.state) | \(.updatedAt)"'
}

# List open PRs (thin wrapper)
prs_list() {
    gh pr list --state open 2>/dev/null
}

# Run delivery pipeline for a branch
deliver() {
    pipeline_run "$@"
}

# Show command help
show_help() {
    echo "Orchestrator Commands:"
    echo "  delivery_list_pretty  - Show active deliveries"
    echo "  prs_list              - List open PRs"
    echo "  deliver <branch>      - Run delivery pipeline for a branch"
    echo "  pipeline_status <id>  - Show delivery detail for a task"
    echo "  pipeline_resume <id>  - Resume a blocked/interrupted delivery"
}

# If sourced, export functions; if run directly, execute command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        deliveries) delivery_list_pretty ;;
        prs) prs_list ;;
        deliver) shift; deliver "$@" ;;
        status) shift; pipeline_status "$@" ;;
        resume) shift; pipeline_resume "$@" ;;
        *) show_help ;;
    esac
fi
