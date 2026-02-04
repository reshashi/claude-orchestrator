---
description: Execute a complete project from concept to delivery - the Planner orchestrates workers, reviews, and delivers
allowed-tools: Bash(*), Read, Write, Grep, Glob, Task
---

# /project - Autonomous Project Execution

Execute a complete project from a conceptual description. The Planner will:
1. Generate a comprehensive PRD
2. Break work into parallel tasks
3. Spawn and manage workers
4. Review completed work (`/review` + `/qcode`)
5. Fix critical issues, add suggestions to `TASKS_BACKLOG.md`
6. Iterate if needed (max 3 times)
7. Generate Slack post for stakeholders
8. Deliver summary and notify you

## Arguments
- $ARGUMENTS: The project description (what you want to build)

## Context
- Repo root: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`
- Project structure: !`find . -type d -maxdepth 2 -not -path '*/\.*' -not -path './node_modules/*' | head -30`

## Instructions

### Resuming After Context Compaction

If you're resuming this project after context was compacted:
1. Read the PRD file (check `~/.claude/project-state.json` for `prd_path`)
2. Go directly to **Section 6: Execution Status** in the PRD
3. The "Current State" tells you what phase you're in
4. The "Phase Checklist" shows what's done
5. The "Worker Status" table shows each worker's progress
6. Resume from the appropriate phase below

### Phase 1: PRD Generation (CONCEPTUALIZING)

Think deeply about the project requirements. Consider:
- What is the user trying to accomplish?
- What files need to be created or modified?
- How can this be broken into parallel, independent work streams?
- What are the success criteria?

Generate a comprehensive PRD and save it:

```bash
# Generate project name (slug) from description
PROJECT_NAME=$(echo "$ARGUMENTS" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-30)

# Create dated filename: PRD-YYYY-MM-DD-project-name.md
DATE_PREFIX=$(date +%Y-%m-%d)
PRD_FILENAME="PRD-${DATE_PREFIX}-${PROJECT_NAME}.md"
REPO_ROOT=$(git rev-parse --show-toplevel)

# Ensure /prds directory exists
mkdir -p "${REPO_ROOT}/prds"
```

Write the PRD to `${REPO_ROOT}/prds/${PRD_FILENAME}` with these sections:

```markdown
# PRD: [Project Name]

