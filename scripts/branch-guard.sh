#!/usr/bin/env bash
# Branch guard: Prevents git operations on the wrong branch in worktree sessions
#
# Walks up from $PWD (or --dir) to find .claude-worktree marker.
# Compares expected branch with actual git branch.
# Blocks if mismatched or on a protected branch (main/master).
#
# Usage: branch-guard.sh [--check-only] [--dir <path>]
#   --check-only   Validate only; don't print worktree path on success
#   --dir <path>   Start search from <path> instead of $PWD
#
# Exit codes:
#   0 = OK (branch matches, or no marker found)
#   1 = BLOCKED (mismatch or on protected branch with marker)
#
# On success (without --check-only), prints the worktree path to stdout.

set -eo pipefail

# --- Defaults ---
CHECK_ONLY=false
SEARCH_DIR=""

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-only) CHECK_ONLY=true; shift ;;
        --dir) SEARCH_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: branch-guard.sh [--check-only] [--dir <path>]"
            echo ""
            echo "Walks up from \$PWD to find .claude-worktree marker."
            echo "Blocks git operations if on the wrong branch."
            echo ""
            echo "Options:"
            echo "  --check-only   Validate only; don't print worktree path"
            echo "  --dir <path>   Start search from <path> instead of \$PWD"
            echo ""
            echo "Exit 0 = OK, Exit 1 = BLOCKED"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

SEARCH_DIR="${SEARCH_DIR:-$PWD}"

# --- find_marker: walk up directory tree looking for .claude-worktree ---
find_marker() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.claude-worktree" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# --- Main ---

# Find the marker file
MARKER_DIR=""
MARKER_DIR=$(find_marker "$SEARCH_DIR") || true

if [[ -z "$MARKER_DIR" ]]; then
    # No marker found — not in a worktree session, allow everything
    exit 0
fi

MARKER_FILE="$MARKER_DIR/.claude-worktree"

# Read expected branch from marker
EXPECTED_BRANCH=""
if command -v jq &>/dev/null; then
    EXPECTED_BRANCH=$(jq -r '.branch // empty' "$MARKER_FILE" 2>/dev/null)
else
    # Fallback: grep for "branch" field
    EXPECTED_BRANCH=$(grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$MARKER_FILE" | head -1 | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//; s/"//')
fi

if [[ -z "$EXPECTED_BRANCH" ]]; then
    echo "WARNING: .claude-worktree marker found at $MARKER_DIR but has no branch field" >&2
    exit 0
fi

# Get actual branch
ACTUAL_BRANCH=$(git -C "$MARKER_DIR" branch --show-current 2>/dev/null || echo "")

if [[ -z "$ACTUAL_BRANCH" ]]; then
    echo "ERROR: Could not determine current git branch in $MARKER_DIR" >&2
    exit 1
fi

# Check: on a protected branch with a worktree marker means something is wrong
if [[ "$ACTUAL_BRANCH" == "main" || "$ACTUAL_BRANCH" == "master" ]]; then
    echo "BLOCKED: You are on '$ACTUAL_BRANCH' but .claude-worktree expects '$EXPECTED_BRANCH'" >&2
    echo "" >&2
    echo "Recovery:" >&2
    echo "  cd $MARKER_DIR" >&2
    echo "  git checkout $EXPECTED_BRANCH" >&2
    exit 1
fi

# Check: branch mismatch
if [[ "$ACTUAL_BRANCH" != "$EXPECTED_BRANCH" ]]; then
    echo "BLOCKED: Branch mismatch — expected '$EXPECTED_BRANCH', currently on '$ACTUAL_BRANCH'" >&2
    echo "" >&2
    echo "Recovery:" >&2
    echo "  cd $MARKER_DIR" >&2
    echo "  git checkout $EXPECTED_BRANCH" >&2
    exit 1
fi

# All checks passed
if [[ "$CHECK_ONLY" == "false" ]]; then
    echo "$MARKER_DIR"
fi

exit 0
