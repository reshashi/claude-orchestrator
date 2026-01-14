#!/bin/bash
# Lightweight HTTP server for Prometheus metrics endpoint
# Usage: ./metrics-server.sh [port]

set -e

PORT="${1:-9090}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source metrics utilities
if [ -f "$SCRIPT_DIR/metrics.sh" ]; then
    # shellcheck source=./metrics.sh
    source "$SCRIPT_DIR/metrics.sh"
else
    echo "Error: metrics.sh not found"
    exit 1
fi

# Initialize metrics
init_metrics

echo "Starting metrics server on port $PORT..."
echo "Metrics endpoint: http://localhost:$PORT/metrics"
echo "Press Ctrl+C to stop"

# Simple HTTP server using netcat (nc)
# Note: This is a basic implementation for local development
# For production, consider using a proper HTTP server

handle_request() {
    local REQUEST
    REQUEST=$(cat)

    # Parse the request line
    local REQUEST_LINE
    REQUEST_LINE=$(echo "$REQUEST" | head -1)
    local _METHOD
    _METHOD=$(echo "$REQUEST_LINE" | cut -d' ' -f1)
    local PATH
    PATH=$(echo "$REQUEST_LINE" | cut -d' ' -f2)

    # Route the request
    case "$PATH" in
        /metrics)
            # Generate Prometheus metrics
            local BODY
            BODY=$(metrics_prometheus_format)
            local CONTENT_LENGTH
            CONTENT_LENGTH=$(echo -n "$BODY" | wc -c | tr -d ' ')

            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/plain; version=0.0.4"
            echo "Content-Length: $CONTENT_LENGTH"
            echo ""
            echo -e "$BODY"
            ;;

        /health)
            local BODY='{"status":"healthy"}'
            local CONTENT_LENGTH
            CONTENT_LENGTH=$(echo -n "$BODY" | wc -c | tr -d ' ')

            echo "HTTP/1.1 200 OK"
            echo "Content-Type: application/json"
            echo "Content-Length: $CONTENT_LENGTH"
            echo ""
            echo "$BODY"
            ;;

        /)
            local BODY
            BODY=$(cat << 'HTML'
<!DOCTYPE html>
<html>
<head><title>Claude Orchestrator Metrics</title></head>
<body>
<h1>Claude Orchestrator Metrics Server</h1>
<ul>
<li><a href="/metrics">/metrics</a> - Prometheus metrics</li>
<li><a href="/health">/health</a> - Health check</li>
</ul>
</body>
</html>
HTML
)
            local CONTENT_LENGTH
            CONTENT_LENGTH=$(echo -n "$BODY" | wc -c | tr -d ' ')

            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/html"
            echo "Content-Length: $CONTENT_LENGTH"
            echo ""
            echo "$BODY"
            ;;

        *)
            local BODY='{"error":"Not Found"}'
            local CONTENT_LENGTH
            CONTENT_LENGTH=$(echo -n "$BODY" | wc -c | tr -d ' ')

            echo "HTTP/1.1 404 Not Found"
            echo "Content-Type: application/json"
            echo "Content-Length: $CONTENT_LENGTH"
            echo ""
            echo "$BODY"
            ;;
    esac
}

# Check which netcat variant is available
if command -v nc.openbsd &> /dev/null; then
    NC_CMD="nc.openbsd"
elif command -v nc &> /dev/null; then
    NC_CMD="nc"
elif command -v ncat &> /dev/null; then
    NC_CMD="ncat"
else
    echo "Error: netcat (nc) not found. Please install it."
    exit 1
fi

# Mark orchestrator as up
metric_orchestrator_up

# Cleanup on exit
cleanup() {
    echo "Shutting down metrics server..."
    metric_orchestrator_down
    exit 0
}
trap cleanup SIGINT SIGTERM

# Main server loop
# Using a simple loop with nc for portability
while true; do
    # Handle one request at a time
    # The -l flag makes nc listen, -p specifies port
    # Different nc implementations have different flags

    # Try OpenBSD-style nc first (macOS default)
    if [ "$NC_CMD" = "nc.openbsd" ] || [ "$NC_CMD" = "nc" ]; then
        # macOS/OpenBSD nc: -l -p PORT
        # Some versions don't need -p
        handle_request | $NC_CMD -l "$PORT" 2>/dev/null || \
        handle_request | $NC_CMD -l -p "$PORT" 2>/dev/null
    else
        # nmap's ncat
        handle_request | $NC_CMD -l -p "$PORT" --keep-open 2>/dev/null
    fi

    # Small delay to prevent CPU spinning on errors
    sleep 0.1
done
