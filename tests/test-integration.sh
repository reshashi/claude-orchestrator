#!/usr/bin/env bash
# Integration tests for the delivery pipeline
# Exercises the full pipeline_run() with mocked gh/git/claude commands.
# Run: ./tests/test-integration.sh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$SCRIPT_DIR/../pipeline"
CONFIG_DIR="$SCRIPT_DIR/../config"
export ORCHESTRATOR_AGENTS_DIR="$SCRIPT_DIR/../agents"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# File-based counters (work across subshells)
_COUNTER_DIR=$(mktemp -d)
echo "0" > "$_COUNTER_DIR/run"
echo "0" > "$_COUNTER_DIR/passed"
echo "0" > "$_COUNTER_DIR/failed"
: > "$_COUNTER_DIR/fail_messages"

_inc_run()    { echo $(( $(cat "$_COUNTER_DIR/run") + 1 )) > "$_COUNTER_DIR/run"; }
_inc_passed() { echo $(( $(cat "$_COUNTER_DIR/passed") + 1 )) > "$_COUNTER_DIR/passed"; }
_inc_failed() { echo $(( $(cat "$_COUNTER_DIR/failed") + 1 )) > "$_COUNTER_DIR/failed"; }
_add_fail_msg() { echo "$1" >> "$_COUNTER_DIR/fail_messages"; }

# Test helpers (file-backed for subshell compatibility)
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    _inc_run
    if [[ "$expected" == "$actual" ]]; then
        _inc_passed
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        _inc_failed
        _add_fail_msg "$msg: expected '$expected', got '$actual'"
        echo -e "  ${RED}✗${NC} $msg"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
    fi
}

assert_ok() {
    local exit_code="$1" msg="$2"
    _inc_run
    if [[ "$exit_code" -eq 0 ]]; then
        _inc_passed
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        _inc_failed
        _add_fail_msg "$msg: expected exit 0, got $exit_code"
        echo -e "  ${RED}✗${NC} $msg (exit code: $exit_code)"
    fi
}

assert_fail() {
    local exit_code="$1" msg="$2"
    _inc_run
    if [[ "$exit_code" -ne 0 ]]; then
        _inc_passed
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        _inc_failed
        _add_fail_msg "$msg: expected non-zero exit, got 0"
        echo -e "  ${RED}✗${NC} $msg (expected failure, got success)"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    _inc_run
    if echo "$haystack" | grep -qF "$needle"; then
        _inc_passed
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        _inc_failed
        _add_fail_msg "$msg: '$needle' not found in output"
        echo -e "  ${RED}✗${NC} $msg"
        echo "    looking for: '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="$3"
    _inc_run
    if ! echo "$haystack" | grep -qF "$needle"; then
        _inc_passed
        echo -e "  ${GREEN}✓${NC} $msg"
    else
        _inc_failed
        _add_fail_msg "$msg: '$needle' should not be in output"
        echo -e "  ${RED}✗${NC} $msg"
        echo "    should NOT contain: '$needle'"
    fi
}

# ============================================================
# Setup: isolated state + mock commands
# ============================================================

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

MOCK_DIR="$TEMP_DIR/mocks"
mkdir -p "$MOCK_DIR"

export GATES_CONFIG="$CONFIG_DIR/gates.yaml"

# Helper to reset state for each test
reset_state() {
    rm -rf "${TEMP_DIR:?}/state"
    export ORCHESTRATOR_STATE_DIR="$TEMP_DIR/state"
}

# Helper to install default (happy-path) mocks
install_happy_mocks() {
    # gh mock — happy path: no existing PR, create returns 42, CI passes, merge succeeds
    # Note: -q flag in `gh pr view --json X -q '.X'` extracts the value, so mock returns plain numbers
    cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/usr/bin/env bash
# Mock gh CLI for integration tests
case "$*" in
    "auth status")
        exit 0 ;;
    "repo view --json nameWithOwner"*)
        echo '{"nameWithOwner":"test/repo"}' ;;
    *"pr list"*"--state open"*)
        echo "" ;;
    *"pr create"*)
        echo "https://github.com/test/repo/pull/42" ;;
    *"pr view"*"statusCheckRollup"*)
        echo '[{"conclusion":"SUCCESS"}]' ;;
    *"pr view"*"additions"*)
        echo "25" ;;
    *"pr view"*"deletions"*)
        echo "10" ;;
    *"pr diff"*"--name-only"*)
        echo "src/main.ts" ;;
    *"pr diff"*)
        echo "+added line" ;;
    *"pr merge"*)
        echo "Merged" ;;
    *)
        echo "mock gh: unhandled: $*" >&2
        exit 0 ;;
esac
MOCK_GH
    chmod +x "$MOCK_DIR/gh"

    # git mock — branch exists on remote
    cat > "$MOCK_DIR/git" << 'MOCK_GIT'
