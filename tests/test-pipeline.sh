#!/usr/bin/env bash
# Tests for the delivery pipeline scripts
# Run: ./tests/test-pipeline.sh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$SCRIPT_DIR/../pipeline"
CONFIG_DIR="$SCRIPT_DIR/../config"
export ORCHESTRATOR_AGENTS_DIR="$SCRIPT_DIR/../agents"

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_MESSAGES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test helpers
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES+=("$msg: expected '$expected', got '$actual'")
        echo -e "  ${RED}✗${NC} $msg"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
    fi
}

assert_ok() {
    local exit_code="$1" msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$exit_code" -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES+=("$msg: expected exit 0, got $exit_code")
        echo -e "  ${RED}✗${NC} $msg (exit code: $exit_code)"
    fi
}

assert_fail() {
    local exit_code="$1" msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$exit_code" -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES+=("$msg: expected non-zero exit, got 0")
        echo -e "  ${RED}✗${NC} $msg (expected failure, got success)"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES+=("$msg: '$needle' not found in output")
        echo -e "  ${RED}✗${NC} $msg"
        echo "    looking for: '$needle'"
    fi
}

# Setup temp dir for test state
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
export ORCHESTRATOR_STATE_DIR="$TEMP_DIR/state"

# ============================================================
echo ""
echo -e "${YELLOW}=== Mode Detection ===${NC}"
# ============================================================

(
    unset ORCHESTRATOR_MODE
    unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
    # shellcheck source=../scripts/mode-detect.sh
    source "$SCRIPT_DIR/../scripts/mode-detect.sh"
    assert_eq "pipeline" "$ORCHESTRATOR_MODE" "Default mode is pipeline"
)

(
    unset ORCHESTRATOR_MODE
    export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
    # shellcheck source=../scripts/mode-detect.sh
    source "$SCRIPT_DIR/../scripts/mode-detect.sh"
    assert_eq "agent-teams" "$ORCHESTRATOR_MODE" "Detects agent-teams from env var"
)

