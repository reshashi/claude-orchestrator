#!/bin/bash
# Classify worker domain based on task description and optional file patterns

TASK_DESC="${1}"
FILES="${2:-}"  # Optional: comma-separated list of files

SEED_DIR="${HOME}/.claude/orchestrator/seed"
CLASSIFICATIONS="${SEED_DIR}/domain-classifications.json"

# Default to general if can't classify
DOMAIN="general"

if [[ ! -f "${CLASSIFICATIONS}" ]]; then
  echo "${DOMAIN}"
  exit 0
fi

# Convert task to lowercase for matching
task_lower=$(echo "${TASK_DESC}" | tr '[:upper:]' '[:lower:]')

# Check each domain's keywords
for domain in frontend backend testing auth database devops docs; do
  keywords=$(jq -r ".${domain}.keywords[]" "${CLASSIFICATIONS}" 2>/dev/null)
  for keyword in ${keywords}; do
    if [[ "${task_lower}" == *"${keyword}"* ]]; then
      DOMAIN="${domain}"
      break 2
    fi
  done
done

# If files provided, check file patterns
if [[ -n "${FILES}" && "${DOMAIN}" == "general" ]]; then
  for domain in frontend backend testing auth database devops docs; do
    patterns=$(jq -r ".${domain}.file_patterns[]" "${CLASSIFICATIONS}" 2>/dev/null)
    for pattern in ${patterns}; do
      # Simple glob matching
      if [[ "${FILES}" == *"${pattern}"* ]]; then
        DOMAIN="${domain}"
        break 2
      fi
    done
  done
fi

echo "${DOMAIN}"