## 1. Executive Summary
[One paragraph describing what we're building and why]

## 2. Goals & Success Criteria
- [ ] Criterion 1 (must be measurable and testable)
- [ ] Criterion 2
- [ ] Criterion 3
[Add more as needed - these will be verified after implementation]

## 3. Technical Requirements

### Files to Create
- path/to/new/file.ts - [Purpose]

### Files to Modify
- path/to/existing.ts - [What changes]

### Dependencies
- [New packages needed, if any]

## 4. Worker Task Breakdown

### Worker 1: [short-name]
- **Task**: [Specific description of what this worker does]
- **Owns**: [files/directories this worker can modify]
- **Off-limits**: [files this worker must NOT touch]
- **Depends on**: [other worker names, or "none"]

### Worker 2: [short-name]
[Repeat for each worker - aim for 2-5 workers]

## 5. Verification Plan
How to verify the project is complete:
- [ ] Manual test 1
- [ ] Manual test 2
- [ ] `npm run test` passes
- [ ] `npm run build` passes
- [ ] `npm run type-check` passes

## 6. Execution Status

> **READ THIS FIRST AFTER CONTEXT COMPACTION**
> This section is the source of truth for project progress.

### Current State
- **Phase**: CONCEPTUALIZING
- **Iteration**: 1 of 3
- **Started**: [timestamp]
- **Last Updated**: [timestamp]

### Phase Checklist
- [x] Phase 1: PRD Generation
- [ ] Phase 2: Workers Spawned
- [ ] Phase 3: Workers Active
- [ ] Phase 4: All Workers Merged
- [ ] Phase 5: Review Complete
- [ ] Phase 6: Quality Gates Passed
- [ ] Phase 7: Deliverables Generated
- [ ] Phase 8: Project Complete

### Worker Status
| Worker | Branch | Status | PR | Notes |
|--------|--------|--------|-----|-------|
| [name] | [branch] | pending/working/pr-open/merged | #N | |

### Blockers & Issues
- None yet

### Quality Gate Results
- [ ] `/review`: pending
- [ ] `/qcode`: pending
- [ ] Security scan: pending
- [ ] Critical issues fixed: N/A

### Log
- [timestamp] Project created
```

### Phase 2: Initialize Project State (SPAWNING_WORKERS)

**Update PRD Status**: Change Phase to `SPAWNING_WORKERS`, check off Phase 1, add log entry.

Create the project state file:

```bash
cat > ~/.claude/project-state.json << JSONEOF
{
  "project_name": "${PROJECT_NAME}",
  "prd_path": "${REPO_ROOT}/prds/${PRD_FILENAME}",
  "prd_filename": "${PRD_FILENAME}",
  "status": "spawning_workers",
  "iteration": 1,
  "max_iterations": 3,
  "workers": [],
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "completed_at": null,
  "feedback_history": []
}
JSONEOF
```

### Phase 3: Spawn Workers

**Update PRD Status**: For each worker spawned, add a row to the Worker Status table.

For each worker defined in the PRD:

1. Run `/spawn [worker-name] "[task description]"`
2. Update project-state.json to track the worker

Example:
```bash
/spawn oauth-config "Set up OAuth provider configuration. Owns: src/config/oauth.ts, .env.example. Off-limits: src/routes/*, src/components/*"
```

After spawning all workers, update status:
```bash
jq '.status = "workers_active"' ~/.claude/project-state.json > tmp.$$ && mv tmp.$$ ~/.claude/project-state.json
```

**Update PRD Status**: Check off Phase 2, set Phase to `WORKERS_ACTIVE`, add log entry with worker count.

### Phase 4: Start Orchestrator Loop

Start the orchestrator loop in the background:
```bash
~/.claude/scripts/orchestrator-loop.sh &
```

Tell the user:
```
Workers spawned and orchestrator running.

Monitoring progress... (check /status for updates)

You can walk away - I'll notify you when complete.
```

### Phase 5: Wait for Completion

Monitor for the `PROJECT_COMPLETE` message from the orchestrator.

When all workers have merged, the orchestrator will send:
`PROJECT_COMPLETE: All workers have merged. Begin review.`

### Phase 6: Review Merged Work (REVIEWING)

**Update PRD Status**: Check off Phases 3-4, set Phase to `REVIEWING`, update all workers to `merged`, add log entry.

Read the PRD success criteria from `${REPO_ROOT}/prds/${PRD_FILENAME}` (path stored in project-state.json as `prd_path`)

Review the merged code:
```bash
git log --oneline master..HEAD
git diff master --stat
```

For each success criterion, verify it is met by:
1. Reading the relevant files
2. Running any test commands
3. Checking the implementation matches requirements

Create a review report:
- Which requirements are met? (checkmark them)
- Which requirements are NOT met?
- What specific fixes are needed?

### Phase 6.5: Run Quality Agents (QUALITY_GATES)

**Update PRD Status**: Check off Phase 5, set Phase to `QUALITY_GATES`. After each agent runs, update Quality Gate Results section.

**IMPORTANT**: Run the quality agents to ensure the combined work meets standards.

1. **Run QA Guardian Review** on the merged changes:
```bash
# Review all changes since the project started
/review
```
This will:
- Check architecture policy compliance (5-layer boundaries)
- Verify test coverage hasn't decreased
- Check code quality standards
- Identify security issues

2. **Run Code Simplifier** to clean up the combined changes:
```bash
# Simplify and clean up the merged code
/qcode
```
This will:
- Remove unnecessary complexity
- Improve code readability
- Ensure consistent patterns
- Clean up any redundant code from parallel workers

3. **Run Security Scan**:
```bash
npm audit --audit-level=high
```

4. **Run DevOps Deployment Check** if infrastructure was changed:
```bash
/deploy
```

**Agent Results Summary**:
After running the agents, document:
- QA Review: PASS/FAIL (with issues if any)
- Code Simplifier: Changes made (or "No changes needed")
- Security: Vulnerabilities found (or "Clean")
- DevOps: Deployment ready (if applicable)

### Phase 6.6: Address Review Findings (REMEDIATION)

**Update PRD Status**: Add any blockers/issues found. Update Quality Gate Results as issues are fixed.

**IMPORTANT**: Act on the review findings immediately.

1. **Fix Critical Issues**: For any 🔴 Critical issues found by `/review`:
   - Fix them NOW before proceeding
   - Run the failing checks again to verify
   - These MUST be resolved before merge

2. **Add Backlog Items**: For 🟡 Important and 🟢 Suggestions:
   - Create or update `TASKS_BACKLOG.md` in the repo root
   - Add each suggestion as a task with context

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
BACKLOG_FILE="${REPO_ROOT}/TASKS_BACKLOG.md"

# Create backlog file if it doesn't exist
if [ ! -f "$BACKLOG_FILE" ]; then
  cat > "$BACKLOG_FILE" << 'EOF'
# Tasks Backlog

Suggestions and future work items captured during development.

## Format
- **[Priority]** Description — Source: [project/review date]

---

## Pending Tasks

EOF
fi
```

Append new items to the backlog:
```markdown
### From Project: ${PROJECT_NAME} ($(date +%Y-%m-%d))

- **[Important]** [issue description] — [file:line if applicable]
- **[Suggestion]** [suggestion description]
```

If any agent finds critical issues, add them to the requirements check.

### Phase 7: Decision Point

**If ALL requirements met** → Go to Phase 8 (Deliverables)

**If requirements NOT met AND iteration < 3**:
1. Increment iteration in project-state.json
2. Write feedback to `~/.claude/feedback/${PROJECT_NAME}-iteration-${N}.md`
3. Spawn fix workers for unmet requirements
4. Go back to Phase 4

**If requirements NOT met AND iteration >= 3**:
1. Update status to "needs_human"
2. Notify human with bell + macOS notification:
```bash
echo -e "\a"
osascript -e 'display notification "After 3 iterations, some requirements still not met. Manual intervention required." with title "Project Needs Human Review" sound name "Glass"'
```
3. Display what still needs to be done
4. Exit

### Phase 8: Generate Deliverables (GENERATING_DELIVERABLES)

**Update PRD Status**: Check off Phase 6, set Phase to `GENERATING_DELIVERABLES`, add log entry.

Create the deliverables directory:
```bash
mkdir -p ~/.claude/deliverables/${PROJECT_NAME}
```

Generate SUMMARY.md with:
- Executive Summary (what was built)
- Features Implemented (list)
- Files Changed (table)
- How to Use (for users and developers)
- Testing verification
- Known Limitations
- Metrics (workers, iterations, time)

Generate USAGE_GUIDE.md if the project warrants it.

### Phase 9: Generate Slack Post (COMMUNICATION)

**IMPORTANT**: Generate a Slack-ready post for non-technical stakeholders.

Create `SLACK_POST.md` in the deliverables directory:

```bash
cat > ~/.claude/deliverables/${PROJECT_NAME}/SLACK_POST.md << 'SLACKEOF'
# Slack Post: ${PROJECT_NAME}

Copy the content below into Slack:

---

## 🚀 [Project Title] - Complete!

### What We Did
[1-2 sentences explaining the feature/change in plain English. No technical jargon.]

### Why It Matters
[1-2 sentences on the business value or user benefit.]

### How to Test
1. [Step 1 - simple action anyone can do]
2. [Step 2]
3. [Expected result]

### Links
- PR: [link if applicable]
- Demo: [link if applicable]

---
SLACKEOF
```

**Guidelines for the Slack post**:
- Use plain English (no code, no technical terms)
- Focus on WHAT changed and WHY it matters to users/business
- Testing steps should be actionable by a non-developer
- Keep it under 150 words
- Use emojis sparingly for visual appeal

Display the Slack post to the user for review and copying.

### Phase 10: Notify Human (PROJECT_COMPLETE)

**Update PRD Status**: Check off Phases 7-8, set Phase to `COMPLETE`, add final log entry with completion timestamp.

Update project state:
```bash
jq '.status = "complete" | .completed_at = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"' ~/.claude/project-state.json > tmp.$$ && mv tmp.$$ ~/.claude/project-state.json
```

Send notifications:
```bash
# Terminal bell
echo -e "\a"

# macOS notification
osascript -e 'display notification "See ~/.claude/deliverables/${PROJECT_NAME}/SUMMARY.md for details" with title "Project Complete!" sound name "Glass"'
```

Display the summary in terminal:
```
========================================
PROJECT COMPLETE: ${PROJECT_NAME}
========================================

[Contents of SUMMARY.md]

========================================
SLACK POST (copy to #channel):
========================================

[Contents of SLACK_POST.md]

========================================
```

## Important Notes

- **File Ownership**: Each worker must have exclusive ownership of files. No two workers can modify the same file.
- **Off-limits Enforcement**: Workers are told which files they cannot touch. This prevents merge conflicts.
- **Iteration Limit**: Maximum 3 feedback iterations before escalating to human.
- **Quality Gates**: Each worker PR goes through QA Guardian review automatically.
- **Autonomous Operation**: After you type `/project`, you can walk away. You'll be notified when complete.
- **Standard Quality Process**: Every project runs `/review` and `/qcode`. Critical issues are fixed immediately; suggestions go to `TASKS_BACKLOG.md`.
- **Stakeholder Communication**: Every project generates a non-technical Slack post explaining what was done, why, and how to test.
- **Context Recovery**: The PRD's "Execution Status" section is the source of truth. After context compaction, read the PRD first to understand current state before resuming work.

## Example

```
/project "Add a dark mode toggle that:
- Adds a toggle button in the site header
- Persists user preference to localStorage
- Applies CSS variables for dark theme
- Works across all pages"
```

This will:
1. Generate PRD at `/prds/PRD-2026-01-13-add-a-dark-mode-toggle-that.md`
2. Spawn 2-3 workers (theme-config, toggle-ui, css-vars)
3. Monitor until all PRs merge
4. Run `/review` and `/qcode` quality checks
5. Fix any critical issues immediately
6. Add suggestions to `TASKS_BACKLOG.md`
7. Generate Slack post for stakeholders
8. Deliver summary and notify you

### Example Slack Post Output

```
🚀 Dark Mode Toggle - Complete!

**What We Did**
Added a dark mode toggle to the site header that remembers your preference.

**Why It Matters**
Users can now choose their preferred viewing experience, reducing eye strain and improving accessibility.

**How to Test**
1. Visit any page on the site
2. Click the moon/sun icon in the top-right corner
3. The theme should switch and persist when you refresh

**Links**
- PR: #42
```
