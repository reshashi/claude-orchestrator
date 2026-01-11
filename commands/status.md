---
description: Check status of all active worktrees and Claude sessions
allowed-tools: Bash(git:*), Bash(cat:*), Bash(ls:*)
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

5. Suggest next actions:
   - `/merge [session]` for completed work
   - Check on sessions with no activity
   - Remove stale worktrees with `wt remove [repo] [session]`
