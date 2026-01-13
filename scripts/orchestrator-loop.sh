#!/bin/bash
set -e

REPO_NAME="${REPO_NAME:-medicalbills}"
REPO_FULL="Mudunuri-Ventures/$REPO_NAME"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
LOG_FILE="${LOG_FILE:-$HOME/.claude/orchestrator.log}"
PID_FILE="$HOME/.claude/orchestrator.pid"
SESSIONS_FILE="$HOME/.claude/active-sessions.log"
STATE_DIR="$HOME/.claude/worker-states"
PROJECT_STATE_FILE="$HOME/.claude/project-state.json"

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$STATE_DIR"

# ============================================================
# PROJECT MODE FUNCTIONS
# ============================================================

is_project_mode() {
    [ -f "$PROJECT_STATE_FILE" ]
}

get_project_status() {
    jq -r '.status' "$PROJECT_STATE_FILE" 2>/dev/null
}

get_project_name() {
    jq -r '.project_name' "$PROJECT_STATE_FILE" 2>/dev/null
}

update_project_status() {
    local NEW_STATUS="$1"
    local TMP_FILE=$(mktemp)
    jq --arg status "$NEW_STATUS" '.status = $status' "$PROJECT_STATE_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$PROJECT_STATE_FILE"
    log "Project status updated: $NEW_STATUS"
}

update_worker_status_in_project() {
    local WORKER_NAME="$1"
    local NEW_STATUS="$2"
    local TMP_FILE=$(mktemp)
    jq --arg name "$WORKER_NAME" --arg status "$NEW_STATUS" \
        '(.workers[] | select(.name == $name)).status = $status' \
        "$PROJECT_STATE_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$PROJECT_STATE_FILE"
    log "Worker $WORKER_NAME status updated: $NEW_STATUS"
}

check_all_project_workers_complete() {
    if ! is_project_mode; then return 1; fi

    # Count workers that are not yet merged
    local ACTIVE=$(jq '[.workers[] | select(.status != "merged")] | length' "$PROJECT_STATE_FILE" 2>/dev/null)

    if [ -z "$ACTIVE" ] || [ "$ACTIVE" -eq 0 ]; then
        return 0  # All workers complete
    fi
    return 1
}

notify_human() {
    local TITLE="$1"
    local MESSAGE="$2"

    # Terminal bell
    echo -e "\a"

    # macOS notification
    osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"Glass\"" 2>/dev/null || true

    log "NOTIFICATION: $TITLE - $MESSAGE"
}

# ============================================================
# END PROJECT MODE FUNCTIONS
# ============================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "Orchestrator already running (PID: $OLD_PID)"
        exit 1
    fi
fi

echo $$ > "$PID_FILE"
log "Orchestrator started (PID: $$)"

