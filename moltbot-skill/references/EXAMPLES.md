# Claude Orchestrator Usage Examples

Real-world examples of using the orchestrator through Moltbot.

## Example 1: Building a Feature with Multiple Workers

**User request:**
> "I need to add OAuth login. Spawn workers for config, API routes, and UI"

**Response:**
```
Spawning 3 workers for OAuth login:

⏳ oauth-config
   Task: Set up OAuth provider configuration (Google, GitHub)
   Branch: feature/oauth-config

⏳ oauth-api
   Task: Implement OAuth callback routes and token handling
   Branch: feature/oauth-api

⏳ oauth-ui
   Task: Build login/logout UI components with social buttons
   Branch: feature/oauth-ui

Workers are starting. Use 'orchestrator status' to monitor progress.
```

**Behind the scenes:**
```bash
orchestrator-bridge spawn oauth-config "Set up OAuth provider configuration for Google and GitHub including environment variables and auth client setup"
orchestrator-bridge spawn oauth-api "Implement OAuth callback routes and token handling with proper error handling and session management"
orchestrator-bridge spawn oauth-ui "Build login/logout UI components with social login buttons and loading states"
```

---

## Example 2: Checking Worker Status

**User request:**
> "What's the status of my workers?"

**Response:**
```
Workers Status:
────────────────────────────────────────────────

💻 oauth-config        WORKING
   Task: Set up OAuth provider configuration...
   Last active: 2 minutes ago

📬 oauth-api           PR_OPEN       PR #45
   Task: Implement OAuth callback routes...
   CI: ⏳ Running

📬 oauth-ui            PR_OPEN       PR #46
   Task: Build login/logout UI components...
   CI: ✅ Passed | Review: ⏳ Pending

Summary: 1 working, 2 with open PRs
```

---

## Example 3: Sending Additional Instructions

**User request:**
> "Tell the oauth-config worker to also add Apple Sign In"

**Response:**
```
Message sent to oauth-config:
"Also add Apple Sign In configuration. Follow the same pattern as Google and GitHub."

Worker will incorporate this into the current task.
```

**Behind the scenes:**
```bash
orchestrator-bridge send oauth-config "Also add Apple Sign In configuration. Follow the same pattern as Google and GitHub providers."
```

---

## Example 4: Full Project Mode

**User request:**
> "orchestrator project: build a complete user notification system with email, push, and in-app notifications"

**Response:**
```
Starting autonomous project: User Notification System

Phase 1: Planning
  Generating PRD and breaking down tasks...

Phase 2: Task Breakdown
  Identified 4 components:
  1. notification-models - Database models and types
  2. notification-email - Email notification service (SendGrid)
  3. notification-push - Push notification service (FCM)
  4. notification-inapp - In-app notification UI component

Phase 3: Spawning Workers
  ⏳ notification-models spawned
  ⏳ notification-email spawned
  ⏳ notification-push spawned
  ⏳ notification-inapp spawned

Phase 4: Monitoring
  Workers are now executing their tasks.
  I'll notify you when PRs are ready for review.

Use 'orchestrator status' to check progress at any time.
```

---

## Example 5: Merging Completed Work

**User request:**
> "The oauth-ui PR looks good, merge it"

**Response:**
```
Merging PR #46 for oauth-ui...

✅ PR #46 merged successfully!
   Commit: "feat: Add OAuth UI components (#46)"
   Branch: feature/oauth-ui deleted

Worker oauth-ui transitioned to MERGED state.

Remaining workers:
  💻 oauth-config - Still working
  📬 oauth-api - PR #45 awaiting review
```

---

## Example 6: Handling Errors

**User request:**
> "The oauth-api worker seems stuck"

**Response:**
```
Checking oauth-api status...

❌ oauth-api            ERROR
   Last active: 15 minutes ago
   Error: "Build failed: Missing dependency @auth/core"

Recommended actions:
1. Check the full output: orchestrator read oauth-api
2. Send a fix instruction: orchestrator send oauth-api "Install @auth/core and retry"
3. Or restart the worker manually

Would you like me to send the fix instruction?
```

---

## Example 7: Cleaning Up

**User request:**
> "Clean up all the completed workers"

**Response:**
```
Cleaning up completed workers...

Removed:
  ✅ oauth-ui (merged PR #46)
  ✅ notification-models (merged PR #52)

Still active:
  💻 oauth-config (working)
  📬 oauth-api (PR #45 open)

Worktrees remain at ~/.worktrees/myapp/
Run 'git worktree remove <path>' to fully clean up.
```

---

## Example 8: Natural Language Variations

All of these are equivalent ways to spawn a worker:

- "spawn auth-worker to implement JWT authentication"
- "create a worker called auth-worker for JWT authentication"
- "start a new worker named auth-worker to add JWT auth"
- "I need a worker called auth-worker to implement JWT"
- "orchestrator spawn auth-worker JWT authentication"

All of these check status:

- "what's the status?"
- "show me the workers"
- "how are my workers doing?"
- "orchestrator status"
- "list active workers"

---

## Example 9: Multi-Platform Usage

### From Discord
```
User: @moltbot spawn payment-api to integrate Stripe payments
Moltbot: Worker 'payment-api' spawned! Starting Stripe integration...
```

### From Slack
```
User: /claude orchestrator spawn payment-api "integrate Stripe payments"
Claude: Worker 'payment-api' spawned! I'll work on integrating Stripe.
```

### From Terminal (via API)
```bash
curl -X POST http://localhost:3001/api/workers \
  -H "Content-Type: application/json" \
  -d '{"name":"payment-api","task":"Integrate Stripe payments"}'
```

---

## Example 10: Coordinated Feature Development

**User request:**
> "I need to build a dark mode feature. It needs database schema changes, backend API, and frontend components. Coordinate the workers so they don't conflict."

**Response:**
```
Building dark mode with coordinated workers:

Phase 1: Database first (must complete before others)
  ⏳ darkmode-db
     Task: Add user_preferences table with theme column
     Branch: feature/darkmode-db

Phase 2: Backend (depends on db)
  ⏳ darkmode-api
     Task: Add GET/PUT endpoints for user theme preference
     Branch: feature/darkmode-api
     Waiting for: darkmode-db

Phase 3: Frontend (depends on api)
  ⏳ darkmode-ui
     Task: Build theme toggle component and apply theme CSS
     Branch: feature/darkmode-ui
     Waiting for: darkmode-api

Coordination:
- Workers will check dependencies before starting
- Each worker merges before the next one can PR
- I'll manage the sequence automatically

ETA: Workers will complete in sequence. I'll update you as each one finishes.
```

---

## Quick Command Cheat Sheet

| What you want | What to say |
|---------------|-------------|
| Create one worker | "spawn worker-name to do the task" |
| Create multiple workers | "spawn workers for X, Y, and Z" |
| Check all workers | "status" or "what's happening" |
| Check one worker | "status of worker-name" |
| See worker output | "read worker-name" |
| Send instructions | "tell worker-name to also do X" |
| Stop a worker | "stop worker-name" |
| Merge a PR | "merge worker-name" |
| Clean up | "cleanup completed workers" |
| Full project | "project: description of feature" |
