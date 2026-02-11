# Claude-Orchestrator v2.0 — Product Requirements Document

**Agent Teams Integration & Delivery Pipeline**

| | |
|---|---|
| **Author** | Shashi Mudunuri |
| **Repository** | reshashi/claude-orchestrator |
| **Version** | 2.0 (proposed) |
| **Date** | February 9, 2026 |
| **Status** | Draft |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Background & Problem Statement](#2-background--problem-statement)
3. [Goals & Non-Goals](#3-goals--non-goals)
4. [Feature Disposition Map](#4-feature-disposition-map)
5. [Detailed Requirements](#5-detailed-requirements)
6. [Architecture](#6-architecture)
7. [Implementation Plan](#7-implementation-plan)
8. [Success Criteria](#8-success-criteria)
9. [Risks & Mitigations](#9-risks--mitigations)
10. [Open Questions](#10-open-questions)
11. [Appendix A: Agent Teams Quick Reference](#appendix-a-agent-teams-quick-reference)

---

## 1. Executive Summary

With the release of Claude Opus 4.6, Anthropic has shipped **Agent Teams** as a first-party experimental feature inside Claude Code. Agent Teams natively handles multi-session orchestration, inter-agent communication, shared task lists, and parallel coordination. This absorbs approximately 80% of what **claude-orchestrator v1.0** was built to do.

This PRD defines the scope for v2.0 of claude-orchestrator, which will be reimagined as a **complementary layer** that integrates with Agent Teams where there is duplication, and extends Agent Teams with capabilities it does not currently provide: git worktree isolation for write-heavy parallelism, an automated PR/CI/merge delivery pipeline, pre-configured quality agents, and a fully automated background orchestration loop.

The goal is to make claude-orchestrator the best companion tool for Claude Code Agent Teams, not a competitor to it.

---

## 2. Background & Problem Statement

### 2.1 Current State of claude-orchestrator v1.0

Version 1.0 was built on Boris Cherny's parallel development patterns before Agent Teams existed. It provides:

- **Session spawning** via iTerm2 AppleScript tabs
- **Git worktree isolation** for conflict-free parallel branches
- **Slash commands** (`/spawn`, `/status`, `/merge`, `/workers`, `/plan`, `/review`, `/deploy`)
- **Built-in quality agents** (QA Guardian, DevOps Engineer, Code Simplifier, Verify App)
- **Automated orchestrator loop** for fully hands-off operation
- **PR pipeline automation** (CI monitoring, review gating, auto-merge)

### 2.2 What Agent Teams Now Provides Natively

Agent Teams (enabled via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) provides:

- **Multi-session orchestration** with a lead agent coordinating teammates
- **Inter-agent messaging** — teammates communicate peer-to-peer, not just report to a parent
- **Shared task list** with pending/in-progress/completed states and dependency tracking
- **Multiple backends** — in-process (any terminal), tmux split panes, iTerm2 panes
- **Delegate mode** — restricts lead to coordination only, preventing it from doing implementation work
- **Direct teammate interaction** — jump into any teammate's session via Shift+Up/Down or tmux pane clicks
- **CLAUDE.md integration** — teammates read project instructions from their working directory

### 2.3 The Gap

Agent Teams does **not** provide:

- Git worktree isolation for write-heavy parallel tasks (teammates share a codebase and can conflict on files)
- A delivery pipeline (PR creation, CI monitoring, review gating, merge automation)
- Pre-configured quality agents with persistent review mandates
- A fully automated background orchestration loop (MCP/trust prompt handling, CI polling, auto-merge)
- Session persistence or recovery after crashes/disconnects
- Cross-platform parity (tmux split panes don't work in VS Code terminal, Windows Terminal, or Ghostty)

Claude-orchestrator v2.0 fills these gaps while deferring to Agent Teams for everything it does well.

---

## 3. Goals & Non-Goals

### 3.1 Goals

1. **Integrate with Agent Teams:** Detect when Agent Teams is enabled and delegate session spawning, task management, and inter-agent coordination to it. The orchestrator becomes a wrapper, not a replacement.
2. **Preserve worktree isolation:** Offer git worktree mode as an opt-in for write-heavy parallel tasks where multiple agents editing the same files would cause conflicts.
3. **Deliver the delivery pipeline:** Provide PR creation, CI monitoring, quality review gates, and merge automation that Agent Teams lacks.
4. **Port quality agents:** Convert QA Guardian, DevOps Engineer, Code Simplifier, and Verify App into portable CLAUDE.md-compatible agent definitions that Agent Teams teammates can load.
5. **Maintain the automation loop:** Preserve the fully automated background orchestrator for unattended operation.
6. **Reduce platform dependencies:** Remove the hard requirement on iTerm2/AppleScript. Support tmux as primary, with iTerm2 as optional.

### 3.2 Non-Goals

- Replacing Agent Teams or duplicating its core capabilities
- Building a general-purpose multi-agent framework (this is specifically for Claude Code)
- Supporting non-macOS/Linux platforms (Windows is out of scope pending Agent Teams' own cross-platform improvements)
- Implementing nested or recursive agent teams
- Cost optimization or token budgeting (this is the user's responsibility)

---

## 4. Feature Disposition Map

This table maps every v1.0 feature to its v2.0 disposition: **Retire** (Agent Teams does it), **Retain** (Agent Teams doesn't), or **Adapt** (partially overlapping).

| v1.0 Feature | Disposition | v2.0 Owner | Notes |
|---|---|---|---|
| `/spawn` command | 🔴 Retire | Agent Teams | Lead agent handles spawning natively via TeammateTool |
| `/status` command | 🟡 Adapt | Orchestrator | Retains delivery pipeline status (PR state, CI checks); defers session status to Agent Teams |
| `/workers list/read` | 🔴 Retire | Agent Teams | Shift+Up/Down and tmux pane navigation replaces this |
| `/merge` command | 🟢 Retain | Orchestrator | Agent Teams has no merge/PR concept |
| `/plan` command | 🔴 Retire | Agent Teams | Lead agent's task list with dependencies replaces manual planning |
| `/review` command | 🟢 Retain | Orchestrator | Triggers QA Guardian agent; no equivalent in Agent Teams |
| `/deploy` command | 🟢 Retain | Orchestrator | Triggers DevOps Engineer agent; no equivalent in Agent Teams |
| Git worktrees | 🟡 Adapt | Orchestrator | Opt-in mode for write-heavy isolation; not used in Agent Teams mode by default |
| iTerm2 tab mgmt | 🔴 Retire | Agent Teams | tmux/in-process backends replace AppleScript automation |
| Orchestrator loop | 🟢 Retain | Orchestrator | Background automation (MCP prompts, CI polling, auto-merge) has no Agent Teams equivalent |
| QA Guardian agent | 🟡 Adapt | Both | Port to CLAUDE.md teammate prompt + retain as pipeline review gate |
| DevOps Engineer | 🟡 Adapt | Both | Port to CLAUDE.md teammate prompt + retain as pipeline review gate |
| Code Simplifier | 🟡 Adapt | Both | Port to CLAUDE.md teammate prompt for Agent Teams spawning |
| Verify App agent | 🟡 Adapt | Both | Port to CLAUDE.md teammate prompt for Agent Teams spawning |
| State machine tracking | 🟡 Adapt | Orchestrator | Tracks delivery states (PR_OPEN, REVIEWING, MERGING) not session states |
| Shell aliases (wt) | 🟢 Retain | Orchestrator | Worktree management utilities remain useful for isolation mode |

---

## 5. Detailed Requirements

### 5.1 Agent Teams Integration Layer

**Objective:** When Agent Teams is enabled, the orchestrator should use it as the session management and coordination backend rather than managing sessions directly.

#### 5.1.1 Detection & Mode Selection

- On startup, detect whether `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is set to `1`
- If enabled: operate in **Agent Teams mode** — delegate spawning, messaging, and task management to Agent Teams
- If disabled: operate in **Legacy mode** — use existing iTerm2/worktree approach (for backward compatibility)
- Expose a `--mode` flag to override auto-detection: `--mode=agent-teams | --mode=legacy | --mode=auto` (default)

#### 5.1.2 Spawn Delegation

When a user runs the orchestrator's spawn command in Agent Teams mode:

1. The orchestrator instructs the lead agent to spawn a teammate with the specified role and task prompt
2. If worktree isolation is requested (`--isolate` flag), the orchestrator creates a worktree first, then tells the teammate to work in that directory
3. The orchestrator registers the teammate in its own state tracker for delivery pipeline purposes

#### 5.1.3 Agent Prompt Portability

All four built-in agents must be ported to a format that Agent Teams can consume:

- **CLAUDE.md fragments:** Each agent's review mandate, quality criteria, and output format are expressed as a CLAUDE.md-compatible block that can be injected into a teammate's spawn prompt
- **Standalone agent files:** Retain .md files in `~/.claude/agents/` for use as pipeline review gates (invoked by the orchestrator, not as teammates)
- **Dual-use design:** The same agent definition should work both as a teammate spawn prompt and as a standalone review invocation

---

### 5.2 Delivery Pipeline

**Objective:** Provide the PR lifecycle that Agent Teams lacks. This is the orchestrator's primary unique value in v2.0.

#### 5.2.1 Pipeline Stages

Each task managed by the orchestrator progresses through these delivery stages:

| Stage | Emoji | Description |
|---|---|---|
| WORKING | 💻 | Teammate is actively developing (tracked by Agent Teams) |
| PR_CREATING | 📝 | Orchestrator creates a PR from the teammate's branch or changes |
| CI_RUNNING | ⏳ | GitHub Actions / CI checks are in progress |
| REVIEWING | 🔍 | QA Guardian and/or DevOps Engineer are reviewing the PR |
| APPROVED | ✅ | All checks passed; ready for merge |
| MERGING | 🔀 | PR is being merged to main |
| MERGED | ✅✅ | Complete; worktree cleaned up if applicable |
| BLOCKED | 🛑 | CI failed or review rejected; needs human attention |

#### 5.2.2 PR Creation

When a teammate signals task completion (via Agent Teams task status → completed):

1. **Worktree mode:** The teammate's worktree branch is pushed and a PR is created via `gh pr create`
2. **Shared codebase mode:** The orchestrator creates a feature branch from the teammate's changes, commits, pushes, and opens a PR
3. PR description is auto-generated from the teammate's task prompt and a summary of changes

#### 5.2.3 Quality Gates

Before a PR can be merged, it must pass through configurable quality gates:

- **CI Gate:** All GitHub Actions checks must pass
- **QA Guardian Gate:** Automated code review for quality, test coverage, and policy compliance. Configurable to be advisory or blocking.
- **DevOps Gate:** Triggered only when infrastructure-related files are changed (Dockerfile, CI configs, Terraform, etc.)
- **Code Simplifier Gate:** Triggered only when PR diff exceeds a configurable threshold (default: 500 lines)

#### 5.2.4 Merge Automation

When all gates pass:

1. The orchestrator merges the PR via `gh pr merge` (configurable: squash, merge commit, or rebase)
2. If worktree mode was used, the worktree and its branch are cleaned up
3. The orchestrator notifies the lead agent that the task is fully delivered

---

### 5.3 Worktree Isolation Mode

**Objective:** Provide opt-in file isolation for write-heavy parallel tasks where Agent Teams' shared codebase would cause conflicts.

#### 5.3.1 When to Use

Worktree mode is recommended when:

- Multiple teammates will edit the same files (e.g., shared config, package.json, migration files)
- Tasks are independent features that should each become separate PRs
- You need branch-level isolation for rollback safety

#### 5.3.2 Hybrid Workflow

In the hybrid model, Agent Teams manages coordination and the orchestrator manages isolation:

1. User requests a task with `--isolate` flag
2. Orchestrator creates a git worktree at `~/.worktrees/<repo>/<task-name>/`
3. Orchestrator instructs the lead agent to spawn a teammate with cwd set to the worktree path
4. Teammate works in isolation; Agent Teams handles messaging and task state
5. On completion, the orchestrator's delivery pipeline takes over (PR, CI, review, merge)

---

### 5.4 Automation Loop

**Objective:** Preserve the fully automated background orchestrator for unattended operation, adapted to work with Agent Teams.

#### 5.4.1 Loop Responsibilities

- **Permission prompt handling:** Auto-approve known MCP tool calls and trust prompts based on a configurable allowlist
- **CI polling:** Check GitHub Actions status for open PRs every N seconds (configurable, default 30s)
- **Quality gate triggering:** Invoke QA Guardian / DevOps Engineer when CI passes
- **Auto-merge:** Merge approved PRs automatically
- **Stall detection:** Detect teammates that have stopped making progress and alert the user or attempt recovery
- **Agent Teams health monitoring:** Check for crashed teammates or lead agent, attempt restart if possible

#### 5.4.2 Commands

| Command | Description |
|---|---|
| `orchestrator-start` | Start the background automation loop |
| `orchestrator-stop` | Stop the loop gracefully |
| `orchestrator-status` | Show loop state, active PRs, gate results |
| `orchestrator-config` | Edit automation settings (poll interval, gate config, merge strategy) |

---

### 5.5 Portable Agent Definitions

**Objective:** Make the four built-in agents (QA Guardian, DevOps Engineer, Code Simplifier, Verify App) usable both as Agent Teams teammates and as standalone pipeline reviewers.

#### 5.5.1 Agent Definition Format

Each agent will be defined as a YAML+Markdown file with the following structure:

- **metadata:** Name, description, trigger conditions (e.g., "trigger when infrastructure files change")
- **teammate_prompt:** The full prompt to pass to Agent Teams when spawning this agent as a teammate
- **review_mandate:** The specific criteria, output format, and pass/fail thresholds for pipeline review mode
- **configuration:** Adjustable parameters (e.g., Code Simplifier's line count threshold)

#### 5.5.2 Agent Registry

A registry at `~/.claude-orchestrator/agents/` allows users to add custom agents following the same format. The orchestrator discovers all agents at startup and makes them available both for teammate spawning and pipeline review.

---

## 6. Architecture

### 6.1 System Diagram

The v2.0 architecture positions the orchestrator as a delivery and isolation layer around Agent Teams:

```
┌─────────────────────────────────────────────────────┐
│  CLAUDE-ORCHESTRATOR v2.0                           │
│  ┌─────────────┐  ┌────────────┐  ┌────────────┐   │
│  │  Delivery   │  │  Worktree  │  │  Automation│   │
│  │  Pipeline   │  │  Isolation │  │  Loop      │   │
│  └──────┬──────┘  └──────┬─────┘  └──────┬─────┘   │
└─────────┼────────────────┼───────────────┼──────────┘
          │                │               │
          ▼                ▼               ▼
┌─────────────────────────────────────────────────────┐
│  CLAUDE CODE AGENT TEAMS (native)                   │
│  Lead Agent  ↔  Teammate 1  ↔  Teammate 2  ...     │
│  (shared task list, peer-to-peer messaging)         │
└─────────────────────────────────────────────────────┘
```

### 6.2 Directory Structure (v2.0)

```
~/.claude-orchestrator/
├── config/
│   ├── orchestrator.yaml        # Global config
│   └── gates.yaml               # Quality gate config
├── agents/
│   ├── qa-guardian.yaml          # Dual-use agent def
│   ├── devops-engineer.yaml
│   ├── code-simplifier.yaml
│   └── verify-app.yaml
├── pipeline/
│   ├── pr-manager.sh            # PR create/merge
│   ├── ci-monitor.sh            # CI polling
│   └── gate-runner.sh           # Review gate exec
├── scripts/
│   ├── orchestrator-loop.sh     # Background loop
│   └── wt.sh                    # Worktree mgmt
├── commands/                    # Retained slash cmds
│   ├── merge.md
│   ├── review.md
│   ├── deploy.md
│   └── status.md               # Delivery status only
├── install.sh
├── uninstall.sh
└── version
```

---

## 7. Implementation Plan

### Phase 1: Foundation (Week 1–2)

- Implement Agent Teams detection and mode selection logic
- Refactor spawn command to delegate to Agent Teams when in AT mode
- Remove iTerm2/AppleScript dependency; make tmux the primary backend
- Port four agent definitions to dual-use YAML+Markdown format
- Update install.sh to handle v1 → v2 migration cleanly

### Phase 2: Delivery Pipeline (Week 3–4)

- Implement PR creation from both worktree and shared-codebase modes
- Build CI polling monitor with configurable interval
- Implement quality gate runner that invokes agent definitions
- Build merge automation with configurable strategy (squash/merge/rebase)
- Implement `/status` command showing delivery pipeline state

### Phase 3: Automation Loop (Week 5–6)

- Adapt orchestrator-loop.sh for Agent Teams mode
- Implement stall detection for teammates
- Add Agent Teams health monitoring (detect crashed sessions)
- Implement permission prompt auto-approval with configurable allowlist
- End-to-end testing of automated workflow: spawn → develop → PR → CI → review → merge

### Phase 4: Polish & Documentation (Week 7–8)

- Update README.md with v2.0 architecture, commands, and usage patterns
- Write migration guide from v1.0 to v2.0
- Add configuration examples for common project types (monorepo, microservices, etc.)
- Create CLAUDE.md template showing how to set up agent roles for common workflows
- Release v2.0.0

---

## 8. Success Criteria

| Metric | Target |
|---|---|
| Agent Teams mode works end-to-end | Spawn teammates, complete tasks, create PRs, merge — all via orchestrator commands |
| Legacy mode backward compatibility | v1.0 workflows continue to function for users who don't have Agent Teams enabled |
| Delivery pipeline completes autonomously | PR → CI → QA review → merge cycle runs without human intervention |
| Quality agents work in both modes | Same agent def spawns as teammate AND runs as pipeline gate |
| Worktree isolation prevents file conflicts | Two teammates editing the same file in isolation mode produce no git conflicts |
| Install/update is one command | curl install + source refresh, same as v1.0 |
| No iTerm2 hard dependency | Full functionality with tmux only; iTerm2 optional |

---

## 9. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Agent Teams API changes during research preview | 🔴 High | Abstract Agent Teams interactions behind an adapter layer. Monitor Claude Code release notes. Pin to known-good Claude Code versions in CI. |
| Agent Teams reaches GA and subsumes delivery pipeline features | 🟡 Medium | Design the pipeline as modular and removable. If Agent Teams ships PR/merge capabilities, gracefully deprecate ours. |
| Token cost escalation from Agent Teams overhead | 🟡 Medium | Document cost expectations clearly. Add a `--budget` flag for approximate token ceiling alerts. Recommend subagents for simple tasks. |
| Worktree + Agent Teams hybrid creates state inconsistencies | 🟡 Medium | Maintain a single source of truth for task state. Agent Teams owns session state; orchestrator owns delivery state. Never overlap. |
| macOS-only limitation persists | 🟢 Low | tmux works on Linux too. Cross-platform support improves automatically as Agent Teams improves. |
| Community adoption risk (niche tool) | 🟢 Low | Position clearly as a complement, not a competitor. Focus on the delivery pipeline gap that all Agent Teams users face. |

---

## 10. Open Questions

1. **Agent Teams session resumption:** When Anthropic ships `/resume` support for teammates, does the orchestrator need to handle session recovery, or can it delegate entirely?
2. **Nested teams:** If Agent Teams supports nested teams in a future release, should the orchestrator support spawning sub-orchestrators for complex multi-project workflows?
3. **Cost tracking:** Should the orchestrator integrate with Anthropic's billing API (if available) to provide real-time token cost reporting per task?
4. **CI provider flexibility:** v1.0 assumes GitHub Actions and `gh` CLI. Should v2.0 support GitLab CI, Bitbucket Pipelines, or other CI systems?
5. **Plugin ecosystem:** Should the agent registry support community-contributed agent definitions (like the wshobson/agents plugin system)?

---

## Appendix A: Agent Teams Quick Reference

For developers working on this PRD's implementation:

```bash
# Enable Agent Teams
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Or in settings.json
{ "experimental": { "agentTeams": true } }

# Force tmux backend for split panes
export CLAUDE_CODE_SPAWN_BACKEND=tmux

# Navigation (in-process mode)
Shift+Up/Down    Select teammate
Enter            View teammate session
Escape           Interrupt teammate turn
Ctrl+T           Toggle task list
```
