#!/bin/bash
PID_FILE="$HOME/.claude/orchestrator.pid"
LOG_FILE="$HOME/.claude/orchestrator.log"
echo "=== Orchestrator Status ==="
if [ -f "$PID_FILE" ]; then
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
echo "=== Recent Logs ==="
[ -f "$LOG_FILE" ] && tail -20 "$LOG_FILE" || echo "No logs."
