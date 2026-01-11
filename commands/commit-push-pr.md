---
description: Commit current changes, push to remote, and open a PR (Boris's favorite)
allowed-tools: Bash(git:*), Bash(gh:*)
---

# Commit, Push, and Open Pull Request

## Current State
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Changed files: !`git diff --name-only`

## Instructions

1. Review the changes shown above
2. Stage all changes: `git add -A`
3. Create a descriptive commit message based on the actual changes (not generic)
4. Commit the changes
5. Push to origin (set upstream if needed): `git push -u origin HEAD`
6. Create a PR using GitHub CLI with a clear title and description

Use this format for commit messages:
```
<type>(<scope>): <description>

<body if needed>
```

Types: feat, fix, docs, style, refactor, test, chore

After creating the PR, output the PR URL so the user can review it.
