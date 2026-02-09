---
description: Check status of all active worktrees, delivery pipeline, and Claude sessions
allowed-tools: Bash(git:*), Bash(cat:*), Bash(ls:*), Bash(~/.claude-orchestrator/pipeline/*:*), Bash(~/.claude/scripts/orchestrator-status.sh:*)
---

# Status: Active Sessions Overview

## Active Worktrees
!`git worktree list`

## Session Log
!`cat ~/.claude/active-sessions.log 2>/dev/null || echo "(no sessions logged)"`

## Instructions

1. Parse the worktree list and session log
2. For each active worktree, check:
   - Branch name
   - Last commit (if any): `git -C [path] log --oneline -1 2>/dev/null`
   - Working directory status: `git -C [path] status --short 2>/dev/null`
   - Whether it has uncommitted changes

3. Present a summary table:

```
┌─────────────────────────────────────────────────────────────────┐
│ Active Claude Workers                                           │
├──────────────┬─────────────────┬──────────┬────────────────────┤
│ Session      │ Branch          │ Status   │ Last Activity      │
├──────────────┼─────────────────┼──────────┼────────────────────┤
│ auth-flow    │ feature/auth    │ 3 files  │ 2 commits ahead    │
│ billing      │ feature/billing │ clean    │ ready to merge     │
│ api-tests    │ feature/tests   │ 1 file   │ in progress        │
└──────────────┴─────────────────┴──────────┴────────────────────┘
```

4. Provide recommendations:
   - Sessions ready to merge (clean, with commits)
   - Sessions that might be stuck (no recent changes)
   - Potential conflicts (multiple sessions touched similar files)

5. Show delivery pipeline status:
   - Run: `~/.claude-orchestrator/pipeline/delivery-state.sh list`
   - Present active deliveries in a table:

```
┌─────────────────────────────────────────────────────────────────┐
│ Delivery Pipeline                                                │
├─────────────────┬────────┬──────────────┬───────────────────────┤
│ Branch          │ PR     │ State        │ Last Update           │
├─────────────────┼────────┼──────────────┼───────────────────────┤
│ feat/auth       │ #42    │ REVIEWING    │ 2 min ago             │
│ fix/login       │ #43    │ CI_RUNNING   │ 5 min ago             │
│ feat/dashboard  │ #44    │ MERGED       │ 1 hour ago            │
└─────────────────┴────────┴──────────────┴───────────────────────┘
```

6. Suggest next actions:
   - `/deliver [branch]` to push a branch through the pipeline
   - `/merge [session]` for completed work
   - Check on sessions with no activity
   - Remove stale worktrees with `wt remove [repo] [session]`
