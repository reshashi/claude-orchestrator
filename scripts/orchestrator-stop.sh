#!/bin/bash
PID_FILE="$HOME/.claude/orchestrator.pid"
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Stopping orchestrator (PID: $PID)..."
        kill "$PID"
        rm -f "$PID_FILE"
        echo "Stopped."
    else
        echo "Not running (stale PID)."
        rm -f "$PID_FILE"
    fi
else
    echo "Not running."
fi
