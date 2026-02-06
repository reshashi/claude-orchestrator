---
description: Execute a complete project from concept to delivery - the Planner orchestrates workers, reviews, and delivers
allowed-tools: Bash(*), Read, Write, Grep, Glob, Task
---

# /project - Autonomous Project Execution

Execute a complete project from a conceptual description. The Planner will:
1. Generate a comprehensive PRD
2. Break work into parallel tasks (or execute directly if simple)
3. Implement the work
4. **Run quality gates**: `/review` and `/qcode` (MANDATORY)
5. **Fix critical issues immediately** before proceeding
6. **Add suggestions to backlog database** via `~/.claude/scripts/backlog.sh`
7. Iterate if needed (max 3 times)
8. Generate Slack post for stakeholders
9. Deliver summary and notify you

## Quality Rules (MANDATORY)

These rules apply to ALL projects, regardless of size:

1. **Quality Gates Are Required**: `/review` and `/qcode` MUST run for every project
   - For simple tasks: run directly in the main session
   - For complex tasks: run after all workers complete

2. **Critical Issues Block Merge**: Any 🔴 Critical issue from `/review` MUST be fixed before proceeding

3. **Suggestions Go to Backlog**: All 🟡 Important and 🟢 Suggestion findings are added to the backlog database:
   ```bash
   ~/.claude/scripts/backlog.sh add "Description" --priority important --source review
   ```

4. **Security Scan**: `npm audit --audit-level=high` runs on every project

## Arguments
- $ARGUMENTS: The project description (what you want to build)

## Context
- Repo root: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`
- Project structure: !`find . -type d -maxdepth 2 -not -path '*/\.*' -not -path './node_modules/*' | head -30`

## Instructions

### Simple vs Complex Tasks

**Simple Task** (implement directly):
- Single-file changes or small modifications
- Clear, self-contained scope
- No parallel work needed
- Still requires quality gates!

**Complex Task** (use workers):
- Multiple files across different domains
- Work can be parallelized
- Multiple days of effort
- Benefits from isolation

For simple tasks, skip worker spawning and implement directly, then run quality gates.

### Resuming After Context Compaction

If you're resuming this project after context was compacted:
1. Read the PRD file (check `~/.claude/project-state.json` for `prd_path`)
2. Go directly to **Section 6: Execution Status** in the PRD
3. The "Current State" tells you what phase you're in
4. The "Phase Checklist" shows what's done
5. Resume from the appropriate phase below

### Phase 1: PRD Generation (CONCEPTUALIZING)

Think deeply about the project requirements. Consider:
- What is the user trying to accomplish?
- What files need to be created or modified?
- Is this simple enough to implement directly, or does it need workers?
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

## 4. Implementation Approach

### Simple Implementation (if applicable)
If this is a simple task, describe what will be done directly:
- [Step 1]
- [Step 2]

### Worker Task Breakdown (if complex)

#### Worker 1: [short-name]
- **Task**: [Specific description of what this worker does]
- **Owns**: [files/directories this worker can modify]
- **Off-limits**: [files this worker must NOT touch]
- **Depends on**: [other worker names, or "none"]

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
- [ ] Phase 2: Implementation Started
- [ ] Phase 3: Implementation Complete
- [ ] Phase 4: Review Complete
- [ ] Phase 5: Quality Gates Passed
- [ ] Phase 6: Deliverables Generated
- [ ] Phase 7: Project Complete

### Blockers & Issues
- None yet

### Quality Gate Results
- [ ] `/review`: pending
- [ ] `/qcode`: pending
- [ ] Security scan: pending
- [ ] Critical issues fixed: N/A

### Backlog Items Added
- None yet

### Log
- [timestamp] Project created
```

### Phase 2: Initialize Project State

**Update PRD Status**: Change Phase to `IMPLEMENTING`, check off Phase 1, add log entry.

Create the project state file:

```bash
cat > ~/.claude/project-state.json << JSONEOF
{
  "project_name": "${PROJECT_NAME}",
  "prd_path": "${REPO_ROOT}/prds/${PRD_FILENAME}",
  "prd_filename": "${PRD_FILENAME}",
  "status": "implementing",
  "iteration": 1,
  "max_iterations": 3,
  "is_simple": false,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "completed_at": null,
  "feedback_history": []
}
JSONEOF
```

### Phase 3: Implementation

**For Simple Tasks**: Implement directly in the main session, then proceed to Phase 4.

