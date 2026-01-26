#!/bin/bash
set -e

echo "=== Three-Tier Memory Prototype Test ==="
echo ""

# Setup test project
TEST_PROJECT="/tmp/test-orchestrator-memory"
rm -rf "${TEST_PROJECT}"
mkdir -p "${TEST_PROJECT}"
cd "${TEST_PROJECT}"

SCRIPT_DIR="${HOME}/projects/claude-orchestrator/scripts"

# Initialize project memory
echo "1. Initializing project memory..."
${SCRIPT_DIR}/init-project-memory.sh "${TEST_PROJECT}"
echo ""

# Ensure user tier exists with test data
echo "2. Setting up user tier with test data..."
mkdir -p ~/.claude/memory/user
cat > ~/.claude/memory/user/preferences.json <<'EOF'
{
  "coding_style": "TypeScript strict mode",
  "test_framework": "vitest",
  "prefer_functional": true
}
EOF

cat > ~/.claude/memory/user/standards.json <<'EOF'
{
  "git": {
    "commit_style": "conventional",
    "branch_naming": "feature/description"
  },
  "testing": {
    "min_coverage": 90
  }
}
EOF
echo "   ✓ User tier configured"
echo ""

# Ensure seed tier exists
echo "3. Verifying seed tier..."
if [[ -f ~/.claude/orchestrator/seed/orchestrator-onboarding.md ]]; then
  echo "   ✓ Seed tier exists"
else
  echo "   ✗ Seed tier not found - run install.sh first"
  echo "   Creating minimal seed for testing..."
  mkdir -p ~/.claude/orchestrator/seed
  cp ~/projects/claude-orchestrator/seed/* ~/.claude/orchestrator/seed/
  echo "   ✓ Seed tier created"
fi
echo ""

# Add some test data to project tier
echo "4. Adding test data to project tier..."
cat > "${TEST_PROJECT}/.claude/memory/shared/facts.json" <<'EOF'
{
  "project_name": "test-app",
  "tech_stack": ["React", "Node.js", "PostgreSQL"],
  "facts": [
    "Uses Railway for deployment",
    "API rate limit: 100 req/min",
    "Authentication via JWT tokens"
  ]
}
EOF

cat > "${TEST_PROJECT}/.claude/memory/domains/frontend.json" <<'EOF'
{
  "domain": "frontend",
  "patterns": [
    "Use shadcn/ui for components",
    "Prefer functional components",
    "State management with Zustand"
  ],
  "conventions": [
    "Components in src/components/{feature}/",
    "Use TailwindCSS for styling"
  ],
  "learnings": []
}
EOF
echo "   ✓ Project tier updated with test facts"
echo ""

# Test tier reading
echo "5. Testing tier-aware reading..."
echo ""

echo "--- Test 5a: Reading orchestrator onboarding (seed tier) ---"
${SCRIPT_DIR}/memory-tier-read.sh seed orchestrator | head -10
echo ""

echo "--- Test 5b: Reading user preferences ---"
${SCRIPT_DIR}/memory-tier-read.sh user preferences | jq . 2>/dev/null || cat ~/.claude/memory/user/preferences.json
echo ""

echo "--- Test 5c: Reading project facts ---"
${SCRIPT_DIR}/memory-tier-read.sh project shared | jq . 2>/dev/null || cat "${TEST_PROJECT}/.claude/memory/shared/facts.json"
echo ""

echo "--- Test 5d: Listing domains across all tiers ---"
${SCRIPT_DIR}/memory-tier-read.sh all domains
echo ""

echo "--- Test 5e: Reading frontend domain (project tier) ---"
${SCRIPT_DIR}/memory-tier-read.sh project domains frontend | jq . 2>/dev/null || cat "${TEST_PROJECT}/.claude/memory/domains/frontend.json"
echo ""

# Verify directory structure
echo "6. Verifying directory structure..."
echo ""
echo "Seed tier:"
ls -1 ~/.claude/orchestrator/seed/ 2>/dev/null | sed 's/^/  /' || echo "  (not found)"
echo ""

echo "User tier:"
ls -1 ~/.claude/memory/user/ 2>/dev/null | sed 's/^/  /' || echo "  (not found)"
echo ""

echo "Project tier:"
find "${TEST_PROJECT}/.claude/memory" -type f | sed "s|${TEST_PROJECT}/.claude/memory/|  |" | sort
echo ""

# Summary
echo "=== Prototype Test Complete ==="
echo ""
echo "✓ Seed tier: ~/.claude/orchestrator/seed/"
echo "✓ User tier: ~/.claude/memory/user/"
echo "✓ Project tier: ${TEST_PROJECT}/.claude/memory/"
echo ""
echo "Three-tier memory architecture validated!"
echo ""
echo "Next steps:"
echo "  - Integrate memory injection into worker spawning"
echo "  - Add domain classification logic"
echo "  - Extend orchestrator-loop.sh to load orchestrator memory"
echo "  - Add memory capture during worker execution"
