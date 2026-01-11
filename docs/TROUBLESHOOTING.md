# Troubleshooting

Common issues and solutions for Claude Code Orchestrator.

## Installation Issues

### "iTerm2 not found" Error

**Symptom:**
```
[ERROR] iTerm2 not found at /Applications/iTerm.app
```

**Solution:**
1. Download iTerm2 from https://iterm2.com
2. Move to /Applications/iTerm.app
3. Open iTerm2 at least once to complete setup

### "Git version too old" Warning

**Symptom:**
```
[WARN] Git version 2.17.0 may have limited worktree support
```

**Solution:**
```bash
# Update git via Homebrew
brew upgrade git

# Verify version
git --version  # Should be 2.20+
```

### "Claude Code CLI not found" Warning

**Symptom:**
```
[WARN] Claude Code CLI not found
```

**Solution:**
1. Install from https://claude.ai/code
2. Authenticate with `claude auth`
3. Verify with `claude --version`

### Shell Aliases Not Working

**Symptom:**
Commands like `wt`, `workers`, `orchestrator-start` not found.

**Solution:**
```bash
# Reload shell config
source ~/.zshrc  # or ~/.bashrc

# Verify aliases added
grep "claude-orchestrator" ~/.zshrc
```

If aliases are missing, re-run install:
```bash
~/.claude-orchestrator/install.sh -y
```

## Worker Issues

### Worker Tab Opens But Claude Doesn't Start

**Symptom:**
iTerm tab opens but shows a regular terminal, not Claude.

**Causes:**
1. Claude not in PATH
2. Worktree creation failed
3. AppleScript timing issue

**Solutions:**
```bash
# Check Claude is available
which claude

# Check worktree was created
wt list my-project

# Manually start Claude in worktree
cd ~/.worktrees/my-project/worker-name
claude
```

### Worker Stuck at "MCP Prompt"

**Symptom:**
Worker shows MCP server dialog and doesn't proceed.

**Solutions:**

For manual mode:
- Click the iTerm tab and press Enter

For automated mode:
- The orchestrator loop should handle this automatically
- Check if loop is running: `orchestrator-status`
- Check logs: `tail -f ~/.claude/orchestrator.log`

### Worker Not Receiving Task

**Symptom:**
Worker starts but doesn't know what to do.

**Solutions:**

1. Check worker state:
```bash
cat ~/.claude/worker-states/tab2_initialized
```

2. Manually send task:
```bash
~/.claude/scripts/worker-send.sh 2 "Your task: implement the login API"
```

3. Check active sessions log:
```bash
cat ~/.claude/active-sessions.log
```

### AppleScript Permission Denied

**Symptom:**
```
execution error: System Events got an error: osascript is not allowed to send keystrokes
```

**Solution:**
1. Open System Preferences → Security & Privacy → Privacy
2. Click "Accessibility" in the left sidebar
3. Click the lock to make changes
4. Add Terminal and iTerm2 to the allowed list

## Git/Worktree Issues

### "Worktree Already Exists" Error

**Symptom:**
```
fatal: '~/.worktrees/project/worker' already exists
```

**Solutions:**
```bash
# Remove the worktree
wt remove project worker

# If that fails, force remove
git worktree remove ~/.worktrees/project/worker --force

# Clean up any stale worktrees
git worktree prune
```

### Branch Already Exists

**Symptom:**
```
fatal: a branch named 'feature/worker' already exists
```

**Solutions:**
```bash
# Delete the local branch
git branch -D feature/worker

# If it exists on remote too
git push origin --delete feature/worker
```

### Worktree Not Deleted After Merge

**Symptom:**
Worktree directory remains after PR merge.

**Solution:**
```bash
# Manual cleanup
wt remove project worker

# Or directly
rm -rf ~/.worktrees/project/worker
git worktree prune
```

## Orchestrator Loop Issues

### Loop Not Starting

**Symptom:**
`orchestrator-start` runs but nothing happens.

**Solutions:**
```bash
# Check if already running
orchestrator-status

# Check for PID file
cat ~/.claude/orchestrator.pid

# Start with output visible
~/.claude/scripts/orchestrator-loop.sh  # without &
```

### Loop Crashes

**Symptom:**
Orchestrator stops unexpectedly.

**Solutions:**
```bash
# Check the log
tail -100 ~/.claude/orchestrator.log

# Look for errors
grep -i error ~/.claude/orchestrator.log

# Restart the loop
orchestrator-start
```

### Loop Not Detecting PRs

**Symptom:**
Worker creates PR but loop doesn't detect it.

**Solutions:**
1. Check GitHub CLI is authenticated:
```bash
gh auth status
```

2. Verify PR exists:
```bash
gh pr list
```

3. Check worker output is being read:
```bash
~/.claude/scripts/worker-read.sh 2
```

### Auto-Merge Not Working

**Symptom:**
PR passes review but isn't merged.

**Causes:**
1. Branch protection rules blocking merge
2. CI still running
3. Merge conflicts

**Solutions:**
```bash
# Check PR status
gh pr checks PR_NUMBER

# Check for conflicts
gh pr view PR_NUMBER

# Manual merge
gh pr merge PR_NUMBER --squash --delete-branch
```

## Review/Agent Issues

### QA Guardian Failing

**Symptom:**
`/review` reports issues.

**Solution:**
1. Read the review output carefully
2. Fix the issues in the worker
3. Worker will create a new commit
4. Run `/review` again

### DevOps Agent Not Triggering

**Symptom:**
Infrastructure changes don't trigger DevOps review.

**Solution:**
The DevOps agent only triggers for specific file patterns:
- `.github/workflows/*`
- `vercel.json`
- `supabase/*`
- `Dockerfile`, `docker-compose.yml`

Check if your files match these patterns.

## Performance Issues

### Workers Running Slowly

**Causes:**
1. Too many concurrent workers
2. Claude API rate limiting
3. CI queue congestion

**Solutions:**
- Reduce concurrent workers to 3-5
- Add delays between spawns
- Check Claude API status

### High Memory Usage

**Symptom:**
System becomes slow with many workers.

**Solution:**
Each Claude session uses ~100MB. Limit concurrent workers based on available RAM:
- 8GB RAM: 3-4 workers
- 16GB RAM: 6-8 workers
- 32GB+ RAM: 10+ workers

## Getting Help

If you're still stuck:

1. **Check the logs:**
```bash
tail -100 ~/.claude/orchestrator.log
```

2. **Verify installation:**
```bash
ls -la ~/.claude/scripts/
ls -la ~/.claude/commands/
ls -la ~/.claude/agents/
```

3. **Reset state:**
```bash
rm -rf ~/.claude/worker-states/*
rm -f ~/.claude/orchestrator.pid
```

4. **Reinstall:**
```bash
~/.claude-orchestrator/uninstall.sh
curl -fsSL https://raw.githubusercontent.com/reshashi/claude-orchestrator/main/install.sh | bash
```

5. **Open an issue:**
https://github.com/reshashi/claude-orchestrator/issues
