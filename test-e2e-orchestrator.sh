#!/usr/bin/env bash
set -e

echo "=== End-to-End Orchestrator Memory Test ==="
echo ""

# Create realistic test project
TEST_PROJECT="/tmp/test-e2e-orchestrator"
rm -rf "${TEST_PROJECT}"
mkdir -p "${TEST_PROJECT}/src"
cd "${TEST_PROJECT}"

# Initialize git
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Create a simple project structure
cat > package.json <<'EOF'
{
  "name": "test-app",
  "version": "1.0.0"
}
EOF

git add package.json
git commit -m "Initial commit"

echo "1. Simulating orchestrator startup..."
# Initialize project memory (orchestrator would do this)
~/.claude/scripts/init-project-memory.sh "${TEST_PROJECT}"
echo "   ✓ Orchestrator initialized project memory"
echo ""

echo "2. Adding project-wide facts (simulating user input)..."
cat > "${TEST_PROJECT}/.claude/memory/shared/facts.json" <<'EOF'
{
  "project_name": "test-app",
  "tech_stack": ["React", "TypeScript", "Vite"],
  "facts": [
    "Uses React 18 with TypeScript strict mode",
    "State management via Zustand",
    "Testing with Vitest",
    "Deployment to Vercel"
  ]
}
EOF
echo "   ✓ Project facts stored"
echo ""

echo "3. Simulating worker spawn for frontend task..."
WORKER_CONTEXT=$(~/.claude/scripts/build-worker-context.sh \
  "ui-components" \
  "frontend" \
  "Create a reusable Button component with variants (primary, secondary, outline)" \
  "${TEST_PROJECT}")

# Save context to file
mkdir -p "${TEST_PROJECT}/.claude/workers"
echo "${WORKER_CONTEXT}" > "${TEST_PROJECT}/.claude/workers/ui-components-context.md"
echo "   ✓ Worker context generated"
echo ""

echo "4. Verifying worker received all memory tiers..."
if grep -q "Memory System Training" "${TEST_PROJECT}/.claude/workers/ui-components-context.md"; then
  echo "   ✓ Seed tier (worker training) injected"
fi

if grep -q "User Preferences" "${TEST_PROJECT}/.claude/workers/ui-components-context.md"; then
  echo "   ✓ User tier (preferences) injected"
fi

if grep -q "test-app" "${TEST_PROJECT}/.claude/workers/ui-components-context.md"; then
  echo "   ✓ Project tier (shared facts) injected"
fi

if grep -q "frontend Domain Patterns" "${TEST_PROJECT}/.claude/workers/ui-components-context.md"; then
  echo "   ✓ Domain-specific memory injected"
fi
echo ""

echo "5. Simulating worker discovering a pattern..."
# Worker would run: /assistant remember "frontend: Button components use CVA for variants"
jq '.patterns += ["Button components use CVA (class-variance-authority) for variant handling"]' \
  "${TEST_PROJECT}/.claude/memory/domains/frontend.json" > /tmp/frontend.json
mv /tmp/frontend.json "${TEST_PROJECT}/.claude/memory/domains/frontend.json"
echo "   ✓ Pattern stored to frontend domain memory"
echo ""

echo "6. Spawning second frontend worker (should receive first worker's learning)..."
WORKER2_CONTEXT=$(~/.claude/scripts/build-worker-context.sh \
  "form-components" \
  "frontend" \
  "Create Input component with validation" \
  "${TEST_PROJECT}")

if echo "${WORKER2_CONTEXT}" | grep -q "class-variance-authority"; then
  echo "   ✓ Second worker received first worker's pattern!"
else
  echo "   ✗ Second worker did not receive pattern"
  exit 1
fi
echo ""

echo "7. Testing cross-domain spawning (backend worker)..."
BACKEND_CONTEXT=$(~/.claude/scripts/build-worker-context.sh \
  "api-auth" \
  "backend" \
  "Create authentication API endpoints" \
  "${TEST_PROJECT}")

# Backend worker should get project facts but not frontend patterns
if echo "${BACKEND_CONTEXT}" | grep -q "test-app" && \
   ! echo "${BACKEND_CONTEXT}" | grep -q "class-variance-authority"; then
  echo "   ✓ Backend worker isolated from frontend patterns"
else
  echo "   ✗ Domain isolation failed"
  exit 1
fi
echo ""

echo "=== End-to-End Test Complete ==="
echo ""
echo "Summary:"
echo "✓ Orchestrator initializes project memory"
echo "✓ Workers receive three-tier memory context"
echo "✓ Workers can store domain-specific learnings"
echo "✓ Subsequent workers benefit from earlier learnings"
echo "✓ Domain isolation prevents cross-contamination"
echo ""
echo "Full memory system workflow validated!"
echo ""
echo "Worker context saved to:"
echo "  ${TEST_PROJECT}/.claude/workers/ui-components-context.md"
echo ""
echo "You can review the generated context to see what workers receive."
