---
description: Deployment checklist and status using DevOps Engineer agent
allowed-tools: Bash(git:*), Bash(npm:*), Bash(vercel:*), Bash(supabase:*), Bash(gh:*), Read, Grep, Glob
---

# Deployment Status (DevOps Engineer)

You are invoking the DevOps Engineer agent to check deployment readiness and status.

## Context Gathering

### Current Branch and Status
!`git branch --show-current`
!`git status --short`
!`git log --oneline -5`

### Environment
!`echo "Vercel Project:" && vercel ls 2>/dev/null | head -5 || echo "Vercel CLI not configured"`

### Database Status
!`supabase migration list 2>/dev/null | tail -10 || echo "Supabase CLI not configured"`

## Pre-Flight Checks

Run these checks before deployment:

### 1. Static Analysis
```bash
npm run type-check
npm run lint
```

### 2. Test Suite
```bash
npm run test
```

### 3. Build Verification
```bash
npm run build
```

### 4. Security Audit
```bash
npm audit --audit-level=high
```

## Your Task

As the DevOps Engineer, assess deployment readiness:

### For Staging (feature → staging)
1. All pre-flight checks pass
2. No pending migrations that could break staging
3. Feature is complete and tested locally
4. PR created and CI passes

### For Production (staging → master)
1. Feature tested on staging (medicalbills.co)
2. No critical bugs found during QA
3. All migrations applied to staging successfully
4. PR approved by at least 1 reviewer

## Output Format

```
╔══════════════════════════════════════════════════════════════╗
║ DEPLOYMENT STATUS                                            ║
╠══════════════════════════════════════════════════════════════╣
║ Environment: [STAGING/PRODUCTION]                            ║
║ Branch: [branch-name]                                        ║
║ Commit: [short-hash]                                         ║
╠══════════════════════════════════════════════════════════════╣
║ Pre-Flight Checks                                            ║
╠══════════════════════════════════════════════════════════════╣
║ [✓/✗] Type-check: [status]                                   ║
║ [✓/✗] Lint: [status]                                         ║
║ [✓/✗] Unit Tests: [status]                                   ║
║ [✓/⚠] E2E Tests: [status or SKIPPED if not in CI]           ║
║ [✓/✗] Build: [status]                                        ║
║ [✓/⚠] Security Audit: [status]                               ║
╠══════════════════════════════════════════════════════════════╣
║ Infrastructure Status                                        ║
╠══════════════════════════════════════════════════════════════╣
║ [✓/⚠] Database Migrations: [X pending / all applied]        ║
║ [✓/✗] CI Pipeline: [status]                                  ║
║ [✓/⚠] Vercel: [deployment status]                            ║
╠══════════════════════════════════════════════════════════════╣
║ RESULT: [READY/NOT READY/NEEDS ATTENTION]                    ║
╚══════════════════════════════════════════════════════════════╝

## Action Items

### 🔴 Blockers (must resolve)
- [blocker description]

### 🟡 Warnings (review recommended)
- [warning description]

## Next Steps

1. [step 1]
2. [step 2]
```

## Deployment Commands Reference

### Deploy to Staging
```bash
# 1. Push to staging branch
git checkout staging
git merge feature/your-feature
git push origin staging

# 2. Vercel auto-deploys to medicalbills.co
# 3. Verify at https://medicalbills.co
```

### Deploy to Production
```bash
# 1. Create PR: staging → master
gh pr create --base master --head staging --title "Release: [description]"

# 2. After approval, merge
gh pr merge --squash

# 3. Vercel auto-deploys to medicalbills.com
# 4. Verify at https://medicalbills.com
```

### Rollback
```bash
# Instant rollback via Vercel
vercel rollback

# Or revert commit
git revert HEAD
git push origin master
```

### Database Migration
```bash
# Apply pending migrations
supabase db push

# Check status
supabase migration list

# Rollback if needed
supabase migration down
```

## Environment Reference

| Environment | Branch | Domain | Auto-Deploy |
|-------------|--------|--------|-------------|
| Production | master | medicalbills.com | Yes |
| Staging | staging | medicalbills.co | Yes |
| Preview | feature/* | *.vercel.app | Yes (on PR) |

## CLI-First Reminder

All operations should use CLI tools:
- `vercel` for deployments
- `supabase` for database
- `gh` for GitHub PRs
- `npm` for builds and tests

Never use web dashboards for write operations.
