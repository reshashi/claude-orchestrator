---
description: Merge a worker session's branch back to main and clean up the worktree
allowed-tools: Bash(git:*), Bash(rm:*), Bash(gh:*)
---

# Merge Worker Session

Integrate completed work from a worker session back to the main branch.

## Session to Merge
$ARGUMENTS

## Current State
- Main branch: !`git branch --show-current`
- Repo root: !`git rev-parse --show-toplevel`

## Instructions

1. Verify you're in the main repository (not a worktree)

2. Check the worker's branch status:
```bash
REPO_NAME=$(basename $(git rev-parse --show-toplevel))
BRANCH="feature/$1"
WORKTREE_PATH="$HOME/.worktrees/$REPO_NAME/$1"

# Check if worktree exists
git worktree list | grep "$1"

# Check for uncommitted changes in worktree
git -C "$WORKTREE_PATH" status --short
```

3. If there are uncommitted changes, STOP and inform user:
   "Worker '$1' has uncommitted changes. Please commit or stash them first."

4. If clean, proceed with merge:
```bash
# Ensure main is up to date
git fetch origin
git pull origin main

# Merge the feature branch
git merge "$BRANCH" --no-ff -m "Merge $BRANCH: [summary of changes]"
```

5. If merge conflicts occur:
   - List the conflicting files
   - Suggest resolution strategy
   - Do NOT auto-resolve - let the user handle conflicts

6. After successful merge, clean up:
```bash
# Remove the worktree
git worktree remove "$WORKTREE_PATH" --force

# Delete the branch
git branch -d "$BRANCH"

# Update session log
sed -i '' "/$1/d" ~/.claude/active-sessions.log 2>/dev/null || true
```

7. Output summary:
```
✓ Merged: feature/$1 → main

Changes integrated:
- [list key changes from commits]

Cleanup:
- ✓ Worktree removed
- ✓ Branch deleted
- ✓ Session log updated

Remaining active sessions: [count]
```

8. Suggest next steps:
   - Push to origin: `git push origin main`
   - Or create a PR if following that workflow
   - Check `/status` for remaining work