(
    export ORCHESTRATOR_MODE="agent-teams"
    # shellcheck source=../scripts/mode-detect.sh
    source "$SCRIPT_DIR/../scripts/mode-detect.sh"
    assert_eq "agent-teams" "$ORCHESTRATOR_MODE" "Respects pre-set ORCHESTRATOR_MODE"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Delivery State ===${NC}"
# ============================================================

# Test init
output=$(bash "$PIPELINE_DIR/delivery-state.sh" init "task-1" "feature/test-branch")
assert_ok $? "delivery_init creates entry"
assert_contains "$output" '"state": "WORKING"' "Initial state is WORKING"
assert_contains "$output" '"branch": "feature/test-branch"' "Branch is set"
assert_contains "$output" '"taskId": "task-1"' "Task ID is set"

# Test get
output=$(bash "$PIPELINE_DIR/delivery-state.sh" get "task-1")
assert_ok $? "delivery_get retrieves entry"
assert_contains "$output" '"state": "WORKING"' "Get returns correct state"

# Test valid transition
output=$(bash "$PIPELINE_DIR/delivery-state.sh" transition "task-1" "PR_CREATING")
assert_ok $? "Valid transition WORKING → PR_CREATING"

output=$(bash "$PIPELINE_DIR/delivery-state.sh" get "task-1")
assert_contains "$output" '"state": "PR_CREATING"' "State updated to PR_CREATING"

# Test full valid transition chain
bash "$PIPELINE_DIR/delivery-state.sh" transition "task-1" "CI_RUNNING" >/dev/null
assert_ok $? "Valid transition PR_CREATING → CI_RUNNING"

bash "$PIPELINE_DIR/delivery-state.sh" transition "task-1" "REVIEWING" >/dev/null
assert_ok $? "Valid transition CI_RUNNING → REVIEWING"

bash "$PIPELINE_DIR/delivery-state.sh" transition "task-1" "APPROVED" >/dev/null
assert_ok $? "Valid transition REVIEWING → APPROVED"

bash "$PIPELINE_DIR/delivery-state.sh" transition "task-1" "MERGING" >/dev/null
assert_ok $? "Valid transition APPROVED → MERGING"

bash "$PIPELINE_DIR/delivery-state.sh" transition "task-1" "MERGED" >/dev/null
assert_ok $? "Valid transition MERGING → MERGED"

# Test invalid transition
bash "$PIPELINE_DIR/delivery-state.sh" init "task-2" "feature/test-2" >/dev/null
output=$(bash "$PIPELINE_DIR/delivery-state.sh" transition "task-2" "MERGED" 2>&1 || true)
assert_contains "$output" "Invalid transition" "Rejects invalid transition WORKING → MERGED"

# Test BLOCKED transitions
bash "$PIPELINE_DIR/delivery-state.sh" init "task-3" "feature/blocked" >/dev/null
bash "$PIPELINE_DIR/delivery-state.sh" transition "task-3" "PR_CREATING" >/dev/null
bash "$PIPELINE_DIR/delivery-state.sh" transition "task-3" "CI_RUNNING" >/dev/null
bash "$PIPELINE_DIR/delivery-state.sh" transition "task-3" "BLOCKED" >/dev/null
assert_ok $? "Valid transition CI_RUNNING → BLOCKED"

bash "$PIPELINE_DIR/delivery-state.sh" transition "task-3" "CI_RUNNING" >/dev/null
assert_ok $? "Valid transition BLOCKED → CI_RUNNING (retry)"

# Test list
output=$(bash "$PIPELINE_DIR/delivery-state.sh" list)
assert_ok $? "delivery_list works"

output=$(bash "$PIPELINE_DIR/delivery-state.sh" list --state "MERGED")
assert_contains "$output" "task-1" "Filtered list finds MERGED task"

# Test set-pr
bash "$PIPELINE_DIR/delivery-state.sh" set-pr "task-2" 42 >/dev/null
output=$(bash "$PIPELINE_DIR/delivery-state.sh" get "task-2")
assert_contains "$output" '"prNumber": 42' "set-pr updates PR number"

# Test set-gate
bash "$PIPELINE_DIR/delivery-state.sh" set-gate "task-2" "qa-guardian" "passed" >/dev/null
output=$(bash "$PIPELINE_DIR/delivery-state.sh" get "task-2")
assert_contains "$output" '"qa-guardian": "passed"' "set-gate records gate result"

# Test cleanup
bash "$PIPELINE_DIR/delivery-state.sh" cleanup "task-1" >/dev/null
assert_ok $? "delivery_cleanup works"
output=$(bash "$PIPELINE_DIR/delivery-state.sh" get "task-1" 2>&1 || true)
assert_contains "$output" "No delivery found" "Cleaned up task is gone"

# Test nonexistent task
output=$(bash "$PIPELINE_DIR/delivery-state.sh" get "nonexistent" 2>&1 || true)
assert_contains "$output" "No delivery found" "Get nonexistent task errors"

# ============================================================
echo ""
echo -e "${YELLOW}=== Agent Registry ===${NC}"
# ============================================================

# Test list
output=$(bash "$PIPELINE_DIR/agent-registry.sh" list)
assert_ok $? "agent_list works"
assert_contains "$output" "qa-guardian" "List includes qa-guardian"
assert_contains "$output" "devops-engineer" "List includes devops-engineer"

# Test metadata extraction
output=$(bash "$PIPELINE_DIR/agent-registry.sh" metadata "qa-guardian")
assert_ok $? "agent_get_metadata works"
assert_contains "$output" "name: qa-guardian" "Metadata contains name"
assert_contains "$output" "trigger: always" "Metadata contains trigger"
assert_contains "$output" "blocking: true" "Metadata contains blocking"

# Test prompt extraction
output=$(bash "$PIPELINE_DIR/agent-registry.sh" prompt "qa-guardian")
assert_ok $? "agent_get_prompt works"
assert_contains "$output" "QA Guardian Agent" "Prompt contains agent title"

# Test review mandate extraction
output=$(bash "$PIPELINE_DIR/agent-registry.sh" review-mandate "qa-guardian")
assert_ok $? "agent_get_review_mandate works"
assert_contains "$output" "RESULT: PASS" "Review mandate mentions RESULT: PASS"

# Test devops-engineer metadata
output=$(bash "$PIPELINE_DIR/agent-registry.sh" metadata "devops-engineer")
assert_contains "$output" "blocking: false" "DevOps is non-blocking"

# Test code-simplifier metadata
output=$(bash "$PIPELINE_DIR/agent-registry.sh" metadata "code-simplifier")
assert_contains "$output" "min_lines_changed: 50" "Code simplifier has line threshold"

# Test verify-app metadata
output=$(bash "$PIPELINE_DIR/agent-registry.sh" metadata "verify-app")
assert_contains "$output" "trigger: always" "Verify-app triggers always"
assert_contains "$output" "blocking: true" "Verify-app is blocking"

# Test nonexistent agent
output=$(bash "$PIPELINE_DIR/agent-registry.sh" metadata "nonexistent" 2>&1 || true)
assert_contains "$output" "not found" "Nonexistent agent errors"

# ============================================================
echo ""
echo -e "${YELLOW}=== Config Files ===${NC}"
# ============================================================

# Test gates.yaml exists and has expected structure
file_exists() { [[ -f "$1" ]]; }
file_exists "$CONFIG_DIR/gates.yaml"; assert_ok $? "gates.yaml exists"

output=$(grep 'qa-guardian:' "$CONFIG_DIR/gates.yaml")
assert_ok $? "gates.yaml has qa-guardian section"

output=$(grep 'ci_poll_interval_seconds:' "$CONFIG_DIR/gates.yaml")
assert_ok $? "gates.yaml has CI poll interval"

output=$(grep 'merge_method:' "$CONFIG_DIR/gates.yaml")
assert_ok $? "gates.yaml has merge method"

# Test orchestrator.yaml exists
file_exists "$CONFIG_DIR/orchestrator.yaml"; assert_ok $? "orchestrator.yaml exists"

output=$(grep 'version: 2' "$CONFIG_DIR/orchestrator.yaml")
assert_ok $? "orchestrator.yaml has version 2"

# ============================================================
echo ""
echo -e "${YELLOW}=== PR Manager (parsing only) ===${NC}"
# ============================================================

# Test that pr-manager.sh is parseable
bash -n "$PIPELINE_DIR/pr-manager.sh"
assert_ok $? "pr-manager.sh has valid syntax"

# Test usage output
output=$(bash "$PIPELINE_DIR/pr-manager.sh" 2>&1 || true)
assert_contains "$output" "Usage:" "Shows usage on no args"

# ============================================================
echo ""
echo -e "${YELLOW}=== CI Monitor (parsing only) ===${NC}"
# ============================================================

# Test that ci-monitor.sh is parseable
bash -n "$PIPELINE_DIR/ci-monitor.sh"
assert_ok $? "ci-monitor.sh has valid syntax"

# Test usage output
output=$(bash "$PIPELINE_DIR/ci-monitor.sh" 2>&1 || true)
assert_contains "$output" "Usage:" "Shows usage on no args"

# ============================================================
echo ""
echo -e "${YELLOW}=== Gate Runner (parsing only) ===${NC}"
# ============================================================

# Test that gate-runner.sh is parseable
bash -n "$PIPELINE_DIR/gate-runner.sh"
assert_ok $? "gate-runner.sh has valid syntax"

# Test usage output
output=$(bash "$PIPELINE_DIR/gate-runner.sh" 2>&1 || true)
assert_contains "$output" "Usage:" "Shows usage on no args"

# ============================================================
echo ""
echo -e "${YELLOW}=== Pipeline Runner ===${NC}"
# ============================================================

# Test that run.sh is parseable
bash -n "$PIPELINE_DIR/run.sh"
assert_ok $? "run.sh has valid syntax"

# Test that run.sh can be sourced
(
    # Source in subshell to avoid polluting test environment
    source "$PIPELINE_DIR/run.sh" 2>/dev/null
    # Verify expected functions exist
    declare -f pipeline_run >/dev/null
    assert_ok $? "pipeline_run function exists after sourcing"
    declare -f pipeline_resume >/dev/null
    assert_ok $? "pipeline_resume function exists after sourcing"
    declare -f pipeline_status >/dev/null
    assert_ok $? "pipeline_status function exists after sourcing"
)

# Test usage output (no args → shows usage)
output=$(bash "$PIPELINE_DIR/run.sh" 2>&1 || true)
assert_contains "$output" "Usage:" "Shows usage on no args"

# Test that _emit produces correct output format
(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null
    output=$(_emit "test-task" "PHASE" "CI_RUNNING" "Polling CI...")
    assert_eq "PIPELINE|test-task|PHASE|CI_RUNNING|Polling CI..." "$output" "_emit produces correct pipe-delimited format"
)

# Test that _validate_branch rejects main/master
(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null
    set +e
    _validate_branch "main" 2>/dev/null
    assert_fail $? "_validate_branch rejects main"
    _validate_branch "master" 2>/dev/null
    assert_fail $? "_validate_branch rejects master"
)

# Test merge settings loading (defaults)
(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null
    _load_merge_settings
    assert_eq "squash" "$MERGE_METHOD" "Default merge method is squash"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Orchestrator Scripts (syntax) ===${NC}"
# ============================================================

bash -n "$SCRIPT_DIR/../scripts/orchestrator.sh"
assert_ok $? "orchestrator.sh has valid syntax"

bash -n "$SCRIPT_DIR/../scripts/orchestrator-status.sh"
assert_ok $? "orchestrator-status.sh has valid syntax"

bash -n "$SCRIPT_DIR/../scripts/orchestrator-loop.sh"
assert_ok $? "orchestrator-loop.sh has valid syntax"

bash -n "$SCRIPT_DIR/../scripts/mode-detect.sh"
assert_ok $? "mode-detect.sh has valid syntax"

# ============================================================
echo ""
echo -e "${YELLOW}=== No iTerm References ===${NC}"
# ============================================================

# Verify no iTerm tab/window management references remain
# Exclude: notification-only osascript (display notification), logging.sh, cost-tracker.sh, comments
iterm_refs=$(grep -rn 'tell application "iTerm"\|window-utils\|send_to_tab\|read_tab_output\|write text\|tell tab\|tell current session' "$SCRIPT_DIR/../scripts/" "$SCRIPT_DIR/../pipeline/" 2>/dev/null || echo "")
if [[ -z "$iterm_refs" ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}✓${NC} No iTerm tab/window management references in scripts/ or pipeline/"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAIL_MESSAGES+=("iTerm tab management references found: $iterm_refs")
    echo -e "  ${RED}✗${NC} Found iTerm tab management references:"
    echo "$iterm_refs" | while IFS= read -r line; do
        echo "    $line"
    done
fi

# ============================================================
echo ""
echo -e "${YELLOW}=== Version ===${NC}"
# ============================================================

version=$(cat "$SCRIPT_DIR/../version")
assert_eq "4.0.0-alpha.1" "$version" "version file is 4.0.0-alpha.1"

pkg_version=$(grep '"version"' "$SCRIPT_DIR/../package.json" | head -1 | sed 's/.*"version": "//; s/".*//')
assert_eq "4.0.0-alpha.1" "$pkg_version" "package.json version is 4.0.0-alpha.1"

# ============================================================
echo ""
echo -e "${YELLOW}=== Summary ===${NC}"
# ============================================================

echo ""
echo "Tests: $TESTS_RUN | Passed: $TESTS_PASSED | Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failures:${NC}"
    for msg in "${FAIL_MESSAGES[@]}"; do
        echo -e "  ${RED}✗${NC} $msg"
    done
    exit 1
fi

echo -e "${GREEN}All tests passed!${NC}"
