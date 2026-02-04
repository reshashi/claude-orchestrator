#!/usr/bin/env bash
# Metrics collection utilities for Claude Orchestrator
# Usage: source this file, then call metric_* functions

# Configuration
METRICS_DIR="${METRICS_DIR:-$HOME/.claude/metrics}"
METRICS_FILE="${METRICS_FILE:-$METRICS_DIR/metrics.json}"

# Ensure metrics directory exists
mkdir -p "$METRICS_DIR"

# Initialize metrics file if not exists
init_metrics() {
    if [ ! -f "$METRICS_FILE" ]; then
        cat > "$METRICS_FILE" << 'EOF'
{
  "counters": {
    "orchestrator_projects_total": 0,
    "orchestrator_projects_completed_total": 0,
    "orchestrator_projects_failed_total": 0,
    "orchestrator_workers_spawned_total": 0,
    "orchestrator_workers_merged_total": 0,
    "orchestrator_prs_created_total": 0,
    "orchestrator_prs_merged_total": 0,
    "orchestrator_reviews_total": 0,
    "orchestrator_reviews_passed_total": 0,
    "orchestrator_reviews_failed_total": 0,
    "orchestrator_iterations_total": 0
  },
  "gauges": {
    "orchestrator_active_workers": 0,
    "orchestrator_active_projects": 0,
    "orchestrator_up": 0
  },
  "histograms": {
    "orchestrator_prd_generation_seconds": {"buckets": {}, "sum": 0, "count": 0},
    "orchestrator_worker_execution_seconds": {"buckets": {}, "sum": 0, "count": 0},
    "orchestrator_review_seconds": {"buckets": {}, "sum": 0, "count": 0},
    "orchestrator_project_total_seconds": {"buckets": {}, "sum": 0, "count": 0}
  },
  "last_updated": ""
}
EOF
    fi
}

# Increment a counter
# Usage: metric_inc "orchestrator_projects_total" [amount]
metric_inc() {
    local METRIC="$1"
    local AMOUNT="${2:-1}"

    init_metrics

    local TMP_FILE
    TMP_FILE=$(mktemp)

    jq --arg metric "$METRIC" --argjson amount "$AMOUNT" \
        '.counters[$metric] = (.counters[$metric] // 0) + $amount | .last_updated = now | todate' \
        "$METRICS_FILE" > "$TMP_FILE" 2>/dev/null && mv "$TMP_FILE" "$METRICS_FILE"
}

# Set a gauge value
# Usage: metric_set "orchestrator_active_workers" 5
metric_set() {
    local METRIC="$1"
    local VALUE="$2"

    init_metrics

    local TMP_FILE
    TMP_FILE=$(mktemp)

    jq --arg metric "$METRIC" --argjson value "$VALUE" \
        '.gauges[$metric] = $value | .last_updated = now | todate' \
        "$METRICS_FILE" > "$TMP_FILE" 2>/dev/null && mv "$TMP_FILE" "$METRICS_FILE"
}

