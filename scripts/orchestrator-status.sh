#!/usr/bin/env bash
# Show orchestrator status: PID, logs, and delivery pipeline state

PID_FILE="$HOME/.claude/orchestrator.pid"
LOG_FILE="$HOME/.claude/orchestrator.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$SCRIPT_DIR/../pipeline"

echo "=== Orchestrator Status ==="
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Status: RUNNING (PID: $PID)"
    else
        echo "Status: NOT RUNNING (stale PID)"
    fi
else
    echo "Status: NOT RUNNING"
fi

echo ""
echo "=== Delivery Pipeline ==="
if [[ -f "$PIPELINE_DIR/delivery-state.sh" ]]; then
    deliveries=$("$PIPELINE_DIR/delivery-state.sh" list 2>/dev/null || echo "[]")
    count=$(echo "$deliveries" | jq 'length' 2>/dev/null || echo 0)

    if [[ "$count" -gt 0 ]]; then
        echo "Active deliveries: $count"
        echo "$deliveries" | jq -r '.[] | "  \(.state)\t PR #\(.prNumber // "—")\t \(.branch)"' 2>/dev/null
    else
        echo "No active deliveries."
    fi
else
    echo "Pipeline not installed."
fi

echo ""
echo "=== Recent Logs ==="
if [[ -f "$LOG_FILE" ]]; then
    tail -20 "$LOG_FILE"
else
    echo "No logs."
fi