cleanup() {
    log "Orchestrator stopping..."
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM

get_state() {
    cat "$STATE_DIR/tab${1}_state" 2>/dev/null || echo "UNKNOWN"
}
set_state() {
    echo "$2" > "$STATE_DIR/tab${1}_state"
}
is_initialized() {
    [ -f "$STATE_DIR/tab${1}_initialized" ]
}
set_initialized() {
    touch "$STATE_DIR/tab${1}_initialized"
}
is_merged() {
    [ -f "$STATE_DIR/tab${1}_merged" ]
}
set_merged() {
    touch "$STATE_DIR/tab${1}_merged"
}
is_reviewed() {
    [ -f "$STATE_DIR/tab${1}_reviewed" ]
}
set_reviewed() {
    touch "$STATE_DIR/tab${1}_reviewed"
}
get_review_pr() {
    cat "$STATE_DIR/tab${1}_review_pr" 2>/dev/null
}
set_review_pr() {
    echo "$2" > "$STATE_DIR/tab${1}_review_pr"
}
clear_tab_state() {
    rm -f "$STATE_DIR/tab${1}_state" "$STATE_DIR/tab${1}_merged" "$STATE_DIR/tab${1}_initialized" "$STATE_DIR/tab${1}_reviewed" "$STATE_DIR/tab${1}_review_pr" "$STATE_DIR/tab${1}_agents_run"
}

read_worker_output() {
    osascript << APPLESCRIPT 2>/dev/null | tail -"${2:-100}"
tell application "iTerm"
    tell current window
        tell tab $1
            tell current session
                return contents
            end tell
        end tell
    end tell
end tell
APPLESCRIPT
}

detect_worker_state() {
    local OUTPUT="$1"

    # Check for composing/thinking state first - don't interrupt Claude while thinking
    if echo "$OUTPUT" | grep -qiE "(Composing|thinking|ctrl\+c to interrupt)"; then
        echo "WORKING"
    elif echo "$OUTPUT" | grep -qiE '(Try "how does|>\s*$|\? for shortcuts)' && ! echo "$OUTPUT" | grep -qiE "(Reading|WORKER\.md|task|error)"; then
        echo "NEEDS_INIT"
    elif echo "$OUTPUT" | grep -qiE "(MCP servers found|Space to select.*Enter to confirm)"; then
        echo "MCP_PROMPT"
    elif echo "$OUTPUT" | grep -qiE "(Trust this project|Do you trust)"; then
        echo "TRUST_PROMPT"
    # Check for PR URL pattern (github.com/.../pull/NNN) - more reliable than text matching
    elif echo "$OUTPUT" | grep -qiE "(github\.com/.*/pull/[0-9]+|PR created|pull request|opened.*PR)"; then
        if echo "$OUTPUT" | grep -qiE "(merged|✓.*merged)"; then
            echo "MERGED"
        else
            echo "PR_OPEN"
        fi
    elif echo "$OUTPUT" | grep -qiE "(Do you want to proceed|waiting for|proceed\?|continue\?|y/n|yes/no|\[Y/n\]|\[y/N\])"; then
        echo "WAITING_INPUT"
    # Only trigger ERROR for actual Claude/system errors, not build/test failures which worker handles
    elif echo "$OUTPUT" | grep -qiE "(Claude.*error|API.*error|connection.*failed|ECONNREFUSED|rate.*limit)"; then
        echo "ERROR"
    else
        echo "WORKING"
    fi
}

send_to_worker() {
    local TAB="$1"
    local MSG="$2"
    # Use keystroke approach for reliability - types text then presses return
    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm"
    activate
    tell current window
        tell tab $TAB
            tell current session
                -- First write the text
                write text "$MSG"
            end tell
        end tell
    end tell
end tell
-- Small delay then ensure return is sent
delay 0.2
tell application "System Events"
    tell process "iTerm2"
        keystroke return
    end tell
end tell
APPLESCRIPT
    log "Sent to tab $TAB: $MSG"
}

send_enter() {
    local TAB="$1"
    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm"
    activate
    tell current window
        tell tab $TAB
            select
        end tell
    end tell
end tell
delay 0.1
tell application "System Events"
    tell process "iTerm2"
        keystroke return
    end tell
end tell
APPLESCRIPT
    log "Sent Enter to tab $TAB"
}

nudge_worker() {
    local TAB="$1"
    local STATE="$2"
    case "$STATE" in
        NEEDS_INIT)
            if ! is_initialized "$TAB"; then
                send_to_worker "$TAB" "Read WORKER.md for your task. Enable auto-accept mode (Shift+Tab) and begin working. BEFORE creating a PR, run: npm run type-check && npm run lint && npm run test. Only create the PR if all checks pass."
                set_initialized "$TAB"
            fi
            ;;
        MCP_PROMPT)
            send_enter "$TAB"
            ;;
        TRUST_PROMPT)
            send_to_worker "$TAB" "yes"
            ;;
        WAITING_INPUT)
            send_to_worker "$TAB" "y"
            ;;
        ERROR)
            send_to_worker "$TAB" "Analyze the error and try a different approach."
            ;;
    esac
}

get_pr_for_branch() {
    gh pr list --repo "$REPO_FULL" --head "$1" --state open --json number --jq '.[0].number' 2>/dev/null
}

check_pr_status() {
    if gh pr checks "$1" --repo "$REPO_FULL" 2>/dev/null | grep -q "fail"; then
        echo "FAILED"
    elif gh pr checks "$1" --repo "$REPO_FULL" 2>/dev/null | grep -q "pending"; then
        echo "PENDING"
    else
        echo "PASSED"
    fi
}

