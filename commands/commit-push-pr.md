---
description: Commit current changes, push to remote, and open a PR (Boris's favorite)
allowed-tools: Bash(git:*), Bash(gh:*), Bash(cat:*), Bash(jq:*)
---

# Commit, Push, and Open Pull Request

## Step 0: Branch Guard (MANDATORY)

Before ANY git operation, verify you're on the correct branch:

```bash
BRANCH_GUARD="$HOME/.claude/scripts/branch-guard.sh"
if [ -x "$BRANCH_GUARD" ]; then
    WORKTREE_PATH=$("$BRANCH_GUARD" 2>&1) || {
        echo "$WORKTREE_PATH"
        echo ""
        echo "REFUSING TO COMMIT — wrong branch detected."
        echo "Fix the branch first, then retry /commit-push-pr."
        exit 1
    }
fi
```

If `WORKTREE_PATH` is set (non-empty), use `git -C "$WORKTREE_PATH"` for ALL git commands below.
If empty (no marker found), use plain git commands as usual.

## Current State
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Changed files: !`git diff --name-only`

## Instructions

1. **Run the branch guard above first.** If it fails, STOP and show the error.

2. Review the changes shown above

3. Stage all changes:
   - With worktree: `git -C "$WORKTREE_PATH" add -A`
   - Without worktree: `git add -A`

4. Create a descriptive commit message based on the actual changes (not generic)

5. Commit the changes:
   - With worktree: `git -C "$WORKTREE_PATH" commit -m "..."`
   - Without worktree: `git commit -m "..."`

6. Push to origin (set upstream if needed):
   - With worktree: `git -C "$WORKTREE_PATH" push -u origin HEAD`
   - Without worktree: `git push -u origin HEAD`

7. Create a PR using GitHub CLI with a clear title and description

Use this format for commit messages:
```
<type>(<scope>): <description>

<body if needed>
```

Types: feat, fix, docs, style, refactor, test, chore

**SAFETY**: If `git branch --show-current` returns `main` or `master`, REFUSE to commit.
Double-check the branch name before every git operation.

After creating the PR, output the PR URL so the user can review it.