#!/usr/bin/env bash
case "$*" in
    *"ls-remote"*"--heads"*)
        # Extract branch name from args and report it exists
        echo "abc123 refs/heads/feature/test-branch" ;;
    *)
        echo "mock git: unhandled: $*" >&2
        exit 0 ;;
esac
MOCK_GIT
    chmod +x "$MOCK_DIR/git"

    # claude mock — gate review always passes (consume stdin from pipe)
    cat > "$MOCK_DIR/claude" << 'MOCK_CLAUDE'
#!/usr/bin/env bash
cat > /dev/null
echo "Review looks good. RESULT: PASS"
MOCK_CLAUDE
    chmod +x "$MOCK_DIR/claude"
}

# Prepend mocks to PATH
export PATH="$MOCK_DIR:$PATH"

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: Happy Path ===${NC}"
# ============================================================

reset_state
install_happy_mocks

# Source the pipeline in a subshell to avoid polluting test env
(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null

    output=$(pipeline_run "feature/test-branch" --task-id "happy-1" 2>/dev/null)
    exit_code=$?

    assert_ok $exit_code "Happy path pipeline completes successfully"
    assert_contains "$output" "PIPELINE|happy-1|RESULT|MERGED" "Output shows MERGED result"
    assert_contains "$output" "PR #42" "Output references PR #42"

    # Verify final delivery state
    state_json=$(delivery_get "happy-1" 2>/dev/null)
    state=$(echo "$state_json" | jq -r '.state')
    assert_eq "MERGED" "$state" "Delivery state is MERGED"

    pr_num=$(echo "$state_json" | jq -r '.prNumber')
    assert_eq "42" "$pr_num" "PR number is recorded as 42"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: Existing PR Found ===${NC}"
# ============================================================

reset_state

# Override gh mock to return existing PR
cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
    "auth status") exit 0 ;;
    "repo view --json nameWithOwner"*) echo '{"nameWithOwner":"test/repo"}' ;;
    *"pr list"*"--state open"*)
        echo "42" ;;
    *"pr create"*)
        echo "ERROR: should not create PR" >&2; exit 1 ;;
    *"pr view"*"statusCheckRollup"*)
        echo '[{"conclusion":"SUCCESS"}]' ;;
    *"pr view"*"additions"*) echo "25" ;;
    *"pr view"*"deletions"*) echo "10" ;;
    *"pr diff"*"--name-only"*) echo "src/main.ts" ;;
    *"pr diff"*) echo "+added line" ;;
    *"pr merge"*) echo "Merged" ;;
    *) exit 0 ;;
esac
MOCK_GH
chmod +x "$MOCK_DIR/gh"

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null

    output=$(pipeline_run "feature/test-branch" --task-id "existing-pr-1" 2>/dev/null)
    exit_code=$?

    assert_ok $exit_code "Existing PR path completes successfully"
    assert_contains "$output" "PIPELINE|existing-pr-1|RESULT|MERGED" "Skips PR creation, still merges"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: CI Failure ===${NC}"
# ============================================================

reset_state

# Override gh mock — CI fails
cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
    "auth status") exit 0 ;;
    "repo view --json nameWithOwner"*) echo '{"nameWithOwner":"test/repo"}' ;;
    *"pr list"*"--state open"*) echo "" ;;
    *"pr create"*) echo "https://github.com/test/repo/pull/42" ;;
    *"pr view"*"statusCheckRollup"*)
        echo '[{"conclusion":"FAILURE"}]' ;;
    *"pr view"*"additions"*) echo "25" ;;
    *"pr view"*"deletions"*) echo "10" ;;
    *"pr diff"*"--name-only"*) echo "src/main.ts" ;;
    *"pr diff"*) echo "+added line" ;;
    *"pr merge"*) echo "Merged" ;;
    *) exit 0 ;;
esac
MOCK_GH
chmod +x "$MOCK_DIR/gh"

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null
    set +e

    output=$(pipeline_run "feature/test-branch" --task-id "ci-fail-1" 2>/dev/null)
    exit_code=$?

    assert_fail $exit_code "CI failure causes pipeline to fail"
    assert_contains "$output" "BLOCKED" "Output shows BLOCKED on CI failure"

    state_json=$(delivery_get "ci-fail-1" 2>/dev/null)
    state=$(echo "$state_json" | jq -r '.state')
    assert_eq "BLOCKED" "$state" "Delivery state is BLOCKED after CI failure"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: CI Timeout ===${NC}"
# ============================================================

reset_state

