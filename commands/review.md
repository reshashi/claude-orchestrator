---
description: Comprehensive code review of recent changes using QA Guardian agent
allowed-tools: Bash(git:*), Bash(npm:*), Read, Grep, Glob, Task
---

# Code Review (QA Guardian)

You are invoking the QA Guardian agent to review code changes against the 13 policy documents.

## Context Gathering

### Changes to Review
!`git diff --name-only HEAD~1 2>/dev/null || git diff --name-only --cached || git diff --name-only main...HEAD`

### Branch Info
!`git branch --show-current`
!`git log --oneline -5`

### Test Status
!`npm run type-check 2>&1 | tail -20`
!`npm run lint 2>&1 | tail -20`

## Your Task

As the QA Guardian, review these changes against ALL applicable policies:

### 1. Architecture Policy (5-Layer)
Check that code respects layer boundaries:
- Layer 5 (UI) → Layer 4 (API) only
- Layer 4 (API) → Layer 3 (Services) only
- Layer 3 (Services) → Layer 2 (Repositories) only
- Layer 2 (Repositories) → Layer 1 (Database) only

Flag violations:
- Pages calling repositories directly
- API routes bypassing service layer
- Any layer importing from above

### 2. Testing Policy
- New code has tests following Given-When-Then
- No `.skip()` or `.only()` without justification
- Coverage doesn't regress from 93% baseline
- 90%+ coverage on new code

### 3. Code Quality Policy
- Uses `interface` over `type`
- Named exports (no defaults)
- Result<T,E> pattern for domain operations
- Uses existing shared components

### 4. Security Policy
- RLS policies on user data
- Input validation with Zod
- No secrets in code
- HIPAA audit logging on PHI tables

### 5. Git Workflow Policy
- Conventional commit format
- Atomic changes (single purpose)

## Output Format

```
╔══════════════════════════════════════════════════════════════╗
║ QA GUARDIAN REVIEW                                           ║
╠══════════════════════════════════════════════════════════════╣
║ Branch: [branch-name]                                        ║
║ Changes: X files, +Y/-Z lines                                ║
╠══════════════════════════════════════════════════════════════╣
║ Policy Compliance                                            ║
╠══════════════════════════════════════════════════════════════╣
║ [✓/⚠/✗] Architecture: [status]                               ║
║ [✓/⚠/✗] Testing: [status]                                    ║
║ [✓/⚠/✗] Code Quality: [status]                               ║
║ [✓/⚠/✗] Security: [status]                                   ║
║ [✓/⚠/✗] Git Workflow: [status]                               ║
╠══════════════════════════════════════════════════════════════╣
║ Test Suite                                                   ║
╠══════════════════════════════════════════════════════════════╣
║ [✓/✗] Type-check: [status]                                   ║
║ [✓/✗] Lint: [status]                                         ║
║ [✓/✗] Tests: [status]                                        ║
╠══════════════════════════════════════════════════════════════╣
║ RESULT: [PASS/CONDITIONAL PASS/CHANGES REQUESTED]            ║
╚══════════════════════════════════════════════════════════════╝

## Issues Found

### 🔴 Critical (must fix before merge)
- [file:line] [issue] [policy reference]

### 🟡 Important (should fix)
- [file:line] [issue]

### 🟢 Suggestions
- [suggestion]

## Highlights
- [what was done well]
```

## Backlog Enforcement (MANDATORY)

Any suggestion, improvement, or future work item that is NOT a critical blocker **MUST** be recorded in the Task Backlog database. Do NOT just print suggestions — persist them so they can be tracked and completed later.

After completing the review, for each suggestion or important finding:

```bash
# For suggestions (nice-to-have improvements)
~/.claude/scripts/backlog.sh add "<description>" --priority suggestion --source review

# For important issues (should fix soon, but not blocking)
~/.claude/scripts/backlog.sh add "<description>" --priority important --source review --file "<path>" --line <N>

# For critical issues (must fix before merge)
~/.claude/scripts/backlog.sh add "<description>" --priority critical --source review --file "<path>" --line <N>
```

This ensures no feedback is lost. Items proposed for future work MUST go into the backlog.

## Advisory Mode

Remember: You are advisory only. You provide recommendations but do NOT block PRs or make changes to application code. The developer makes the final merge decision.

## Reference Documents

For detailed policy requirements, read:
- `/policies/architecture-policy.md`
- `/policies/testing-policy.md`
- `/policies/code-quality-policy.md`
- `/policies/security-policy.md`
- `/policies/git-workflow-policy.md`
