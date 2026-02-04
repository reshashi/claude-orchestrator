#!/usr/bin/env bash
# Claude Code Orchestrator - Uninstall Script
#
# Usage: ./uninstall.sh

set -eo pipefail

# Run install.sh with uninstall flag
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/install.sh" --uninstall "$@"
