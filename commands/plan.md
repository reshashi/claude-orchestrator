---
description: Create a work breakdown structure for parallel execution across multiple Claude sessions
allowed-tools: Bash(git:*), Bash(cat:*), Bash(find:*)
---

# Plan: Work Breakdown for Parallel Execution

Analyze the requested work and create a structured plan that can be executed by multiple parallel Claude workers.

## Request
$ARGUMENTS

## Current Context
- Repo root: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`
- Directory structure: !`find . -type d -maxdepth 2 -not -path '*/\.*' -not -path './node_modules/*' | head -20`

## Instructions

Analyze the request and create a plan with these sections:

### 1. Goal Summary
One paragraph describing the overall objective.

### 2. Work Breakdown
Break the work into 2-5 independent streams that can run in parallel. For each stream:

```
Stream: [short-name]
Task: [specific task description]
Owns: [files/directories this worker can modify]
Off-limits: [files/directories NOT to touch]
Dependencies: [any streams this must wait for, or "none"]
Estimated scope: [small/medium/large]
```

### 3. Execution Order
- Which streams can start immediately (no dependencies)
- Which must wait for others
- Suggested merge order

### 4. Risk Assessment
- Files that multiple streams might want to touch → assign to ONE owner
- Potential conflicts and how to avoid them
- Shared state or configuration that needs coordination

### 5. Ready-to-Execute Commands
Provide the exact `/spawn` commands to create each worker:

```
/spawn [stream-name] "[task description]"
```

### Rules for Good Work Breakdown

1. **Independence**: Each stream should be able to work without blocking on others
2. **Clear ownership**: Every file has exactly ONE owner
3. **Minimal interfaces**: Streams communicate through clear interfaces, not shared files
4. **Atomic deliverables**: Each stream produces a complete, testable result
5. **No overlap**: If two streams need the same file, redesign the breakdown

### Example Breakdown

For "Add user authentication with OAuth":

```
Stream: oauth-config
Task: Set up OAuth provider configuration and environment variables
Owns: /src/config/oauth.ts, .env.example
Off-limits: /src/routes/*, /src/components/*
Dependencies: none
Scope: small

Stream: auth-routes
Task: Implement /auth/login, /auth/callback, /auth/logout routes
Owns: /src/routes/auth/*
Off-limits: /src/components/*, /src/config/*
Dependencies: oauth-config
Scope: medium

Stream: auth-ui
Task: Create login button and auth state components
Owns: /src/components/auth/*
Off-limits: /src/routes/*, /src/config/*
Dependencies: auth-routes (for API contract)
Scope: medium
```