**For Complex Tasks**: Use the Task tool to spawn worker agents:

```
Use Task tool with subagent_type appropriate for each worker task
```

After all workers complete, update status and proceed to Phase 4.

### Phase 4: Review Implementation (REVIEWING)

**Update PRD Status**: Set Phase to `REVIEWING`, add log entry.

Review the changes:
```bash
git log --oneline main..HEAD
git diff main --stat
```

For each success criterion, verify it is met by:
1. Reading the relevant files
2. Running any test commands
3. Checking the implementation matches requirements

### Phase 5: Run Quality Gates (QUALITY_GATES) - MANDATORY

**Update PRD Status**: Set Phase to `QUALITY_GATES`.

**THESE ARE REQUIRED FOR ALL PROJECTS**:

1. **Run QA Guardian Review**:
```bash
/review
```
This will:
- Check architecture policy compliance
- Verify test coverage hasn't decreased
- Check code quality standards
- Identify security issues

2. **Run Code Simplifier**:
```bash
/qcode
```
This will:
- Remove unnecessary complexity
- Improve code readability
- Ensure consistent patterns

3. **Run Security Scan**:
```bash
npm audit --audit-level=high
```

4. **Run DevOps Check** (if infrastructure changed):
```bash
/deploy
```

### Phase 6: Address Review Findings (REMEDIATION)

**CRITICAL**: Act on review findings immediately.

**1. Fix Critical Issues (🔴)**:
- Fix them NOW before proceeding
- Re-run failing checks to verify
- Do NOT proceed until all critical issues are resolved

**2. Add Important & Suggestions to Backlog (🟡 🟢)**:
Use the backlog database instead of markdown files:

```bash
# For important issues
~/.claude/scripts/backlog.sh add "Missing input validation on API endpoint" \
  --priority important --source review

# For suggestions
~/.claude/scripts/backlog.sh add "Consider using shared Card component" \
  --priority suggestion --source review
```

Update the PRD's "Backlog Items Added" section with what was added.

### Phase 7: Decision Point

**If ALL requirements met AND no critical issues** → Go to Phase 8 (Deliverables)

**If requirements NOT met AND iteration < 3**:
1. Increment iteration in project-state.json
2. Write feedback to `~/.claude/feedback/${PROJECT_NAME}-iteration-${N}.md`
3. Fix unmet requirements
4. Go back to Phase 4

**If requirements NOT met AND iteration >= 3**:
1. Update status to "needs_human"
2. Notify human:
```bash
echo -e "\a"
osascript -e 'display notification "After 3 iterations, some requirements still not met. Manual intervention required." with title "Project Needs Human Review" sound name "Glass"'
```
3. Display what still needs to be done
4. Exit

### Phase 8: Generate Deliverables (GENERATING_DELIVERABLES)

**Update PRD Status**: Set Phase to `GENERATING_DELIVERABLES`, add log entry.

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
- Quality Gate Results
- Backlog Items (count and link to `/backlog list`)

### Phase 9: Generate Slack Post (COMMUNICATION)

**IMPORTANT**: Generate a Slack-ready post for non-technical stakeholders.

Create `SLACK_POST.md` in the deliverables directory:

```bash
cat > ~/.claude/deliverables/${PROJECT_NAME}/SLACK_POST.md << 'SLACKEOF'
# Slack Post: ${PROJECT_NAME}

Copy the content below into Slack:

---

## [Project Title] - Complete!

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

### Phase 10: Notify Human (PROJECT_COMPLETE)

**Update PRD Status**: Set Phase to `COMPLETE`, add final log entry.

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
BACKLOG: X items added (run /backlog list)
========================================
```

## Important Notes

- **Quality Gates Are Mandatory**: Every project runs `/review` and `/qcode`. No exceptions.
- **Critical Issues Block**: 🔴 Critical issues must be fixed before proceeding.
- **Suggestions to Database**: All suggestions go to the backlog database, not markdown files.
- **Iteration Limit**: Maximum 3 feedback iterations before escalating to human.
- **Stakeholder Communication**: Every project generates a non-technical Slack post.
- **Context Recovery**: The PRD's "Execution Status" section is the source of truth.

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
2. Implement the feature (directly or via workers)
3. Run `/review` and `/qcode` quality checks
4. Fix any critical issues immediately
5. Add suggestions to backlog database
6. Generate Slack post for stakeholders
7. Deliver summary and notify you

### Example Slack Post Output

```
Dark Mode Toggle - Complete!

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
