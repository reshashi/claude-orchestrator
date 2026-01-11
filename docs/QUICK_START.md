# Quick Start Guide

This guide walks you through setting up and using Claude Code Orchestrator for parallel development.

## Prerequisites

Before you begin, ensure you have:

- **macOS** (required for iTerm2 + AppleScript)
- **[iTerm2](https://iterm2.com/)** installed
- **Git 2.20+** for worktree support
- **[Claude Code CLI](https://claude.ai/code)** installed and authenticated
- **[GitHub CLI](https://cli.github.com/)** (optional, for PR automation)

## Installation

### Step 1: Install the Orchestrator

```bash
curl -fsSL https://raw.githubusercontent.com/[org]/claude-orchestrator/main/install.sh | bash
```

You should see output like:
```
[INFO] Checking prerequisites...
[OK] macOS detected
[OK] iTerm2 found
[OK] Git 2.39.0 (worktree support: OK)
[OK] Claude Code CLI found
[OK] GitHub CLI found

[INFO] Installing from local directory...
[INFO] Version: 1.0.0

[INFO] Installing scripts...
[OK] Scripts installed to ~/.claude/scripts

[INFO] Installing commands...
[OK] Commands installed to ~/.claude/commands

[INFO] Installing agents...
[OK] Agents installed to ~/.claude/agents

Installation complete!
```

### Step 2: Restart Your Terminal

```bash
source ~/.zshrc  # or ~/.bashrc
```

### Step 3: Verify Installation

```bash
# Check scripts are available
ls ~/.claude/scripts/orchestrator*.sh

# Check commands are available
ls ~/.claude/commands/spawn.md

# Check aliases work
wt --help
```

## Your First Parallel Development Session

### Step 1: Start Claude in Your Project

```bash
cd ~/your-project
claude
```

### Step 2: Plan the Work

Use the `/plan` command to break down a large task:

```
You: /plan "Implement user authentication with login, logout, and password reset"
```

Claude will analyze your codebase and suggest a work breakdown:
- Worker 1: Database schema and migrations
- Worker 2: API endpoints
- Worker 3: Frontend components
- Worker 4: Tests

### Step 3: Spawn Workers

```
You: /spawn auth-db "Create users table migration with email, password_hash, created_at"
```

This will:
1. Create a git worktree at `~/.worktrees/your-project/auth-db`
2. Create a feature branch `feature/auth-db`
3. Open a new iTerm tab
4. Start Claude in that worktree
5. Initialize the worker with the task

Repeat for other workers:

```
You: /spawn auth-api "Implement login and logout API endpoints with JWT"
You: /spawn auth-ui "Build login form with email/password fields and validation"
```

### Step 4: Monitor Progress

Check on your workers:

```
You: /status
```

Output:
```
Active Worktrees:
  auth-db   feature/auth-db   ~/.worktrees/your-project/auth-db   [WORKING]
  auth-api  feature/auth-api  ~/.worktrees/your-project/auth-api  [WORKING]
  auth-ui   feature/auth-ui   ~/.worktrees/your-project/auth-ui   [PR_OPEN]

Open PRs:
  #42 feature/auth-ui → main [CI: passing]
```

Read output from a specific worker:

```
You: /workers read 2
```

### Step 5: Review and Merge

When a worker creates a PR:

```
You: /review
```

This runs QA Guardian to review the PR against your project's policies.

When the review passes:

```bash
gh pr merge 42 --squash --delete-branch
```

Or use the merge command:

```
You: /merge auth-ui
```

### Step 6: Clean Up

Workers are automatically cleaned up when merged. To manually clean up:

```bash
wt remove your-project auth-db
```

## Automated Mode

For hands-off operation, start the orchestrator loop:

```bash
# In a terminal (not in Claude)
orchestrator-start
```

The loop will automatically:
- Initialize workers when they're ready
- Answer prompts (MCP, trust confirmations)
- Monitor PRs for CI status
- Run `/review` when CI passes
- Merge when review passes
- Close tabs when workers complete

Monitor the loop:
```bash
tail -f ~/.claude/orchestrator.log
```

Stop when done:
```bash
orchestrator-stop
```

## Tips for Success

### 1. Define Clear Task Boundaries

Each worker should have a clear, isolated scope:
- ✅ "Create users table migration"
- ✅ "Implement login API endpoint"
- ❌ "Build authentication" (too broad)

### 2. Avoid File Conflicts

Don't assign the same files to multiple workers. If workers need to modify the same file, have them work sequentially or coordinate through well-defined interfaces.

### 3. Use Conventional Branches

The orchestrator uses `feature/<worker-name>` branches by default. This integrates well with most CI/CD pipelines.

### 4. Review Before Merging

Always run `/review` before merging to catch issues early. The QA Guardian checks:
- Code quality and patterns
- Test coverage
- Security considerations
- Architecture compliance

### 5. Keep Workers Small

Smaller, focused workers complete faster and are easier to review:
- Aim for 1-3 file changes per worker
- Target PRs under 200 lines changed
- Split large features into multiple workers

## Next Steps

- Read [Architecture](ARCHITECTURE.md) to understand how the system works
- Check [Troubleshooting](TROUBLESHOOTING.md) if you run into issues
- Customize the agents in `~/.claude/agents/` for your project's policies