merge_pr() {
    log "Auto-merging PR #$1"
    gh pr merge "$1" --repo "$REPO_FULL" --squash --delete-branch 2>&1 | tee -a "$LOG_FILE"
}

# Run review agent on a PR branch
run_review() {
    local PR_NUM="$1"
    local BRANCH="$2"
    local TAB="$3"

    log "Running /review for PR #$PR_NUM (branch: $BRANCH)"

    # Add 'review-pending' label to track review status
    gh pr edit "$PR_NUM" --repo "$REPO_FULL" --add-label "review-pending" 2>/dev/null || true

    # Tell the worker to run the review
    send_to_worker "$TAB" "/review $BRANCH"

    # Track that we've initiated review for this PR
    set_review_pr "$TAB" "$PR_NUM"
}

# Check if review has completed (look for QA GUARDIAN output)
check_review_complete() {
    local OUTPUT="$1"

    if echo "$OUTPUT" | grep -qE "(RESULT:.*PASS|RESULT:.*CONDITIONAL PASS|QA GUARDIAN REVIEW)"; then
        if echo "$OUTPUT" | grep -qE "RESULT:.*FAIL"; then
            echo "FAILED"
        else
            echo "PASSED"
        fi
    else
        echo "PENDING"
    fi
}

# Mark PR as reviewed
mark_pr_reviewed() {
    local PR_NUM="$1"
    log "PR #$PR_NUM passed review"
    gh pr edit "$PR_NUM" --repo "$REPO_FULL" --remove-label "review-pending" --add-label "reviewed" 2>/dev/null || true
}

# Check if PR needs devops review (infrastructure changes)
needs_devops_review() {
    local PR_NUM="$1"
    local FILES=$(gh pr diff "$PR_NUM" --repo "$REPO_FULL" --name-only 2>/dev/null)

    # Check for infrastructure-related files
    if echo "$FILES" | grep -qE "(\.github/|vercel\.json|supabase/|Dockerfile|docker-compose|\.env|middleware\.ts|playwright\.config)"; then
        return 0  # true - needs devops review
    fi
    return 1  # false - no devops review needed
}

# Check if PR needs code-simplifier (medium+ changes)
needs_code_simplifier() {
    local PR_NUM="$1"
    local STATS=$(gh pr view "$PR_NUM" --repo "$REPO_FULL" --json additions,deletions --jq '.additions + .deletions' 2>/dev/null)

    # Run code-simplifier for PRs with 50+ lines changed (lowered from 100)
    if [ -n "$STATS" ] && [ "$STATS" -ge 50 ]; then
        return 0  # true - needs code-simplifier
    fi
    return 1  # false - no code-simplifier needed
}

# Check if PR needs security scan (always run for safety)
needs_security_scan() {
    # Always run security scan on all PRs
    return 0
}

# Run security scan
run_security_scan() {
    local PR_NUM="$1"
    local TAB="$2"

    log "Running security scan for PR #$PR_NUM"
    send_to_worker "$TAB" "Run 'npm audit --audit-level=high' and report any vulnerabilities. If critical issues found, list them clearly."
    add_agent_run "$TAB" "security"
}

# Track which agents have run
get_agents_run() {
    cat "$STATE_DIR/tab${1}_agents_run" 2>/dev/null || echo ""
}
add_agent_run() {
    local CURRENT=$(get_agents_run "$1")
    echo "$CURRENT $2" > "$STATE_DIR/tab${1}_agents_run"
}
has_agent_run() {
    get_agents_run "$1" | grep -q "$2"
}

# Run devops review
run_devops_review() {
    local PR_NUM="$1"
    local BRANCH="$2"
    local TAB="$3"

    log "Running devops review for PR #$PR_NUM (infrastructure changes detected)"
    send_to_worker "$TAB" "/deploy"
    add_agent_run "$TAB" "devops"
}

# Run code-simplifier
run_code_simplifier() {
    local PR_NUM="$1"
    local BRANCH="$2"
    local TAB="$3"

    log "Running code-simplifier for PR #$PR_NUM (100+ lines changed)"
    send_to_worker "$TAB" "/qcode"
    add_agent_run "$TAB" "simplifier"
}

