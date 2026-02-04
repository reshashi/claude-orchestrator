#!/usr/bin/env bash
# Worktree management helper for Claude Code parallel sessions

WORKTREE_BASE="$HOME/.worktrees"

usage() {
    echo "Usage: wt <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create <repo> <name> [base-branch]  Create new worktree"
    echo "  list [repo]                          List worktrees"
    echo "  remove <repo> <name>                 Remove worktree"
    echo "  cd <repo> <name>                     Print cd command for worktree"
    echo "  clean <repo>                         Remove all worktrees for repo"
    echo ""
    echo "Examples:"
    echo "  wt create medicalbills auth-flow main"
    echo "  wt list medicalbills"
    echo "  wt remove medicalbills auth-flow"
}

create_worktree() {
    local repo="$1"
    local name="$2"
    local base="${3:-main}"
    local branch="feature/$name"
    local worktree_path="$WORKTREE_BASE/$repo/$name"
    
    if [ -z "$repo" ] || [ -z "$name" ]; then
        echo "Error: repo and name required"
        usage
        exit 1
    fi
    
    mkdir -p "$WORKTREE_BASE/$repo"
    
    echo "Creating worktree: $worktree_path"
    echo "Branch: $branch (from $base)"
    
    git worktree add -b "$branch" "$worktree_path" "$base"
    
    echo ""
    echo "✓ Worktree created!"
    echo ""
    echo "To start working:"
    echo "  cd $worktree_path && claude"
}

list_worktrees() {
    local repo="$1"
    
    if [ -n "$repo" ]; then
        echo "Worktrees for $repo:"
        ls -la "$WORKTREE_BASE/$repo" 2>/dev/null || echo "  (none)"
    else
        echo "All worktrees:"
        git worktree list
    fi
}

remove_worktree() {
    local repo="$1"
    local name="$2"
    local worktree_path="$WORKTREE_BASE/$repo/$name"
    local branch="feature/$name"
    
    if [ -z "$repo" ] || [ -z "$name" ]; then
        echo "Error: repo and name required"
        usage
        exit 1
    fi
    
    echo "Removing worktree: $worktree_path"
    git worktree remove "$worktree_path" --force 2>/dev/null || true
    git branch -D "$branch" 2>/dev/null || true
    rm -rf "$worktree_path" 2>/dev/null || true
    
    echo "✓ Worktree removed"
}

case "$1" in
    create)
        create_worktree "$2" "$3" "$4"
        ;;
    list)
        list_worktrees "$2"
        ;;
    remove)
        remove_worktree "$2" "$3"
        ;;
    cd)
        echo "cd $WORKTREE_BASE/$2/$3"
        ;;
    clean)
        if [ -n "$2" ]; then
            echo "Removing all worktrees for $2..."
            rm -rf "${WORKTREE_BASE:?}/${2:?}"
            echo "✓ Cleaned"
        fi
        ;;
    *)
        usage
        ;;
esac
