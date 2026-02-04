#!/usr/bin/env bash
# Start multiple Claude workers in new iTerm tabs
# Usage: start-all-workers.sh worker1 worker2 worker3 ...
# Example: start-all-workers.sh privacy-policy terms-of-service legal-components

REPO_NAME="${REPO_NAME:-medicalbills}"
SCRIPT_DIR="$(dirname "$0")"

if [ $# -eq 0 ]; then
  echo "Usage: start-all-workers.sh worker1 worker2 worker3 ..."
  echo "Set REPO_NAME env var to change repo (default: medicalbills)"
  exit 1
fi

for worker in "$@"; do
  "$SCRIPT_DIR/start-worker.sh" "$worker" "$REPO_NAME"
  sleep 1  # Small delay between tabs
done

echo ""
echo "✓ Started $# workers. Give each Claude its task:"
echo '  "You are worker '\''<name>'\''. Read CLAUDE.md for your task. Enable auto-accept (Shift+Tab) and begin."'
