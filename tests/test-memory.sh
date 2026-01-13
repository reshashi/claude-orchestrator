#!/bin/bash
# Tests for memory system scripts
# Run with: ./tests/test-memory.sh

# Don't use set -e because arithmetic expressions can return non-zero

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Test directory (use temp dir to avoid polluting real memory)
export CLAUDE_MEMORY_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"

trap "rm -rf $CLAUDE_MEMORY_DIR" EXIT

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    echo "  Expected: $2"
    echo "  Got: $3"
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    "$@"
}

# =============================================================================
# memory-write.sh tests
# =============================================================================

test_write_creates_memory_dir() {
    rm -rf "$CLAUDE_MEMORY_DIR"
    "$SCRIPT_DIR/memory-write.sh" fact "test fact" >/dev/null 2>&1
    if [[ -d "$CLAUDE_MEMORY_DIR" ]]; then
        pass "memory-write.sh creates memory directory if not exists"
    else
        fail "memory-write.sh creates memory directory" "directory exists" "directory missing"
    fi
}

test_write_fact() {
    "$SCRIPT_DIR/memory-write.sh" fact "Test fact for unit testing" >/dev/null 2>&1
    if grep -q "Test fact for unit testing" "$CLAUDE_MEMORY_DIR/facts.json"; then
        pass "memory-write.sh fact stores fact in facts.json"
    else
        fail "memory-write.sh fact" "fact in facts.json" "fact not found"
    fi
}

test_write_toolchain() {
    "$SCRIPT_DIR/memory-write.sh" toolchain test-tool '{"repo": "https://example.com/test"}' >/dev/null 2>&1
    if grep -q "test-tool" "$CLAUDE_MEMORY_DIR/toolchain.json" && grep -q "example.com" "$CLAUDE_MEMORY_DIR/toolchain.json"; then
        pass "memory-write.sh toolchain stores tool in toolchain.json"
    else
        fail "memory-write.sh toolchain" "tool in toolchain.json" "tool not found"
    fi
}

test_write_repos() {
    "$SCRIPT_DIR/memory-write.sh" repos test-repo '{"url": "https://github.com/test/repo"}' >/dev/null 2>&1
    if grep -q "test-repo" "$CLAUDE_MEMORY_DIR/repos.json" && grep -q "github.com/test/repo" "$CLAUDE_MEMORY_DIR/repos.json"; then
        pass "memory-write.sh repos stores repo in repos.json"
    else
        fail "memory-write.sh repos" "repo in repos.json" "repo not found"
    fi
}

test_write_invalid_type() {
    if ! "$SCRIPT_DIR/memory-write.sh" invalid_type "test" 2>/dev/null; then
        pass "memory-write.sh rejects invalid type"
    else
        fail "memory-write.sh invalid type" "error exit" "success exit"
    fi
}

# =============================================================================
# memory-read.sh tests
# =============================================================================

test_read_all() {
    # First write some data
    "$SCRIPT_DIR/memory-write.sh" fact "read all test" >/dev/null 2>&1

    output=$("$SCRIPT_DIR/memory-read.sh" all 2>/dev/null)
    if echo "$output" | grep -q "Toolchain" && echo "$output" | grep -q "Facts"; then
        pass "memory-read.sh all shows all memory sections"
    else
        fail "memory-read.sh all" "lists all sections" "incomplete output"
    fi
}

test_read_toolchain() {
    "$SCRIPT_DIR/memory-write.sh" toolchain read-test '{"repo": "https://read-test.com"}' >/dev/null 2>&1
    output=$("$SCRIPT_DIR/memory-read.sh" toolchain read-test 2>/dev/null)
    if echo "$output" | grep -q "read-test.com"; then
        pass "memory-read.sh toolchain [name] reads specific tool"
    else
        fail "memory-read.sh toolchain" "tool data" "not found"
    fi
}

test_read_facts_search() {
    "$SCRIPT_DIR/memory-write.sh" fact "searchable unique phrase xyz123" >/dev/null 2>&1
    output=$("$SCRIPT_DIR/memory-read.sh" facts "xyz123" 2>/dev/null)
    if echo "$output" | grep -q "xyz123"; then
        pass "memory-read.sh facts [search] finds matching facts"
    else
        fail "memory-read.sh facts search" "matching fact" "not found"
    fi
}

test_read_repos() {
    "$SCRIPT_DIR/memory-write.sh" repos read-repo '{"url": "https://github.com/read/repo"}' >/dev/null 2>&1
    output=$("$SCRIPT_DIR/memory-read.sh" repos 2>/dev/null)
    if echo "$output" | grep -q "read-repo"; then
        pass "memory-read.sh repos lists all repos"
    else
        fail "memory-read.sh repos" "repo list" "not found"
    fi
}

# =============================================================================
# session-summary.sh tests
# =============================================================================

test_session_summary_creates_file() {
    # Create a mock git repo for the summary script
    local mock_repo=$(mktemp -d)
    cd "$mock_repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "test" > file.txt
    git add .
    git commit -q -m "Initial commit"

    "$SCRIPT_DIR/session-summary.sh" >/dev/null 2>&1 || true

    if ls "$CLAUDE_MEMORY_DIR/sessions/"*.md >/dev/null 2>&1; then
        pass "session-summary.sh creates summary file in sessions/"
    else
        fail "session-summary.sh" "summary file created" "no file found"
    fi

    cd - >/dev/null
    rm -rf "$mock_repo"
}

# =============================================================================
# Run all tests
# =============================================================================

echo "=========================================="
echo "Memory System Tests"
echo "=========================================="
echo "Using temp memory dir: $CLAUDE_MEMORY_DIR"
echo ""

echo "--- memory-write.sh ---"
run_test test_write_creates_memory_dir
run_test test_write_fact
run_test test_write_toolchain
run_test test_write_repos
run_test test_write_invalid_type

echo ""
echo "--- memory-read.sh ---"
run_test test_read_all
run_test test_read_toolchain
run_test test_read_facts_search
run_test test_read_repos

echo ""
echo "--- session-summary.sh ---"
run_test test_session_summary_creates_file

echo ""
echo "=========================================="
echo "Results: $TESTS_PASSED/$TESTS_RUN tests passed"
echo "=========================================="

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    exit 0
else
    exit 1
fi
