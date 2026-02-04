#!/usr/bin/env bash
# Build worker context from all three memory tiers

WORKER_NAME="${1}"
WORKER_DOMAIN="${2}"
TASK_DESC="${3}"
PROJECT_ROOT="${4:-.}"

SEED_DIR="${HOME}/.claude/orchestrator/seed"
USER_DIR="${HOME}/.claude/orchestrator/user"
PROJECT_DIR="${PROJECT_ROOT}/.claude/memory"

# Initialize project memory if it doesn't exist
if [[ ! -d "${PROJECT_DIR}" ]]; then
  "${HOME}/.claude/scripts/init-project-memory.sh" "${PROJECT_ROOT}"
fi

# Start building context
cat <<EOF
# Worker: ${WORKER_NAME} - ${WORKER_DOMAIN} Domain

EOF

# 1. Load seed worker training template
if [[ -f "${SEED_DIR}/worker-training-template.md" ]]; then
  sed "s/{name}/${WORKER_NAME}/g; s/{domain}/${WORKER_DOMAIN}/g; s/{task_description}/See task below/g" \
    "${SEED_DIR}/worker-training-template.md"
  echo ""
fi

# 2. Load user preferences
echo "## User Preferences (Your Coding Standards)"
echo ""
if [[ -f "${USER_DIR}/preferences.json" ]]; then
  jq -r '.preferences[]' "${USER_DIR}/preferences.json" 2>/dev/null | sed 's/^/- /'
  echo ""
fi

# 3. Load project shared facts
echo "## Project Context (Shared Facts)"
echo ""
if [[ -f "${PROJECT_DIR}/shared/facts.json" ]]; then
  PROJECT_NAME=$(jq -r '.project_name // "this project"' "${PROJECT_DIR}/shared/facts.json")
  TECH_STACK=$(jq -r '.tech_stack[]? // empty' "${PROJECT_DIR}/shared/facts.json" | tr '\n' ',' | sed 's/,$//')
  echo "**Project:** ${PROJECT_NAME}"
  if [[ -n "${TECH_STACK}" ]]; then
    echo "**Tech Stack:** ${TECH_STACK}"
  fi
  echo ""
  jq -r '.facts[]? // empty' "${PROJECT_DIR}/shared/facts.json" | sed 's/^/- /'
  echo ""
fi

# 4. Load domain-specific memory
if [[ -f "${PROJECT_DIR}/domains/${WORKER_DOMAIN}.json" ]]; then
  # Capitalize domain name (bash 3.2 compatible)
  DOMAIN_CAP="$(echo "${WORKER_DOMAIN:0:1}" | tr '[:lower:]' '[:upper:]')${WORKER_DOMAIN:1}"
  echo "## ${DOMAIN_CAP} Domain Patterns (Pre-loaded)"
  echo ""

  PATTERNS=$(jq -r '.patterns[]? // empty' "${PROJECT_DIR}/domains/${WORKER_DOMAIN}.json")
  if [[ -n "${PATTERNS}" ]]; then
    echo "**Patterns:**"
    echo "${PATTERNS}" | sed 's/^/- /'
    echo ""
  fi

  CONVENTIONS=$(jq -r '.conventions[]? // empty' "${PROJECT_DIR}/domains/${WORKER_DOMAIN}.json")
  if [[ -n "${CONVENTIONS}" ]]; then
    echo "**Conventions:**"
    echo "${CONVENTIONS}" | sed 's/^/- /'
    echo ""
  fi
fi

# 5. Add the actual task
echo "---"
echo ""
echo "## Your Specific Task"
echo ""
echo "${TASK_DESC}"
echo ""

# 6. Reminder about memory APIs
echo "---"
echo ""
echo "## Remember to Use Memory"
echo ""
echo "During your work, capture learnings:"
echo "- Domain-specific: \`/assistant remember \"${WORKER_DOMAIN}: [pattern]\"\`"
echo "- Project-wide: \`/assistant remember \"shared: [fact]\"\`"
echo ""
echo "At task completion: \`/assistant session-end\`"