# Override gh mock — CI stays pending (timeout quickly with override)
cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
    "auth status") exit 0 ;;
    "repo view --json nameWithOwner"*) echo '{"nameWithOwner":"test/repo"}' ;;
    *"pr list"*"--state open"*) echo "" ;;
    *"pr create"*) echo "https://github.com/test/repo/pull/42" ;;
    *"pr view"*"statusCheckRollup"*) echo '[]' ;;
    *"pr view"*"additions"*) echo "25" ;;
    *"pr view"*"deletions"*) echo "10" ;;
    *) exit 0 ;;
esac
MOCK_GH
chmod +x "$MOCK_DIR/gh"

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null
    set +e

    # Override ci_poll to simulate timeout quickly (avoid real sleep)
    ci_poll() {
        echo "timeout"
        return 2
    }

    output=$(pipeline_run "feature/test-branch" --task-id "ci-timeout-1" 2>/dev/null)
    exit_code=$?

    assert_fail $exit_code "CI timeout causes pipeline to fail"
    assert_contains "$output" "BLOCKED" "Output shows BLOCKED on CI timeout"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: Blocking Gate Failure ===${NC}"
# ============================================================

reset_state
install_happy_mocks

# Override claude mock — gate fails
cat > "$MOCK_DIR/claude" << 'MOCK_CLAUDE'
#!/usr/bin/env bash
cat > /dev/null
echo "Issues found. RESULT: FAIL"
MOCK_CLAUDE
chmod +x "$MOCK_DIR/claude"

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null
    set +e

    output=$(pipeline_run "feature/test-branch" --task-id "gate-fail-1" 2>/dev/null)
    exit_code=$?

    assert_fail $exit_code "Blocking gate failure causes pipeline to fail"
    assert_contains "$output" "BLOCKED" "Output shows BLOCKED on gate failure"

    state_json=$(delivery_get "gate-fail-1" 2>/dev/null)
    state=$(echo "$state_json" | jq -r '.state')
    assert_eq "BLOCKED" "$state" "Delivery state is BLOCKED after gate failure"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: Non-blocking Gate Failure ===${NC}"
# ============================================================

reset_state

# We need a mock that makes only non-blocking gates fail.
# qa-guardian and verify-app are blocking; devops-engineer and code-simplifier are not.
# The pipeline calls `claude --print` for each gate.
# We'll make claude pass, but override run_gate to fail for non-blocking only.

install_happy_mocks

# Restore claude to passing
cat > "$MOCK_DIR/claude" << 'MOCK_CLAUDE'
#!/usr/bin/env bash
cat > /dev/null
echo "Looks good. RESULT: PASS"
MOCK_CLAUDE
chmod +x "$MOCK_DIR/claude"

# For non-blocking gate failure, we need devops-engineer or code-simplifier to trigger.
# devops-engineer triggers on files_match (infra files), code-simplifier on min_lines_changed >= 50
# Our mock gh returns additions=25, deletions=10 (total=35), and file "src/main.ts"
# So neither non-blocking gate triggers by default — both are skipped.
# To test non-blocking failure, override gh to return enough lines (60+) and an infra file

cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
    "auth status") exit 0 ;;
    "repo view --json nameWithOwner"*) echo '{"nameWithOwner":"test/repo"}' ;;
    *"pr list"*"--state open"*) echo "" ;;
    *"pr create"*) echo "https://github.com/test/repo/pull/42" ;;
    *"pr view"*"statusCheckRollup"*) echo '[{"conclusion":"SUCCESS"}]' ;;
    *"pr view"*"additions"*) echo "60" ;;
    *"pr view"*"deletions"*) echo "10" ;;
    *"pr diff"*"--name-only"*) printf "src/main.ts\n.github/workflows/ci.yml\n" ;;
    *"pr diff"*) echo "+added line" ;;
    *"pr merge"*) echo "Merged" ;;
    *) exit 0 ;;
esac
MOCK_GH
chmod +x "$MOCK_DIR/gh"

# Make claude mock return PASS for blocking agents, FAIL for non-blocking
# We use a counter file to track which invocation we're on
cat > "$MOCK_DIR/claude" << 'MOCK_CLAUDE'
#!/usr/bin/env bash
# Always pass — non-blocking gate failure is tested by overriding run_gate instead
cat > /dev/null
echo "Looks good. RESULT: PASS"
MOCK_CLAUDE
chmod +x "$MOCK_DIR/claude"

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null

    # Override run_gate to make non-blocking gates fail
    _orig_gate_blocking=$(_gate_blocking 2>/dev/null || true)
    run_gate() {
        local agent_name="$1"
        if _gate_blocking "$agent_name" 2>/dev/null; then
            echo "RESULT: PASS"
            return 0
        else
            echo "RESULT: FAIL"
            return 1
        fi
    }

    output=$(pipeline_run "feature/test-branch" --task-id "nonblock-1" 2>/dev/null)
    exit_code=$?

    assert_ok $exit_code "Non-blocking gate failure still allows merge"
    assert_contains "$output" "MERGED" "Pipeline proceeds to MERGED despite non-blocking failure"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: --no-merge Flag ===${NC}"
