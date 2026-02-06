#!/usr/bin/env bash
# Install git hooks for automated quality enforcement
#
# Usage:
#   install-hooks.sh                    # Install in current repo
#   install-hooks.sh /path/to/repo      # Install in specified repo
#   install-hooks.sh --uninstall        # Remove hooks

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SOURCE="$SCRIPT_DIR/../templates/hooks"

# Parse arguments
UNINSTALL=false
TARGET_REPO=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --uninstall) UNINSTALL=true; shift ;;
        *) TARGET_REPO="$1"; shift ;;
    esac
done

# Determine target directory
if [ -n "$TARGET_REPO" ]; then
    cd "$TARGET_REPO"
fi

# Verify we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not a git repository${NC}"
    echo "Run this command from within a git repository or specify the path."
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
if [ "$UNINSTALL" = true ]; then
    echo -e "${BLUE}║           UNINSTALLING GIT HOOKS                             ║${NC}"
else
    echo -e "${BLUE}║           INSTALLING GIT HOOKS                               ║${NC}"
fi
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Repository: $REPO_ROOT"
echo ""

if [ "$UNINSTALL" = true ]; then
    # Uninstall hooks
    for hook in pre-commit pre-push post-merge commit-msg; do
        if [ -f "$HOOKS_DIR/$hook" ]; then
            # Check if it's our hook (has orchestrator marker)
            if grep -q "claude-orchestrator" "$HOOKS_DIR/$hook" 2>/dev/null; then
                rm "$HOOKS_DIR/$hook"
                echo -e "${GREEN}✓ Removed $hook${NC}"
            else
                echo -e "${YELLOW}⚠ Skipped $hook (not installed by orchestrator)${NC}"
            fi
        fi
    done
    echo ""
    echo -e "${GREEN}Hooks uninstalled!${NC}"
    exit 0
fi

# Install hooks
if [ ! -d "$HOOKS_SOURCE" ]; then
    echo -e "${RED}Error: Hook templates not found at $HOOKS_SOURCE${NC}"
    exit 1
fi

for hook in pre-commit pre-push post-merge commit-msg; do
    if [ -f "$HOOKS_SOURCE/$hook" ]; then
        # Backup existing hook if it exists and isn't ours
        if [ -f "$HOOKS_DIR/$hook" ]; then
            if ! grep -q "claude-orchestrator" "$HOOKS_DIR/$hook" 2>/dev/null; then
                mv "$HOOKS_DIR/$hook" "$HOOKS_DIR/$hook.backup"
                echo -e "${YELLOW}⚠ Backed up existing $hook to $hook.backup${NC}"
            fi
        fi

        # Copy hook
        cp "$HOOKS_SOURCE/$hook" "$HOOKS_DIR/$hook"
        chmod +x "$HOOKS_DIR/$hook"
        echo -e "${GREEN}✓ Installed $hook${NC}"
    fi
done

# Also create symlinks to auto-review and auto-qcode in .git/hooks for easy access
if [ -f "$SCRIPT_DIR/auto-review.sh" ]; then
    ln -sf "$SCRIPT_DIR/auto-review.sh" "$HOOKS_DIR/auto-review"
    chmod +x "$HOOKS_DIR/auto-review"
    echo -e "${GREEN}✓ Linked auto-review${NC}"
fi

if [ -f "$SCRIPT_DIR/auto-qcode.sh" ]; then
    ln -sf "$SCRIPT_DIR/auto-qcode.sh" "$HOOKS_DIR/auto-qcode"
    chmod +x "$HOOKS_DIR/auto-qcode"
    echo -e "${GREEN}✓ Linked auto-qcode${NC}"
fi

echo ""
echo -e "${GREEN}Git hooks installed successfully!${NC}"
echo ""
echo "Hooks enabled:"
echo "  ${BLUE}pre-commit${NC}  - Type check, lint, test before commit"
echo "  ${BLUE}pre-push${NC}    - Full quality gates before push"
echo "  ${BLUE}post-merge${NC}  - Add TODOs to backlog after merge"
echo "  ${BLUE}commit-msg${NC}  - Enforce conventional commit format"
echo ""
echo "Manual scripts available:"
echo "  ${BLUE}auto-review${NC} - Run '~/.claude/scripts/auto-review.sh'"
echo "  ${BLUE}auto-qcode${NC}  - Run '~/.claude/scripts/auto-qcode.sh --fix'"
echo ""
echo "To bypass hooks (use sparingly):"
echo "  git commit --no-verify"
echo "  git push --no-verify"
