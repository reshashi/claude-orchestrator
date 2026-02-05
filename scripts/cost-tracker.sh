#!/usr/bin/env bash
# Cost tracking utilities for Claude Orchestrator
# Tracks Claude API token usage and estimates costs

# Configuration
COSTS_DIR="${COSTS_DIR:-$HOME/.claude/costs}"
PRICING_FILE="${PRICING_FILE:-$COSTS_DIR/pricing.json}"

# Ensure costs directory exists
mkdir -p "$COSTS_DIR"

# Initialize pricing configuration (per 1M tokens)
init_pricing() {
    if [ ! -f "$PRICING_FILE" ]; then
        cat > "$PRICING_FILE" << 'EOF'
{
  "models": {
    "claude-opus-4-5-20251101": {
      "input_per_million": 15.00,
      "output_per_million": 75.00,
      "display_name": "Claude Opus 4.5"
    },
    "claude-sonnet-4-20250514": {
      "input_per_million": 3.00,
      "output_per_million": 15.00,
      "display_name": "Claude Sonnet 4"
    },
    "claude-3-5-haiku-20241022": {
      "input_per_million": 0.80,
      "output_per_million": 4.00,
      "display_name": "Claude 3.5 Haiku"
    },
    "claude-3-5-sonnet-20241022": {
      "input_per_million": 3.00,
      "output_per_million": 15.00,
      "display_name": "Claude 3.5 Sonnet"
    }
  },
  "default_model": "claude-sonnet-4-20250514",
  "budget_alert_threshold": 10.00,
  "currency": "USD"
}
EOF
    fi
}

# Get project cost file path
get_project_cost_file() {
    local PROJECT_NAME="$1"
    echo "$COSTS_DIR/${PROJECT_NAME}.json"
}

# Initialize cost tracking for a project
init_project_costs() {
    local PROJECT_NAME="$1"
    local COST_FILE
    COST_FILE=$(get_project_cost_file "$PROJECT_NAME")

    if [ ! -f "$COST_FILE" ]; then
        local TIMESTAMP
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        cat > "$COST_FILE" << EOF
{
  "project_name": "$PROJECT_NAME",
  "started_at": "$TIMESTAMP",
  "workers": {},
  "totals": {
    "input_tokens": 0,
    "output_tokens": 0,
    "estimated_cost_usd": 0.0
  },
  "events": []
}
EOF
    fi
}

