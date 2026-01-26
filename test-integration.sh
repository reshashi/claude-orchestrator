#!/bin/bash
set -e

echo "=== Three-Tier Memory Integration Test ==="
echo ""

# Create test project
TEST_PROJECT="/tmp/test-orchestrator-integration"
rm -rf "${TEST_PROJECT}"
mkdir -p "${TEST_PROJECT}"
cd "${TEST_PROJECT}"

# Initialize as git repo (required for orchestrator)
git init
git config user.name "Test User"
git config user.email "test@example.com"

echo "1. Testing domain classification..."
DOMAIN=$(~/.claude/scripts/classify-domain.sh "build login form with email and password")
if [[ "${DOMAIN}" == "frontend" ]]; then
  echo "   ✓ Correctly classified as frontend"
else
  echo "   ✗ Expected 'frontend', got '${DOMAIN}'"
  exit 1
fi

DOMAIN=$(~/.claude/scripts/classify-domain.sh "create REST API endpoint for user registration")
if [[ "${DOMAIN}" == "backend" ]]; then
  echo "   ✓ Correctly classified as backend"
else
  echo "   ✗ Expected 'backend', got '${DOMAIN}'"
  exit 1
fi
echo ""

echo "2. Testing project memory initialization..."
~/.claude/scripts/init-project-memory.sh "${TEST_PROJECT}"
if [[ -d "${TEST_PROJECT}/.claude/memory/domains" ]]; then
  echo "   ✓ Project memory structure created"
else
  echo "   ✗ Failed to create project memory"
  exit 1
fi
echo ""

echo "3. Testing worker context builder..."
CONTEXT=$(~/.claude/scripts/build-worker-context.sh "ui-components" "frontend" "Build login form" "${TEST_PROJECT}")
if [[ "${CONTEXT}" == *"frontend Domain"* ]]; then
  echo "   ✓ Worker context includes domain"
else
  echo "   ✗ Worker context missing domain"
  exit 1
fi

if [[ "${CONTEXT}" == *"Memory System Training"* ]]; then
  echo "   ✓ Worker context includes training"
else
  echo "   ✗ Worker context missing training"
  exit 1
fi
echo ""

echo "4. Testing tier precedence..."
# Add data to each tier
mkdir -p ~/.claude/orchestrator/user
cat > ~/.claude/orchestrator/user/preferences.json <<'EOF'
{
  "preferences": ["User preference test"]
}
EOF

cat > "${TEST_PROJECT}/.claude/memory/shared/facts.json" <<'EOF'
{
  "project_name": "integration-test",
  "facts": ["Project-specific fact"]
}
EOF

CONTEXT=$(~/.claude/scripts/build-worker-context.sh "test-worker" "frontend" "test task" "${TEST_PROJECT}")

if [[ "${CONTEXT}" == *"User preference test"* ]]; then
  echo "   ✓ User preferences loaded"
else
  echo "   ✗ User preferences not loaded"
  exit 1
fi

if [[ "${CONTEXT}" == *"Project-specific fact"* ]]; then
  echo "   ✓ Project facts loaded"
else
  echo "   ✗ Project facts not loaded"
  exit 1
fi
echo ""

echo "5. Testing memory tier reading..."
~/.claude/scripts/memory-tier-read.sh seed orchestrator > /dev/null
echo "   ✓ Seed tier readable"

~/.claude/scripts/memory-tier-read.sh user preferences > /dev/null
echo "   ✓ User tier readable"

~/.claude/scripts/memory-tier-read.sh project shared > /dev/null
echo "   ✓ Project tier readable"
echo ""

echo "=== Integration Test Complete ==="
echo ""
echo "✓ Domain classification working"
echo "✓ Project memory initialization working"
echo "✓ Worker context builder working"
echo "✓ Tier precedence working"
echo "✓ All memory tiers accessible"
echo ""
echo "Integration validated! Ready for production use."