# Record a histogram observation
# Usage: metric_observe "orchestrator_worker_execution_seconds" 45.5
metric_observe() {
    local METRIC="$1"
    local VALUE="$2"

    init_metrics

    # Define histogram buckets (in seconds)
    local BUCKETS="10 30 60 120 300 600 1800 3600"

    local TMP_FILE
    TMP_FILE=$(mktemp)

    # Update histogram sum, count, and buckets
    jq --arg metric "$METRIC" --argjson value "$VALUE" --arg buckets "$BUCKETS" '
        .histograms[$metric].sum = (.histograms[$metric].sum // 0) + $value |
        .histograms[$metric].count = (.histograms[$metric].count // 0) + 1 |
        .histograms[$metric].buckets = (
            .histograms[$metric].buckets // {} |
            . as $b |
            ($buckets | split(" ") | map(tonumber)) as $limits |
            reduce $limits[] as $limit ($b;
                if $value <= $limit then
                    .[$limit | tostring] = ((.[$limit | tostring] // 0) + 1)
                else .
                end
            )
        ) |
        .last_updated = now | todate
    ' "$METRICS_FILE" > "$TMP_FILE" 2>/dev/null && mv "$TMP_FILE" "$METRICS_FILE"
}

# Get current value of a counter
# Usage: metric_get_counter "orchestrator_projects_total"
metric_get_counter() {
    local METRIC="$1"
    init_metrics
    jq -r ".counters[\"$METRIC\"] // 0" "$METRICS_FILE" 2>/dev/null
}

# Get current value of a gauge
# Usage: metric_get_gauge "orchestrator_active_workers"
metric_get_gauge() {
    local METRIC="$1"
    init_metrics
    jq -r ".gauges[\"$METRIC\"] // 0" "$METRICS_FILE" 2>/dev/null
}

# Output metrics in Prometheus text format
# Usage: metrics_prometheus_format
metrics_prometheus_format() {
    init_metrics

    local OUTPUT=""

    # Counters
    OUTPUT+="# HELP orchestrator_projects_total Total number of projects started\n"
    OUTPUT+="# TYPE orchestrator_projects_total counter\n"
    OUTPUT+="orchestrator_projects_total $(metric_get_counter orchestrator_projects_total)\n"

    OUTPUT+="\n# HELP orchestrator_projects_completed_total Total number of projects completed successfully\n"
    OUTPUT+="# TYPE orchestrator_projects_completed_total counter\n"
    OUTPUT+="orchestrator_projects_completed_total $(metric_get_counter orchestrator_projects_completed_total)\n"

    OUTPUT+="\n# HELP orchestrator_projects_failed_total Total number of projects that failed\n"
    OUTPUT+="# TYPE orchestrator_projects_failed_total counter\n"
    OUTPUT+="orchestrator_projects_failed_total $(metric_get_counter orchestrator_projects_failed_total)\n"

    OUTPUT+="\n# HELP orchestrator_workers_spawned_total Total number of workers spawned\n"
    OUTPUT+="# TYPE orchestrator_workers_spawned_total counter\n"
    OUTPUT+="orchestrator_workers_spawned_total $(metric_get_counter orchestrator_workers_spawned_total)\n"

    OUTPUT+="\n# HELP orchestrator_workers_merged_total Total number of workers that merged successfully\n"
    OUTPUT+="# TYPE orchestrator_workers_merged_total counter\n"
    OUTPUT+="orchestrator_workers_merged_total $(metric_get_counter orchestrator_workers_merged_total)\n"

    OUTPUT+="\n# HELP orchestrator_prs_created_total Total number of PRs created\n"
    OUTPUT+="# TYPE orchestrator_prs_created_total counter\n"
    OUTPUT+="orchestrator_prs_created_total $(metric_get_counter orchestrator_prs_created_total)\n"

    OUTPUT+="\n# HELP orchestrator_prs_merged_total Total number of PRs merged\n"
    OUTPUT+="# TYPE orchestrator_prs_merged_total counter\n"
    OUTPUT+="orchestrator_prs_merged_total $(metric_get_counter orchestrator_prs_merged_total)\n"

    OUTPUT+="\n# HELP orchestrator_reviews_total Total QA reviews run\n"
    OUTPUT+="# TYPE orchestrator_reviews_total counter\n"
    OUTPUT+="orchestrator_reviews_total $(metric_get_counter orchestrator_reviews_total)\n"

    OUTPUT+="\n# HELP orchestrator_reviews_passed_total QA reviews that passed\n"
    OUTPUT+="# TYPE orchestrator_reviews_passed_total counter\n"
    OUTPUT+="orchestrator_reviews_passed_total $(metric_get_counter orchestrator_reviews_passed_total)\n"

    OUTPUT+="\n# HELP orchestrator_reviews_failed_total QA reviews that failed\n"
    OUTPUT+="# TYPE orchestrator_reviews_failed_total counter\n"
    OUTPUT+="orchestrator_reviews_failed_total $(metric_get_counter orchestrator_reviews_failed_total)\n"

    OUTPUT+="\n# HELP orchestrator_iterations_total Total number of project iterations\n"
    OUTPUT+="# TYPE orchestrator_iterations_total counter\n"
    OUTPUT+="orchestrator_iterations_total $(metric_get_counter orchestrator_iterations_total)\n"

    # Gauges
    OUTPUT+="\n# HELP orchestrator_active_workers Current number of active workers\n"
    OUTPUT+="# TYPE orchestrator_active_workers gauge\n"
    OUTPUT+="orchestrator_active_workers $(metric_get_gauge orchestrator_active_workers)\n"

    OUTPUT+="\n# HELP orchestrator_active_projects Current number of active projects\n"
    OUTPUT+="# TYPE orchestrator_active_projects gauge\n"
    OUTPUT+="orchestrator_active_projects $(metric_get_gauge orchestrator_active_projects)\n"

    OUTPUT+="\n# HELP orchestrator_up Whether orchestrator is running (1=up, 0=down)\n"
    OUTPUT+="# TYPE orchestrator_up gauge\n"
    OUTPUT+="orchestrator_up $(metric_get_gauge orchestrator_up)\n"

    # Histograms (simplified output - just sum and count for now)
    for HIST in prd_generation_seconds worker_execution_seconds review_seconds project_total_seconds; do
        local FULL_NAME="orchestrator_${HIST}"
        local SUM
        local COUNT
        SUM=$(jq -r ".histograms[\"$FULL_NAME\"].sum // 0" "$METRICS_FILE" 2>/dev/null)
        COUNT=$(jq -r ".histograms[\"$FULL_NAME\"].count // 0" "$METRICS_FILE" 2>/dev/null)

        OUTPUT+="\n# HELP $FULL_NAME Time histogram for $HIST\n"
        OUTPUT+="# TYPE $FULL_NAME histogram\n"
        OUTPUT+="${FULL_NAME}_sum $SUM\n"
        OUTPUT+="${FULL_NAME}_count $COUNT\n"

        # Output bucket values
        local BUCKETS
        BUCKETS=$(jq -r ".histograms[\"$FULL_NAME\"].buckets // {} | to_entries | .[] | \"\(.key) \(.value)\"" "$METRICS_FILE" 2>/dev/null)
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local BUCKET_LE
            local BUCKET_VAL
            BUCKET_LE=$(echo "$line" | cut -d' ' -f1)
            BUCKET_VAL=$(echo "$line" | cut -d' ' -f2)
            OUTPUT+="${FULL_NAME}_bucket{le=\"$BUCKET_LE\"} $BUCKET_VAL\n"
        done <<< "$BUCKETS"
        OUTPUT+="${FULL_NAME}_bucket{le=\"+Inf\"} $COUNT\n"
    done

    echo -e "$OUTPUT"
}

# Convenience functions for common metrics

metric_project_started() {
    metric_inc "orchestrator_projects_total"
    metric_set "orchestrator_active_projects" "$(( $(metric_get_gauge orchestrator_active_projects) + 1 ))"
}

metric_project_completed() {
    metric_inc "orchestrator_projects_completed_total"
    local CURRENT
    CURRENT=$(metric_get_gauge orchestrator_active_projects)
    [ "$CURRENT" -gt 0 ] && metric_set "orchestrator_active_projects" "$(( CURRENT - 1 ))"
}

metric_project_failed() {
    metric_inc "orchestrator_projects_failed_total"
    local CURRENT
    CURRENT=$(metric_get_gauge orchestrator_active_projects)
    [ "$CURRENT" -gt 0 ] && metric_set "orchestrator_active_projects" "$(( CURRENT - 1 ))"
}

metric_worker_spawned() {
    metric_inc "orchestrator_workers_spawned_total"
    metric_set "orchestrator_active_workers" "$(( $(metric_get_gauge orchestrator_active_workers) + 1 ))"
}

metric_worker_merged() {
    metric_inc "orchestrator_workers_merged_total"
    local CURRENT
    CURRENT=$(metric_get_gauge orchestrator_active_workers)
    [ "$CURRENT" -gt 0 ] && metric_set "orchestrator_active_workers" "$(( CURRENT - 1 ))"
}

metric_pr_created() {
    metric_inc "orchestrator_prs_created_total"
}

metric_pr_merged() {
    metric_inc "orchestrator_prs_merged_total"
}

metric_review_started() {
    metric_inc "orchestrator_reviews_total"
}

metric_review_passed() {
    metric_inc "orchestrator_reviews_passed_total"
}

metric_review_failed() {
    metric_inc "orchestrator_reviews_failed_total"
}

metric_iteration() {
    metric_inc "orchestrator_iterations_total"
}

metric_orchestrator_up() {
    metric_set "orchestrator_up" 1
}

metric_orchestrator_down() {
    metric_set "orchestrator_up" 0
}

# Export functions
export -f init_metrics metric_inc metric_set metric_observe
export -f metric_get_counter metric_get_gauge metrics_prometheus_format
export -f metric_project_started metric_project_completed metric_project_failed
export -f metric_worker_spawned metric_worker_merged
export -f metric_pr_created metric_pr_merged
export -f metric_review_started metric_review_passed metric_review_failed
export -f metric_iteration metric_orchestrator_up metric_orchestrator_down
export METRICS_DIR METRICS_FILE