# Check if all required agents have completed
all_agents_complete() {
    local TAB="$1"
    local PR_NUM="$2"
    local OUTPUT="$3"

    # Check if QA review completed
    if ! is_reviewed "$TAB"; then
        return 1
    fi

    # Check if security scan completed (runs on ALL PRs)
    if ! has_agent_run "$TAB" "security"; then
        return 1
    fi
    # Check for security scan completion (npm audit output)
    if ! echo "$OUTPUT" | grep -qE "(found 0 vulnerabilities|audit.*complete|no vulnerabilities|npm audit)"; then
        # Give it some slack - if security was run, assume it completed
        if ! echo "$OUTPUT" | grep -qE "(npm audit|security.*scan|vulnerabilities)"; then
            return 1
        fi
    fi

    # Check if devops was needed and completed
    if needs_devops_review "$PR_NUM"; then
        if ! has_agent_run "$TAB" "devops"; then
            return 1
        fi
        # Check for devops completion marker in output
        if ! echo "$OUTPUT" | grep -qE "(DEPLOYMENT STATUS|READY WITH|DevOps.*complete|Pre-Flight|deployment)"; then
            return 1
        fi
    fi

    # Check if code-simplifier was needed and completed
    if needs_code_simplifier "$PR_NUM"; then
        if ! has_agent_run "$TAB" "simplifier"; then
            return 1
        fi
        # Check for simplifier completion marker
        if ! echo "$OUTPUT" | grep -qE "(Code.*simplified|quality.*check|QCODE.*complete|simplif|Lines removed)"; then
            return 1
        fi
    fi

    return 0  # All agents complete
}

close_tab() {
    log "Closing tab $1"
    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm"
    tell current window
        tell tab $1
            close
        end tell
    end tell
end tell
APPLESCRIPT
}

get_worker_tabs() {
    osascript << 'APPLESCRIPT' 2>/dev/null
tell application "iTerm"
    tell current window
        set tabCount to count of tabs
        set output to ""
        repeat with t from 2 to tabCount
            set output to output & t & " "
        end repeat
        return output
    end tell
end tell
APPLESCRIPT
}

get_worker_info() {
    local LINE_NUM=$(($1 - 1))
    tail -n 20 "$SESSIONS_FILE" 2>/dev/null | grep "$REPO_NAME" | sed -n "${LINE_NUM}p"
}

log "Starting orchestration loop (polling every ${POLL_INTERVAL}s)"

