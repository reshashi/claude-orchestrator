#!/bin/bash
# Read memory with tier precedence (seed → user → project)

TIER="${1}"  # seed, user, project, or all
CATEGORY="${2}"  # orchestrator, domains, shared, facts
KEY="${3}"  # Optional specific key

SEED_DIR="${HOME}/.claude/orchestrator/seed"
USER_DIR="${HOME}/.claude/orchestrator/user"
PROJECT_DIR="${PWD}/.claude/memory"

read_tier() {
  local tier_dir="$1"
  local category="$2"
  local key="$3"

  case "$category" in
    orchestrator)
      if [[ -f "${tier_dir}/orchestrator-onboarding.md" ]]; then
        cat "${tier_dir}/orchestrator-onboarding.md"
      elif [[ -f "${tier_dir}/orchestrator/decomposition.json" ]]; then
        cat "${tier_dir}/orchestrator/decomposition.json"
      fi
      ;;
    domains)
      if [[ -n "$key" ]]; then
        if [[ -f "${tier_dir}/domains/${key}.json" ]]; then
          cat "${tier_dir}/domains/${key}.json"
        fi
      else
        if [[ -d "${tier_dir}/domains/" ]]; then
          ls "${tier_dir}/domains/" 2>/dev/null | sed 's/\.json$//'
        fi
      fi
      ;;
    shared)
      if [[ -f "${tier_dir}/shared/facts.json" ]]; then
        cat "${tier_dir}/shared/facts.json"
      fi
      ;;
    preferences)
      if [[ -f "${tier_dir}/preferences.json" ]]; then
        cat "${tier_dir}/preferences.json"
      fi
      ;;
    standards)
      if [[ -f "${tier_dir}/standards.json" ]]; then
        cat "${tier_dir}/standards.json"
      fi
      ;;
    *)
      echo "Unknown category: $category" >&2
      echo "Valid categories: orchestrator, domains, shared, preferences, standards" >&2
      return 1
      ;;
  esac
}

show_usage() {
  cat <<EOF
Usage: memory-tier-read.sh {seed|user|project|all} {category} [key]

Tiers:
  seed     - Built-in orchestrator training (~/.claude/orchestrator/seed/)
  user     - Your global preferences (~/.claude/memory/user/)
  project  - This project's learnings ({project}/.claude/memory/)
  all      - Show all tiers (demonstrates precedence)

Categories:
  orchestrator - Orchestrator's memory (seed: onboarding, project: decomposition/coordination)
  domains      - Domain-specific patterns (list or specify domain name)
  shared       - Project-wide shared facts
  preferences  - User coding preferences (user tier only)
  standards    - User development standards (user tier only)

Examples:
  memory-tier-read.sh seed orchestrator
  memory-tier-read.sh user preferences
  memory-tier-read.sh project domains frontend
  memory-tier-read.sh all domains
EOF
}

# Validate arguments
if [[ -z "$TIER" || -z "$CATEGORY" ]]; then
  show_usage
  exit 1
fi

case "$TIER" in
  seed)
    read_tier "$SEED_DIR" "$CATEGORY" "$KEY"
    ;;
  user)
    read_tier "$USER_DIR" "$CATEGORY" "$KEY"
    ;;
  project)
    read_tier "$PROJECT_DIR" "$CATEGORY" "$KEY"
    ;;
  all)
    echo "=== SEED TIER ==="
    read_tier "$SEED_DIR" "$CATEGORY" "$KEY"
    echo ""
    echo "=== USER TIER ==="
    read_tier "$USER_DIR" "$CATEGORY" "$KEY"
    echo ""
    echo "=== PROJECT TIER ==="
    read_tier "$PROJECT_DIR" "$CATEGORY" "$KEY"
    ;;
  *)
    echo "Error: Invalid tier '$TIER'" >&2
    echo "" >&2
    show_usage
    exit 1
    ;;
esac
