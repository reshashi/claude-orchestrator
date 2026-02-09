#!/usr/bin/env bash
# Mode detection utility for claude-orchestrator
# Detects whether Agent Teams experimental feature is available.
#
# Usage: source this file, then check $ORCHESTRATOR_MODE
#   source "$(dirname "${BASH_SOURCE[0]}")/mode-detect.sh"
#   if is_agent_teams; then ...

# shellcheck disable=SC2034

# Allow override via CLI flag (parsed by caller)
if [[ -n "${ORCHESTRATOR_MODE:-}" ]]; then
    # Already set externally, respect it
    :
elif [[ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]]; then
    ORCHESTRATOR_MODE="agent-teams"
else
    ORCHESTRATOR_MODE="pipeline"
fi

export ORCHESTRATOR_MODE

# Helper: check if running in agent-teams mode
is_agent_teams() {
    [[ "$ORCHESTRATOR_MODE" == "agent-teams" ]]
}
