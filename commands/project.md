---
description: Execute a complete project from concept to delivery - the Planner orchestrates workers, reviews, and delivers
allowed-tools: Bash(*), Read, Write, Grep, Glob, Task
---

# /project - Autonomous Project Execution

Execute a complete project from a conceptual description. The Planner will:
1. Generate a comprehensive PRD
2. Break work into parallel tasks
3. Spawn and manage workers
4. Review completed work
5. Iterate if needed (max 3 times)
6. Deliver summary and notify you

## Arguments
- $ARGUMENTS: The project description (what you want to build)

## Context
- Repo root: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`
- Project structure: !`find . -type d -maxdepth 2 -not -path '*/\.*' -not -path './node_modules/*' | head -30`

## Instructions

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
```

### Phase 2: Initialize Project State (SPAWNING_WORKERS)

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

### Phase 9: Notify Human (PROJECT_COMPLETE)

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
```

## Important Notes

- **File Ownership**: Each worker must have exclusive ownership of files. No two workers can modify the same file.
- **Off-limits Enforcement**: Workers are told which files they cannot touch. This prevents merge conflicts.
- **Iteration Limit**: Maximum 3 feedback iterations before escalating to human.
- **Quality Gates**: Each worker PR goes through QA Guardian review automatically.
- **Autonomous Operation**: After you type `/project`, you can walk away. You'll be notified when complete.

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
4. Review against success criteria
5. Generate summary and notify you
