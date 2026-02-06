---
description: Create a new worktree and spawn a Claude worker session with a specific task
allowed-tools: Bash(git:*), Bash(mkdir:*), Bash(echo:*), Bash(cat:*), Bash(node:*), Bash(npx:*), Write, Task
---

# Spawn Worker Session

Create an isolated git worktree for parallel development, then start a Claude worker using the Task tool.

**Platform**: Cross-platform (macOS, Linux, Windows)

## Arguments
- $1: Session name (e.g., "auth-flow", "billing-parser")
- $ARGUMENTS: Task description (everything after the session name)

> **Note:** Use `$ARGUMENTS` instead of `$2` for the task description. `$ARGUMENTS` captures
> the full task text even if not quoted, while `$2` only works for properly quoted strings.
>
> Examples:
> - `/spawn auth-flow implement OAuth` → $1="auth-flow", $ARGUMENTS="implement OAuth"
> - `/spawn ui-form "Create login"` → $1="ui-form", $ARGUMENTS="Create login"

## Current Repository
- Repo root: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`

## Quality Requirements (MANDATORY)

**Every worker must run quality gates before creating a PR:**

1. **Before PR Creation**:
   ```bash
   npm run type-check && npm run lint && npm run test
   ```

2. **After PR Merge** (run by orchestrator or main session):
   - `/review` - QA Guardian review
   - `/qcode` - Code simplification

3. **Critical Issues**: Must be fixed before merge
4. **Suggestions**: Added to backlog database via `~/.claude/scripts/backlog.sh`

## Instructions

1. Extract the session name: `$1`
2. Extract the task description: `$ARGUMENTS` (contains everything after session name)

3. Create the worktree:
```bash
REPO_NAME=$(basename $(git rev-parse --show-toplevel))
WORKTREE_PATH="$HOME/.worktrees/$REPO_NAME/$1"
BRANCH_NAME="feature/$1"

mkdir -p "$HOME/.worktrees/$REPO_NAME"
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" HEAD
```

4. Create a session-specific WORKER_CLAUDE.md in the worktree with:

```markdown
# Worker: $1

## Your Task
[Task description from $ARGUMENTS]

## Files You Own (can modify)
- [List specific files/directories]

## Files Off-Limits (do NOT modify)
- [List files this worker must not touch]

## Quality Requirements

Before creating a PR, you MUST:
1. Run: `npm run type-check && npm run lint && npm run test`
2. All checks must pass before creating the PR
3. Use conventional commit format

After your PR is merged, the orchestrator will run:
- `/review` for QA Guardian review
- `/qcode` for code simplification

Any suggestions will be added to the backlog database.

## Coding Standards
Follow the main CLAUDE.md in the repo root for coding standards.
```

5. **Spawn the worker using the Task tool**:

Use the Task tool with an appropriate subagent_type (e.g., "general-purpose") to start the worker:

```
Task tool with:
- prompt: "Work in the worktree at $WORKTREE_PATH. Read WORKER_CLAUDE.md for your task. Complete the task, run quality checks, and create a PR."
- subagent_type: "general-purpose"
```

6. Output confirmation:
```
Worker '$1' spawned!

Session: $1
Branch: feature/$1
Path: ~/.worktrees/[repo]/$1
Task: [task description]

Quality gates will run after PR merge:
- /review (QA Guardian)
- /qcode (Code Simplifier)
```

## Worktree Management

```bash
# List all worktrees
git worktree list

# Remove a worktree after merge
git worktree remove ~/.worktrees/$REPO_NAME/$1

# Prune stale worktrees
git worktree prune
```

## Worker Completion Flow

When a worker completes:
1. Worker runs local checks (type-check, lint, test)
2. Worker creates PR
3. PR gets reviewed/merged
4. Orchestrator runs `/review` and `/qcode` on merged changes
5. Critical issues → fixed immediately
6. Suggestions → added to backlog database