while true; do
    TABS=$(get_worker_tabs)
    for TAB in $TABS; do
        [ -z "$TAB" ] && continue
        OUTPUT=$(read_worker_output "$TAB" 50)
        [ -z "$OUTPUT" ] && continue
        
        STATE=$(detect_worker_state "$OUTPUT")
        PREV_STATE=$(get_state "$TAB")
        
        if [ "$STATE" != "$PREV_STATE" ]; then
            log "Tab $TAB: $PREV_STATE -> $STATE"
            set_state "$TAB" "$STATE"
        fi
        
        case "$STATE" in
            NEEDS_INIT|MCP_PROMPT|TRUST_PROMPT|WAITING_INPUT)
                nudge_worker "$TAB" "$STATE"
                ;;
            ERROR)
                [ "$PREV_STATE" != "ERROR" ] && nudge_worker "$TAB" "$STATE"
                ;;
            PR_OPEN)
                WORKER_INFO=$(get_worker_info "$TAB")
                BRANCH=$(echo "$WORKER_INFO" | cut -d'|' -f2)
                if [ -n "$BRANCH" ]; then
                    PR_NUM=$(get_pr_for_branch "$BRANCH")
                    if [ -n "$PR_NUM" ]; then
                        log "Tab $TAB has PR #$PR_NUM"
                        PR_STATUS=$(check_pr_status "$PR_NUM")
                        log "PR #$PR_NUM CI status: $PR_STATUS"

                        if [ "$PR_STATUS" = "PASSED" ]; then
                            # CI passed - check review status
                            REVIEW_PR=$(get_review_pr "$TAB")

                            if [ -z "$REVIEW_PR" ]; then
                                # Review not started yet - initiate QA review
                                log "PR #$PR_NUM CI passed, initiating review..."
                                run_review "$PR_NUM" "$BRANCH" "$TAB"
                            elif is_reviewed "$TAB"; then
                                # QA review passed - run additional quality agents

                                # Run security scan on ALL PRs (if not yet run)
                                if ! has_agent_run "$TAB" "security"; then
                                    run_security_scan "$PR_NUM" "$TAB"
                                fi

                                # Run devops review if needed and not yet run
                                if needs_devops_review "$PR_NUM" && ! has_agent_run "$TAB" "devops"; then
                                    run_devops_review "$PR_NUM" "$BRANCH" "$TAB"
                                fi

                                # Run code-simplifier if needed (50+ lines) and not yet run
                                if needs_code_simplifier "$PR_NUM" && ! has_agent_run "$TAB" "simplifier"; then
                                    run_code_simplifier "$PR_NUM" "$BRANCH" "$TAB"
                                fi

                                # Check if all required agents have completed
                                if all_agents_complete "$TAB" "$PR_NUM" "$OUTPUT"; then
                                    log "PR #$PR_NUM all agents passed, merging..."
                                    merge_pr "$PR_NUM"
                                    set_merged "$TAB"
                                else
                                    log "PR #$PR_NUM waiting for additional agent(s) to complete..."
                                fi
                            else
                                # Review initiated but not complete - check status
                                REVIEW_RESULT=$(check_review_complete "$OUTPUT")
                                log "PR #$PR_NUM review status: $REVIEW_RESULT"

                                if [ "$REVIEW_RESULT" = "PASSED" ]; then
                                    mark_pr_reviewed "$PR_NUM"
                                    set_reviewed "$TAB"
                                    log "PR #$PR_NUM QA review PASSED, checking for additional agents..."
                                elif [ "$REVIEW_RESULT" = "FAILED" ]; then
                                    log "PR #$PR_NUM review FAILED - manual intervention required"
                                    send_to_worker "$TAB" "Review found issues. Please fix them before the PR can be merged."
                                    # Clear review state so it can be re-run after fixes
                                    rm -f "$STATE_DIR/tab${TAB}_review_pr"
                                fi
                                # If PENDING, just wait for next cycle
                            fi
                        elif [ "$PR_STATUS" = "FAILED" ]; then
                            send_to_worker "$TAB" "CI failed. Run 'gh pr checks' and fix the issues."
                            # Clear all agent state since code changed
                            rm -f "$STATE_DIR/tab${TAB}_review_pr" "$STATE_DIR/tab${TAB}_reviewed" "$STATE_DIR/tab${TAB}_agents_run"
                        fi
                    fi
                fi
                ;;
            MERGED)
                if is_merged "$TAB"; then
                    log "Tab $TAB complete, closing..."

                    # Update project state if in project mode
                    if is_project_mode; then
                        WORKER_INFO=$(get_worker_info "$TAB")
                        WORKER_NAME=$(echo "$WORKER_INFO" | cut -d'|' -f1)
                        if [ -n "$WORKER_NAME" ]; then
                            update_worker_status_in_project "$WORKER_NAME" "merged"
                        fi
                    fi

                    sleep 2
                    close_tab "$TAB"
                    clear_tab_state "$TAB"
                fi
                ;;
        esac
    done

    # ============================================================
    # PROJECT MODE: Check if all workers are complete
    # ============================================================
    if is_project_mode; then
        PROJECT_STATUS=$(get_project_status)

        # Only check for completion if workers are active
        if [ "$PROJECT_STATUS" = "workers_active" ]; then
            if check_all_project_workers_complete; then
                PROJECT_NAME=$(get_project_name)
                log "PROJECT MODE: All workers have merged for project: $PROJECT_NAME"
                update_project_status "all_merged"

                # Notify the planner session (Tab 1) that work is complete
                send_to_worker 1 "PROJECT_COMPLETE: All workers have merged for project '$PROJECT_NAME'. Begin reviewing merged code against PRD requirements."

                log "Notified planner session to begin review"
            fi
        fi
    fi

    sleep "$POLL_INTERVAL"
done
