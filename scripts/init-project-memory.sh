#!/bin/bash
# Initialize project-specific memory structure

PROJECT_ROOT="${1:-.}"
MEMORY_DIR="${PROJECT_ROOT}/.claude/memory"

echo "[INFO] Initializing project memory at ${PROJECT_ROOT}"

# Create directory structure
mkdir -p "${MEMORY_DIR}/orchestrator"
mkdir -p "${MEMORY_DIR}/domains"
mkdir -p "${MEMORY_DIR}/shared"
mkdir -p "${MEMORY_DIR}/sessions"

# Initialize orchestrator memory
cat > "${MEMORY_DIR}/orchestrator/decomposition.json" <<'EOF'
{
  "$schema": "orchestrator-decomposition-schema",
  "$description": "Tracks how this project decomposes into tasks and worker patterns",
  "patterns": [],
  "history": [],
  "notes": "This file captures orchestrator learnings specific to this project"
}
EOF

cat > "${MEMORY_DIR}/orchestrator/coordination.json" <<'EOF'
{
  "$schema": "orchestrator-coordination-schema",
  "$description": "Worker coordination patterns and dependencies for this project",
  "worker_patterns": [],
  "dependencies": [],
  "notes": "Tracks which workers work well together and common dependency chains"
}
EOF

cat > "${MEMORY_DIR}/orchestrator/quality.json" <<'EOF'
{
  "$schema": "orchestrator-quality-schema",
  "$description": "Quality and review learnings for this project",
  "common_issues": [],
  "review_patterns": [],
  "notes": "Captures what QA Guardian typically finds in this project"
}
EOF

# Initialize domain memories
for domain in frontend backend testing auth database devops docs; do
  cat > "${MEMORY_DIR}/domains/${domain}.json" <<EOF
{
  "\$schema": "domain-${domain}-schema",
  "\$description": "${domain} domain patterns and conventions for this project",
  "domain": "${domain}",
  "patterns": [],
  "conventions": [],
  "learnings": [],
  "notes": "Captures ${domain}-specific knowledge for this project"
}
EOF
done

# Initialize shared facts
cat > "${MEMORY_DIR}/shared/facts.json" <<'EOF'
{
  "$schema": "project-facts-schema",
  "$description": "Project-wide facts and context shared by all workers",
  "project_name": "",
  "tech_stack": [],
  "facts": [],
  "notes": "Store project-wide information that all workers should know"
}
EOF

echo "[OK] Initialized project memory at ${MEMORY_DIR}"
echo ""
echo "Directory structure created:"
echo "  ${MEMORY_DIR}/orchestrator/    - Orchestrator's project-specific memory"
echo "  ${MEMORY_DIR}/domains/         - Domain-specific worker memories"
echo "  ${MEMORY_DIR}/shared/          - Project-wide shared facts"
echo "  ${MEMORY_DIR}/sessions/        - Session summaries"
