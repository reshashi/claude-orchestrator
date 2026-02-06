---
description: Install or manage git hooks for automated quality enforcement
allowed-tools: Bash(~/.claude/scripts/install-hooks.sh:*), Bash(~/.claude/scripts/auto-review.sh:*), Bash(~/.claude/scripts/auto-qcode.sh:*)
---

# /hooks - Git Hooks Management

Install or manage git hooks that automatically enforce quality rules.

## Arguments
- $ARGUMENTS: Subcommand (install, uninstall, review, qcode, status)

## Current Repository
- Repo root: !`git rev-parse --show-toplevel 2>/dev/null || echo "Not in a git repository"`
- Hooks dir: !`git rev-parse --git-dir 2>/dev/null`/hooks

## Instructions

Parse the arguments to determine the subcommand:

### install (default)
Install quality enforcement hooks in the current repository:
```bash
~/.claude/scripts/install-hooks.sh
```

This installs:
- **pre-commit**: Type check, lint, test before each commit
- **pre-push**: Full quality gates before pushing
- **post-merge**: Add TODOs to backlog after merge
- **commit-msg**: Enforce conventional commit format

### uninstall
Remove hooks from the current repository:
```bash
~/.claude/scripts/install-hooks.sh --uninstall
```

### review
Run automated code review (static analysis):
```bash
~/.claude/scripts/auto-review.sh
```

Add `--add-to-backlog` to automatically add issues to the backlog:
```bash
~/.claude/scripts/auto-review.sh --add-to-backlog
```

### qcode
Run automated code quality fixes:
```bash
~/.claude/scripts/auto-qcode.sh --fix
```

Add `--dry-run` to preview changes without applying:
```bash
~/.claude/scripts/auto-qcode.sh --fix --dry-run
```

### status
Check which hooks are installed:
```bash
ls -la $(git rev-parse --git-dir)/hooks/ | grep -E "^-.*x" | awk '{print $NF}'
```

## Examples

```
/hooks                    # Install hooks in current repo
/hooks install            # Same as above
/hooks uninstall          # Remove hooks
/hooks review             # Run automated review
/hooks qcode              # Run automated quality fixes
/hooks status             # Show installed hooks
```

## What the Hooks Enforce

### Pre-commit (runs before every commit)
- TypeScript type checking (if available)
- ESLint (if available)
- Tests (if available)
- Checks for potential secrets

### Pre-push (runs before every push)
- Full build
- All linting
- All tests
- Security audit (npm audit)

### Post-merge (runs after merges)
- Scans for TODO/FIXME comments
- Adds them to backlog database

### Commit-msg (validates commit messages)
- Enforces conventional commit format
- Types: feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert
- Example: `feat(auth): add OAuth2 login`

## Bypassing Hooks

If you need to bypass hooks temporarily (use sparingly):
```bash
git commit --no-verify
git push --no-verify
```

## CI/CD Integration

For GitHub Actions, copy the template:
```bash
mkdir -p .github/workflows
cp ~/.claude-orchestrator/templates/github-workflows/quality-gates.yml .github/workflows/
```

This provides server-side enforcement that cannot be bypassed.
