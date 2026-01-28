# Claude Orchestrator Moltbot Skill

A skill for Moltbot that enables parallel Claude Code worker orchestration from any messaging platform.

## Overview

This skill allows you to manage parallel Claude workers from Discord, Slack, Telegram, WhatsApp, or any other Moltbot-supported platform. Spawn workers, monitor their progress, and merge their PRs - all through natural conversation.

## Installation

### Via ClawdHub (Recommended)

```bash
clawdhub install claude-orchestrator
```

### Manual Installation

1. **Install the orchestrator**:
   ```bash
   cd ~/.claude-orchestrator
   npm install
   npm run build
   npm link
   ```

2. **Copy the skill**:
   ```bash
   cp -r moltbot-skill ~/.clawdbot/skills/claude-orchestrator
   ```

3. **Or symlink**:
   ```bash
   ln -s ~/.claude-orchestrator/moltbot-skill ~/.clawdbot/skills/claude-orchestrator
   ```

## Prerequisites

- **Node.js 18+** - Runtime for the orchestrator
- **Git** - With worktree support
- **GitHub CLI (`gh`)** - Authenticated with your account
- **Claude Code CLI** - For running workers
- **jq** - For JSON processing in the bridge script

## Usage

### Quick Commands

| Command | Description |
|---------|-------------|
| `orchestrator spawn <name> <task>` | Create a new worker |
| `orchestrator list` | Show active workers |
| `orchestrator status [id]` | Get detailed status |
| `orchestrator send <id> <message>` | Send message to worker |
| `orchestrator stop <id>` | Stop a worker |
| `orchestrator merge <id>` | Merge worker's PR |

### Natural Language

Users can speak naturally:
- "spawn a worker called auth-api to implement authentication"
- "what's the status of my workers?"
- "tell the api worker to also add pagination"
- "merge the dark-mode worker"

### Full Project Mode

```
orchestrator project: build a complete user notification system
```

This triggers autonomous execution:
1. Generate PRD and break into tasks
2. Spawn workers for each component
3. Monitor and run QA reviews
4. Merge PRs when ready

## API Server

For better integration, run the HTTP API server:

```bash
orchestrator serve --port 3001
```

### REST Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/workers` | List all workers |
| GET | `/api/workers/:id` | Get worker status |
| POST | `/api/workers` | Spawn new worker |
| POST | `/api/workers/:id/send` | Send message |
| POST | `/api/workers/:id/stop` | Stop worker |
| POST | `/api/workers/:id/merge` | Merge PR |
| DELETE | `/api/workers/:id` | Cleanup worker |

### WebSocket

Connect to `ws://localhost:3001/ws/status` for real-time updates.

## File Structure

```
moltbot-skill/
├── SKILL.md              # Main skill definition (Moltbot reads this)
├── scripts/
│   └── orchestrator-bridge.sh  # CLI wrapper for API/CLI
├── references/
│   ├── COMMANDS.md       # Detailed command reference
│   └── EXAMPLES.md       # Usage examples
└── README.md             # This file
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ORCHESTRATOR_PORT` | `3001` | API server port |
| `ORCHESTRATOR_HOST` | `localhost` | API server host |
| `ORCHESTRATOR_CLI` | `claude-orchestrator` | Path to CLI binary |

### Orchestrator Config

The orchestrator reads configuration from:
- CLI flags
- Environment variables
- Persisted state in `~/.claude/workers/`

Key settings:
- `pollIntervalMs` - How often to check workers (default: 5000)
- `autoMerge` - Auto-merge approved PRs (default: true)
- `autoReview` - Auto-run QA review (default: true)

## Troubleshooting

### Worker stuck in WORKING state

```bash
# Check what it's doing
orchestrator read <worker-id>

# Nudge it
orchestrator send <worker-id> "Please continue with the task"
```

### PR not merging

```bash
# Check CI status
gh pr checks <pr-number>

# Check review status
orchestrator status <worker-id>

# Force merge
orchestrator merge <worker-id>
```

### API server not responding

```bash
# Check health
orchestrator-bridge health

# Start server
orchestrator serve
```

### Bridge script errors

```bash
# Verify jq is installed
which jq

# Test API manually
curl http://localhost:3001/api/workers
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Make changes to the skill
4. Test with Moltbot locally
5. Submit a PR

## License

MIT

## Related

- [Claude Orchestrator](https://github.com/...) - The main orchestrator
- [Moltbot](https://github.com/psteinroe/moltbot) - The AI assistant framework
- [ClawdHub](https://github.com/...) - Skill registry
