#!/usr/bin/env bash
# Start the observability dashboard
# Usage: ./start-dashboard.sh [port]

set -e

DASHBOARD_PORT="${1:-3001}"
METRICS_PORT="${2:-9090}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="$SCRIPT_DIR/../dashboard"

echo "Starting Claude Orchestrator Dashboard..."
echo ""

# Check if metrics server is running
if ! curl -s "http://localhost:$METRICS_PORT/health" > /dev/null 2>&1; then
    echo "Metrics server not running. Starting it on port $METRICS_PORT..."
    "$SCRIPT_DIR/metrics-server.sh" "$METRICS_PORT" &
    METRICS_PID=$!
    echo "Metrics server started (PID: $METRICS_PID)"
    sleep 1
fi

echo ""
echo "Dashboard: http://localhost:$DASHBOARD_PORT"
echo "Metrics:   http://localhost:$METRICS_PORT/metrics"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start a simple HTTP server for the dashboard
cd "$DASHBOARD_DIR"

# Try Python 3 first, then Python 2, then npx serve
if command -v python3 &> /dev/null; then
    python3 -m http.server "$DASHBOARD_PORT"
elif command -v python &> /dev/null; then
    python -m SimpleHTTPServer "$DASHBOARD_PORT"
elif command -v npx &> /dev/null; then
    npx serve -l "$DASHBOARD_PORT"
else
    echo "Error: No suitable HTTP server found (need python3, python, or npx)"
    echo ""
    echo "You can manually open the dashboard file:"
    echo "  open $DASHBOARD_DIR/index.html"
    exit 1
fi