# Record token usage for a worker
# Usage: record_usage <project> <worker_name> <model> <input_tokens> <output_tokens>
record_usage() {
    local PROJECT_NAME="$1"
    local WORKER_NAME="$2"
    local MODEL="${3:-claude-sonnet-4-20250514}"
    local INPUT_TOKENS="$4"
    local OUTPUT_TOKENS="$5"

    init_pricing
    init_project_costs "$PROJECT_NAME"

    local COST_FILE
    COST_FILE=$(get_project_cost_file "$PROJECT_NAME")

    # Calculate cost
    local INPUT_RATE
    local OUTPUT_RATE
    INPUT_RATE=$(jq -r ".models[\"$MODEL\"].input_per_million // 3.00" "$PRICING_FILE" 2>/dev/null)
    OUTPUT_RATE=$(jq -r ".models[\"$MODEL\"].output_per_million // 15.00" "$PRICING_FILE" 2>/dev/null)

    local INPUT_COST
    local OUTPUT_COST
    local TOTAL_COST
    INPUT_COST=$(echo "scale=6; $INPUT_TOKENS * $INPUT_RATE / 1000000" | bc)
    OUTPUT_COST=$(echo "scale=6; $OUTPUT_TOKENS * $OUTPUT_RATE / 1000000" | bc)
    TOTAL_COST=$(echo "scale=6; $INPUT_COST + $OUTPUT_COST" | bc)

    local TIMESTAMP
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update project cost file
    local TMP_FILE
    TMP_FILE=$(mktemp)

    jq --arg worker "$WORKER_NAME" \
       --arg model "$MODEL" \
       --argjson input "$INPUT_TOKENS" \
       --argjson output "$OUTPUT_TOKENS" \
       --argjson cost "$TOTAL_COST" \
       --arg ts "$TIMESTAMP" '
        # Update worker stats
        .workers[$worker] = (.workers[$worker] // {
            "model": $model,
            "input_tokens": 0,
            "output_tokens": 0,
            "estimated_cost_usd": 0.0,
            "calls": 0
        }) |
        .workers[$worker].input_tokens += $input |
        .workers[$worker].output_tokens += $output |
        .workers[$worker].estimated_cost_usd = ((.workers[$worker].estimated_cost_usd // 0) + $cost | . * 1000000 | round / 1000000) |
        .workers[$worker].calls += 1 |

        # Update totals
        .totals.input_tokens += $input |
        .totals.output_tokens += $output |
        .totals.estimated_cost_usd = ((.totals.estimated_cost_usd // 0) + $cost | . * 1000000 | round / 1000000) |

        # Add event
        .events += [{
            "timestamp": $ts,
            "worker": $worker,
            "model": $model,
            "input_tokens": $input,
            "output_tokens": $output,
            "cost_usd": ($cost | . * 1000000 | round / 1000000)
        }] |

        .last_updated = $ts
    ' "$COST_FILE" > "$TMP_FILE" 2>/dev/null && mv "$TMP_FILE" "$COST_FILE"

    # Check budget alert
    check_budget_alert "$PROJECT_NAME"
}

# Check if budget threshold exceeded
check_budget_alert() {
    local PROJECT_NAME="$1"
    local COST_FILE
    COST_FILE=$(get_project_cost_file "$PROJECT_NAME")

    if [ ! -f "$COST_FILE" ]; then
        return 0
    fi

    local THRESHOLD
    THRESHOLD=$(jq -r '.budget_alert_threshold // 10.00' "$PRICING_FILE" 2>/dev/null)

    local CURRENT_COST
    CURRENT_COST=$(jq -r '.totals.estimated_cost_usd // 0' "$COST_FILE" 2>/dev/null)

    # Check if threshold exceeded
    if [ "$(echo "$CURRENT_COST >= $THRESHOLD" | bc)" -eq 1 ]; then
        echo "BUDGET ALERT: Project '$PROJECT_NAME' has exceeded cost threshold"
        echo "Current cost: \$$CURRENT_COST (threshold: \$$THRESHOLD)"

        # Send notification
        osascript -e "display notification \"Cost: \$$CURRENT_COST exceeds \$$THRESHOLD threshold\" with title \"Budget Alert: $PROJECT_NAME\" sound name \"Basso\"" 2>/dev/null || true

        return 1
    fi

    return 0
}

# Parse Claude Code output for token counts
# Claude Code displays: "Token usage: X input, Y output"
# Usage: parse_tokens_from_output <output_text>
parse_tokens_from_output() {
    local OUTPUT="$1"

    # Look for token usage patterns
    # Pattern 1: "Token usage: X input, Y output"
    # Pattern 2: "Input tokens: X, Output tokens: Y"
    # Pattern 3: "~X input tokens, ~Y output tokens"

    local INPUT_TOKENS=0
    local OUTPUT_TOKENS=0

    # Try different patterns
    if echo "$OUTPUT" | grep -qE "Token usage:"; then
        INPUT_TOKENS=$(echo "$OUTPUT" | grep -oE "Token usage: [0-9,]+ input" | grep -oE "[0-9,]+" | tr -d ',' | tail -1)
        OUTPUT_TOKENS=$(echo "$OUTPUT" | grep -oE "[0-9,]+ output" | grep -oE "[0-9,]+" | tr -d ',' | tail -1)
    elif echo "$OUTPUT" | grep -qE "input tokens.*output tokens"; then
        INPUT_TOKENS=$(echo "$OUTPUT" | grep -oE "[0-9,]+ input tokens" | grep -oE "[0-9,]+" | tr -d ',' | tail -1)
        OUTPUT_TOKENS=$(echo "$OUTPUT" | grep -oE "[0-9,]+ output tokens" | grep -oE "[0-9,]+" | tr -d ',' | tail -1)
    fi

    # Default to estimates if no tokens found
    [ -z "$INPUT_TOKENS" ] && INPUT_TOKENS=0
    [ -z "$OUTPUT_TOKENS" ] && OUTPUT_TOKENS=0

    echo "$INPUT_TOKENS $OUTPUT_TOKENS"
}

# Estimate tokens from text length (rough approximation)
# ~4 characters per token on average
estimate_tokens_from_text() {
    local TEXT="$1"
    local CHAR_COUNT
    CHAR_COUNT=$(echo -n "$TEXT" | wc -c | tr -d ' ')
    echo $(( CHAR_COUNT / 4 ))
}

# Get project cost summary
# Usage: get_project_summary <project_name>
get_project_summary() {
    local PROJECT_NAME="$1"
    local COST_FILE
    COST_FILE=$(get_project_cost_file "$PROJECT_NAME")

    if [ ! -f "$COST_FILE" ]; then
        echo "No cost data for project: $PROJECT_NAME"
        return 1
    fi

    jq -r '
        "Project: \(.project_name)",
        "Started: \(.started_at)",
        "Last Updated: \(.last_updated // "N/A")",
        "",
        "TOTALS:",
        "  Input Tokens:  \(.totals.input_tokens | tostring | . as $n | ($n | length) as $len | if $len > 3 then ($n[0:$len-3] + "," + $n[$len-3:]) else $n end)",
        "  Output Tokens: \(.totals.output_tokens | tostring | . as $n | ($n | length) as $len | if $len > 3 then ($n[0:$len-3] + "," + $n[$len-3:]) else $n end)",
        "  Estimated Cost: $\(.totals.estimated_cost_usd | tostring | .[0:6])",
        "",
        "WORKERS:",
        (.workers | to_entries | .[] | "  \(.key):",
            "    Model: \(.value.model)",
            "    Calls: \(.value.calls)",
            "    Input: \(.value.input_tokens)",
            "    Output: \(.value.output_tokens)",
            "    Cost: $\(.value.estimated_cost_usd | tostring | .[0:6])"
        )
    ' "$COST_FILE" 2>/dev/null
}

# Get total costs across all projects
get_all_costs() {
    local TOTAL_INPUT=0
    local TOTAL_OUTPUT=0
    local TOTAL_COST=0

    echo "=== Claude Orchestrator Cost Summary ==="
    echo ""

    for COST_FILE in "$COSTS_DIR"/*.json; do
        [ "$COST_FILE" = "$COSTS_DIR/pricing.json" ] && continue
        [ ! -f "$COST_FILE" ] && continue

        local PROJECT_NAME
        local INPUT
        local OUTPUT
        local COST
        PROJECT_NAME=$(jq -r '.project_name' "$COST_FILE" 2>/dev/null)
        INPUT=$(jq -r '.totals.input_tokens // 0' "$COST_FILE" 2>/dev/null)
        OUTPUT=$(jq -r '.totals.output_tokens // 0' "$COST_FILE" 2>/dev/null)
        COST=$(jq -r '.totals.estimated_cost_usd // 0' "$COST_FILE" 2>/dev/null)

        echo "$PROJECT_NAME: \$$COST (input: $INPUT, output: $OUTPUT)"

        TOTAL_INPUT=$((TOTAL_INPUT + INPUT))
        TOTAL_OUTPUT=$((TOTAL_OUTPUT + OUTPUT))
        TOTAL_COST=$(echo "scale=6; $TOTAL_COST + $COST" | bc)
    done

    echo ""
    echo "=== GRAND TOTAL ==="
    echo "Input Tokens:  $TOTAL_INPUT"
    echo "Output Tokens: $TOTAL_OUTPUT"
    echo "Total Cost:    \$$TOTAL_COST"
}

# Generate cost report in markdown
generate_cost_report() {
    local PROJECT_NAME="$1"
    local COST_FILE
    COST_FILE=$(get_project_cost_file "$PROJECT_NAME")

    if [ ! -f "$COST_FILE" ]; then
        echo "No cost data for project: $PROJECT_NAME"
        return 1
    fi

    jq -r '
        "# Cost Report: \(.project_name)",
        "",
        "**Started:** \(.started_at)",
        "**Last Updated:** \(.last_updated // "N/A")",
        "",
        "## Summary",
        "",
        "| Metric | Value |",
        "|--------|-------|",
        "| Input Tokens | \(.totals.input_tokens | tostring) |",
        "| Output Tokens | \(.totals.output_tokens | tostring) |",
        "| **Estimated Cost** | **$\(.totals.estimated_cost_usd | tostring | .[0:6])** |",
        "",
        "## Workers",
        "",
        "| Worker | Model | Calls | Input | Output | Cost |",
        "|--------|-------|-------|-------|--------|------|",
        (.workers | to_entries | .[] |
            "| \(.key) | \(.value.model) | \(.value.calls) | \(.value.input_tokens) | \(.value.output_tokens) | $\(.value.estimated_cost_usd | tostring | .[0:6]) |"
        ),
        "",
        "## Event History",
        "",
        "| Time | Worker | Model | Input | Output | Cost |",
        "|------|--------|-------|-------|--------|------|",
        (.events | .[-10:] | .[] |
            "| \(.timestamp) | \(.worker) | \(.model) | \(.input_tokens) | \(.output_tokens) | $\(.cost_usd | tostring | .[0:6]) |"
        )
    ' "$COST_FILE" 2>/dev/null
}

# Set budget alert threshold
set_budget_threshold() {
    local THRESHOLD="$1"
    init_pricing

    local TMP_FILE
    TMP_FILE=$(mktemp)
    jq --argjson threshold "$THRESHOLD" '.budget_alert_threshold = $threshold' "$PRICING_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$PRICING_FILE"

    echo "Budget alert threshold set to: \$$THRESHOLD"
}

# Export functions
export -f init_pricing init_project_costs record_usage check_budget_alert
export -f parse_tokens_from_output estimate_tokens_from_text
export -f get_project_summary get_all_costs generate_cost_report set_budget_threshold
export -f get_project_cost_file
export COSTS_DIR PRICING_FILE
