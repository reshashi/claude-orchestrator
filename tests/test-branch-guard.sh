#!/usr/bin/env bash
# Tests for scripts/branch-guard.sh
# Run: ./tests/test-branch-guard.sh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/../scripts/branch-guard.sh"

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_MESSAGES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test helpers
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
        echo "    in: '$haystack'"
    fi
}

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

# --- Setup temp git repo ---
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

setup_git_repo() {
    local dir="$1"
    git -C "$dir" init -b main >/dev/null 2>&1
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/README.md"
    git -C "$dir" add -A >/dev/null 2>&1
    git -C "$dir" commit -m "init" >/dev/null 2>&1
}

write_marker() {
    local dir="$1" branch="$2"
    cat > "$dir/.claude-worktree" << JSONEOF
{
  "branch": "$branch",
  "created_at": "2026-01-01T00:00:00Z",
  "project_id": "test"
}
JSONEOF
}

# ============================================================
echo ""
echo -e "${YELLOW}=== Branch Guard: Syntax ===${NC}"
# ============================================================

bash -n "$GUARD_SCRIPT"
assert_ok $? "branch-guard.sh has valid syntax"

output=$(bash "$GUARD_SCRIPT" --help 2>&1)
assert_ok $? "branch-guard.sh --help exits 0"
assert_contains "$output" "Usage:" "--help shows usage"

# ============================================================
echo ""
echo -e "${YELLOW}=== Branch Guard: No Marker (allow) ===${NC}"
# ============================================================

REPO1="$TEMP_DIR/repo-no-marker"
mkdir -p "$REPO1"
setup_git_repo "$REPO1"

output=$(bash "$GUARD_SCRIPT" --dir "$REPO1" 2>&1)
assert_ok $? "No marker → allow (exit 0)"

# ============================================================
echo ""
echo -e "${YELLOW}=== Branch Guard: Correct Branch (allow + print path) ===${NC}"
# ============================================================

REPO2="$TEMP_DIR/repo-correct"
mkdir -p "$REPO2"
setup_git_repo "$REPO2"
git -C "$REPO2" checkout -b "feature/test-task" >/dev/null 2>&1
write_marker "$REPO2" "feature/test-task"

output=$(bash "$GUARD_SCRIPT" --dir "$REPO2" 2>&1)
assert_ok $? "Correct branch → allow (exit 0)"
assert_eq "$REPO2" "$output" "Prints worktree path on success"

# --check-only should NOT print path
output=$(bash "$GUARD_SCRIPT" --check-only --dir "$REPO2" 2>&1)
assert_ok $? "--check-only correct branch → allow (exit 0)"
assert_eq "" "$output" "--check-only produces no stdout"

# ============================================================
echo ""
echo -e "${YELLOW}=== Branch Guard: Wrong Branch (reject) ===${NC}"
# ============================================================

REPO3="$TEMP_DIR/repo-wrong"
mkdir -p "$REPO3"
setup_git_repo "$REPO3"
git -C "$REPO3" checkout -b "feature/wrong-branch" >/dev/null 2>&1
write_marker "$REPO3" "feature/correct-branch"

set +e
output=$(bash "$GUARD_SCRIPT" --dir "$REPO3" 2>&1)
exit_code=$?
set -e

assert_fail "$exit_code" "Wrong branch → reject (exit 1)"
assert_contains "$output" "BLOCKED" "Output says BLOCKED"
assert_contains "$output" "feature/correct-branch" "Shows expected branch"
assert_contains "$output" "Recovery:" "Shows recovery instructions"

# ============================================================
echo ""
echo -e "${YELLOW}=== Branch Guard: On main With Marker (reject) ===${NC}"
# ============================================================

REPO4="$TEMP_DIR/repo-on-main"
mkdir -p "$REPO4"
setup_git_repo "$REPO4"
# Stay on main, but place a marker expecting a feature branch
write_marker "$REPO4" "feature/should-be-here"

set +e
output=$(bash "$GUARD_SCRIPT" --dir "$REPO4" 2>&1)
exit_code=$?
set -e

assert_fail "$exit_code" "On main with marker → reject (exit 1)"
assert_contains "$output" "BLOCKED" "Output says BLOCKED on main"
assert_contains "$output" "main" "Mentions current branch 'main'"

# ============================================================
echo ""
echo -e "${YELLOW}=== Branch Guard: Walk-Up Discovery ===${NC}"
# ============================================================

REPO5="$TEMP_DIR/repo-walkup"
mkdir -p "$REPO5"
setup_git_repo "$REPO5"
git -C "$REPO5" checkout -b "feature/deep-task" >/dev/null 2>&1
write_marker "$REPO5" "feature/deep-task"

# Create a nested subdirectory
SUBDIR="$REPO5/src/components/deep"
mkdir -p "$SUBDIR"

output=$(bash "$GUARD_SCRIPT" --dir "$SUBDIR" 2>&1)
assert_ok $? "Walk-up from nested dir → finds marker and allows"
assert_eq "$REPO5" "$output" "Walk-up prints correct worktree root"

# ============================================================
echo ""
echo -e "${YELLOW}=== Branch Guard: Walk-Up Wrong Branch ===${NC}"
# ============================================================

REPO6="$TEMP_DIR/repo-walkup-wrong"
mkdir -p "$REPO6"
setup_git_repo "$REPO6"
git -C "$REPO6" checkout -b "feature/actual" >/dev/null 2>&1
write_marker "$REPO6" "feature/expected"

SUBDIR6="$REPO6/lib/utils"
mkdir -p "$SUBDIR6"

set +e
output=$(bash "$GUARD_SCRIPT" --dir "$SUBDIR6" 2>&1)
exit_code=$?
set -e

assert_fail "$exit_code" "Walk-up wrong branch → reject"
assert_contains "$output" "BLOCKED" "Walk-up wrong branch output says BLOCKED"

# ============================================================
echo ""
echo -e "${YELLOW}=== Branch Guard: Master Branch Protection ===${NC}"
# ============================================================

REPO7="$TEMP_DIR/repo-master"
mkdir -p "$REPO7"
git -C "$REPO7" init -b master >/dev/null 2>&1
git -C "$REPO7" config user.email "test@test.com"
git -C "$REPO7" config user.name "Test"
echo "init" > "$REPO7/README.md"
git -C "$REPO7" add -A >/dev/null 2>&1
git -C "$REPO7" commit -m "init" >/dev/null 2>&1
write_marker "$REPO7" "feature/some-task"

set +e
output=$(bash "$GUARD_SCRIPT" --dir "$REPO7" 2>&1)
exit_code=$?
set -e

assert_fail "$exit_code" "On master with marker → reject (exit 1)"
assert_contains "$output" "BLOCKED" "Output says BLOCKED on master"

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

echo -e "${GREEN}All branch guard tests passed!${NC}"