# ============================================================

reset_state
install_happy_mocks

# Restore default claude mock (passing)
cat > "$MOCK_DIR/claude" << 'MOCK_CLAUDE'
#!/usr/bin/env bash
cat > /dev/null
echo "Looks good. RESULT: PASS"
MOCK_CLAUDE
chmod +x "$MOCK_DIR/claude"

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null

    output=$(pipeline_run "feature/test-branch" --task-id "nomerge-1" --no-merge 2>/dev/null)
    exit_code=$?

    assert_ok $exit_code "--no-merge pipeline completes successfully"
    assert_contains "$output" "APPROVED" "Output shows APPROVED (not MERGED)"
    assert_not_contains "$output" "PIPELINE|nomerge-1|RESULT|MERGED" "Does NOT show MERGED"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: Resume from BLOCKED ===${NC}"
# ============================================================

reset_state
install_happy_mocks

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null

    # Manually set up a BLOCKED delivery
    delivery_init "resume-blocked-1" "feature/test-branch" >/dev/null
    delivery_transition "resume-blocked-1" "PR_CREATING" >/dev/null
    delivery_transition "resume-blocked-1" "CI_RUNNING" >/dev/null
    delivery_transition "resume-blocked-1" "BLOCKED" >/dev/null

    # Resume should re-run from beginning
    output=$(pipeline_resume "resume-blocked-1" 2>/dev/null)
    exit_code=$?

    assert_ok $exit_code "Resume from BLOCKED completes"
    assert_contains "$output" "MERGED" "Resume from BLOCKED eventually reaches MERGED"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: Resume from CI_RUNNING ===${NC}"
# ============================================================

reset_state
install_happy_mocks

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null

    # Set up a CI_RUNNING delivery with PR number
    delivery_init "resume-ci-1" "feature/test-branch" >/dev/null
    delivery_transition "resume-ci-1" "PR_CREATING" >/dev/null
    delivery_set_pr "resume-ci-1" 42 >/dev/null
    delivery_transition "resume-ci-1" "CI_RUNNING" >/dev/null

    output=$(pipeline_resume "resume-ci-1" 2>/dev/null)
    exit_code=$?

    assert_ok $exit_code "Resume from CI_RUNNING completes"

    state_json=$(delivery_get "resume-ci-1" 2>/dev/null)
    state=$(echo "$state_json" | jq -r '.state')
    assert_eq "MERGED" "$state" "Delivery state reaches MERGED after CI resume"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: Output Protocol ===${NC}"
# ============================================================

reset_state
install_happy_mocks

# Restore default claude mock (passing)
cat > "$MOCK_DIR/claude" << 'MOCK_CLAUDE'
#!/usr/bin/env bash
cat > /dev/null
echo "Looks good. RESULT: PASS"
MOCK_CLAUDE
chmod +x "$MOCK_DIR/claude"

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null

    output=$(pipeline_run "feature/test-branch" --task-id "protocol-1" 2>/dev/null)

    # Verify structured output format
    assert_contains "$output" "PIPELINE|protocol-1|PHASE|" "Output has PHASE entries"
    assert_contains "$output" "PIPELINE|protocol-1|RESULT|" "Output has RESULT entry"

    # Verify pipe-delimited format (5 fields)
    result_line=$(echo "$output" | grep "PIPELINE|protocol-1|RESULT|" | head -1)
    field_count=$(echo "$result_line" | awk -F'|' '{print NF}')
    assert_eq "5" "$field_count" "RESULT line has 5 pipe-delimited fields"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Integration: Branch Validation ===${NC}"
# ============================================================

reset_state
install_happy_mocks

(
    source "$PIPELINE_DIR/run.sh" 2>/dev/null
    set +e

    output=$(pipeline_run "main" --task-id "reject-main" 2>/dev/null)
    exit_code=$?

    assert_fail $exit_code "Pipeline rejects main branch"
)

# ============================================================
echo ""
echo -e "${YELLOW}=== Summary ===${NC}"
# ============================================================

TESTS_RUN=$(cat "$_COUNTER_DIR/run")
TESTS_PASSED=$(cat "$_COUNTER_DIR/passed")
TESTS_FAILED=$(cat "$_COUNTER_DIR/failed")

echo ""
echo "Tests: $TESTS_RUN | Passed: $TESTS_PASSED | Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failures:${NC}"
    while IFS= read -r msg; do
        [[ -z "$msg" ]] && continue
        echo -e "  ${RED}✗${NC} $msg"
    done < "$_COUNTER_DIR/fail_messages"
    rm -rf "$_COUNTER_DIR"
    exit 1
fi

rm -rf "$_COUNTER_DIR"
echo -e "${GREEN}All integration tests passed!${NC}"
