---
description: Analyze and fix a GitHub issue end-to-end
allowed-tools: Bash(gh:*), Bash(git:*), Read, Write, Grep, Glob
---

# Fix GitHub Issue

Analyze and fix a GitHub issue automatically.

## Issue
$ARGUMENTS

## Issue Details
!`gh issue view $1 2>/dev/null || echo "Could not fetch issue $1"`

## Instructions

1. **Understand the Issue**
   - Read the issue details above
   - Identify what needs to be fixed
   - Note any acceptance criteria or requirements

2. **Find Relevant Code**
   - Search the codebase for related files
   - Understand the current implementation
   - Identify what needs to change

3. **Plan the Fix**
   - Before writing code, explain your plan
   - List the files you'll modify
   - Describe the changes you'll make

4. **Implement the Fix**
   - Make the necessary code changes
   - Follow the coding standards in CLAUDE.md
   - Keep changes minimal and focused

5. **Test the Fix**
   - Run existing tests: `npm test`
   - Add new tests if needed
   - Verify the fix works as expected

6. **Verify Quality**
   - Run linter: `npm run lint`
   - Run type check: `npm run typecheck`
   - Ensure build passes: `npm run build`

7. **Commit and PR**
   - Create a descriptive commit message referencing the issue
   - Push to a feature branch
   - Open a PR that closes the issue

## Commit Message Format
```
fix(scope): description

Fixes #[issue-number]
```

## PR Description Template
```markdown
## Summary
[Brief description of the fix]

## Changes
- [Change 1]
- [Change 2]

## Testing
- [How the fix was tested]

Closes #[issue-number]
```
