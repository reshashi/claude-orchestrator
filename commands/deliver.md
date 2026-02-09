---
description: Run the delivery pipeline for a branch — CI, quality gates, merge
allowed-tools: Bash(~/.claude/scripts/*:*), Bash(~/.claude-orchestrator/pipeline/*:*), Bash(git:*), Bash(gh:*)
---

# Deliver: Push a branch through the delivery pipeline

## Arguments
$ARGUMENTS - The branch name to deliver (defaults to current branch)

## Instructions

1. Determine the branch to deliver:
   - If $ARGUMENTS is provided, use that branch
   - Otherwise, detect the current branch: `git branch --show-current`
   - Refuse to deliver `main` or `master`

2. Check prerequisites:
   - Branch exists on remote: `git ls-remote --heads origin <branch>`
   - If not pushed, push it: `git push -u origin <branch>`

3. Run the delivery pipeline:
   ```bash
   ~/.claude-orchestrator/pipeline/run.sh <branch> --task-id <branch>
   ```

4. Monitor and report the output:
   - Each line starts with `PIPELINE|<task-id>|<type>|...`
   - Report phase transitions, gate results, and final outcome

5. If the pipeline ends in BLOCKED:
   - Show what failed (CI? which gate?)
   - Suggest next steps (fix CI, address review feedback)

6. If the pipeline ends in MERGED:
   - Confirm the PR number and merge method
   - Clean up local branch if remote was deleted

## Example Output

```
Delivering branch: feat/add-login

  PR #42 created
  CI: polling... passed (2m 15s)
  Gate: qa-guardian — PASS
  Gate: security — PASS
  Merging PR #42 (squash)...

PR #42 merged successfully.
```
