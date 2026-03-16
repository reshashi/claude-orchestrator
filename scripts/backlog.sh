#!/usr/bin/env bash
# Tasks Backlog Management
# Usage: backlog.sh <command> [args]
#   backlog.sh add <title> [--priority critical|important|suggestion] [--source project|review|manual]
#   backlog.sh list [--status pending|completed|all] [--priority critical|important|suggestion] [--limit N]
#   backlog.sh complete <id>
#   backlog.sh delete <id>
#   backlog.sh search <query>
#   backlog.sh stats

set -e

# Resolve memory directory
if [[ -n "${CLAUDE_MEMORY_DIR:-}" ]]; then
    MEMORY_DIR="$CLAUDE_MEMORY_DIR"
elif [[ -d "$HOME/.claude/orchestrator/global" ]]; then
    MEMORY_DIR="$HOME/.claude/orchestrator/global"
else
    MEMORY_DIR="$HOME/.claude/orchestrator/global"
    mkdir -p "$MEMORY_DIR"
fi

DB_PATH="$MEMORY_DIR/memory.db"

# Check if sqlite3 is available
if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 is required but not installed." >&2
    exit 1
fi

# Initialize database if needed (create tables if they don't exist)
init_db() {
    if [ ! -f "$DB_PATH" ]; then
        # Try to use the Node.js memory service to initialize
        if command -v node &> /dev/null && [ -f "$HOME/.claude-orchestrator/dist/index.js" ]; then
            cd "$HOME/.claude-orchestrator" && node -e "
                const { MemoryService } = require('./dist/memory/index.js');
                const svc = new MemoryService({ dataDir: '$MEMORY_DIR' });
                svc.initialize();
                svc.shutdown();
            " 2>/dev/null || true
        fi

        # If still no DB, create minimal schema
        if [ ! -f "$DB_PATH" ]; then
            sqlite3 "$DB_PATH" << 'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tasks_backlog (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL DEFAULT 'manual',
    priority TEXT NOT NULL DEFAULT 'suggestion',
    title TEXT NOT NULL,
    description TEXT,
    file_path TEXT,
    line_number INTEGER,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL,
    completed_at TEXT,
    metadata TEXT
);
CREATE INDEX IF NOT EXISTS idx_backlog_status ON tasks_backlog(status);
CREATE INDEX IF NOT EXISTS idx_backlog_priority ON tasks_backlog(priority);
INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (2, datetime('now'));
SQL
        fi
    fi
}

add_task() {
    local title="$1"
    local priority="${2:-suggestion}"
    local source="${3:-manual}"
    local description="${4:-}"
    local file_path="${5:-}"
    local line_number="${6:-}"

    if [ -z "$title" ]; then
        echo "Error: title is required" >&2
        echo "Usage: backlog.sh add <title> [--priority critical|important|suggestion] [--source project|review|manual]" >&2
        exit 1
    fi

    init_db

    # Dedup: skip if an identical pending task already exists
    local escaped_title
    escaped_title=$(echo "$title" | sed "s/'/''/g")
    local existing
    existing=$(sqlite3 "$DB_PATH" "SELECT id FROM tasks_backlog WHERE title = '$escaped_title' AND status = 'pending' LIMIT 1;")
    if [ -n "$existing" ]; then
        echo "Skipped (duplicate of #$existing): $title"
        return 0
    fi

    local created_at
    created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local id
    id=$(sqlite3 "$DB_PATH" << SQL
INSERT INTO tasks_backlog (source, priority, title, description, file_path, line_number, status, created_at)
VALUES ('$source', '$priority', '$escaped_title',
        $([ -n "$description" ] && echo "'$(echo "$description" | sed "s/'/''/g")'" || echo "NULL"),
        $([ -n "$file_path" ] && echo "'$file_path'" || echo "NULL"),
        $([ -n "$line_number" ] && echo "$line_number" || echo "NULL"),
        'pending', '$created_at');
SELECT last_insert_rowid();
SQL
)

    echo "Added task #$id: $title (priority: $priority, source: $source)"
}

list_tasks() {
    local status_filter="${1:-pending}"
    local priority_filter="${2:-}"
    local limit="${3:-50}"

    init_db

    local where_clause="WHERE status != 'deleted'"

    if [ "$status_filter" != "all" ]; then
        where_clause="$where_clause AND status = '$status_filter'"
    fi

    if [ -n "$priority_filter" ]; then
        where_clause="$where_clause AND priority = '$priority_filter'"
    fi

    echo "=== Tasks Backlog ==="
    echo ""

    sqlite3 -header -column "$DB_PATH" << SQL
SELECT
    id,
    priority,
    substr(title, 1, 60) as title,
    source,
    status,
    date(created_at) as created
FROM tasks_backlog
$where_clause
ORDER BY
    CASE priority WHEN 'critical' THEN 1 WHEN 'important' THEN 2 WHEN 'suggestion' THEN 3 END,
    created_at DESC
LIMIT $limit;
SQL

    echo ""

    # Show summary counts
    local pending
    pending=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks_backlog WHERE status = 'pending'")
    local in_progress
    in_progress=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks_backlog WHERE status = 'in_progress'")
    local completed
    completed=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks_backlog WHERE status = 'completed'")

    echo "Summary: $pending pending, $in_progress in progress, $completed completed"
}

complete_task() {
    local id="$1"

    if [ -z "$id" ]; then
        echo "Error: task ID is required" >&2
        echo "Usage: backlog.sh complete <id>" >&2
        exit 1
    fi

    init_db

    local completed_at
    completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local changes
    changes=$(sqlite3 "$DB_PATH" << SQL
UPDATE tasks_backlog SET status = 'completed', completed_at = '$completed_at' WHERE id = $id;
SELECT changes();
SQL
)

    if [ "$changes" -gt 0 ]; then
        echo "Completed task #$id"
    else
        echo "Task #$id not found" >&2
        exit 1
    fi
}

delete_task() {
    local id="$1"

    if [ -z "$id" ]; then
        echo "Error: task ID is required" >&2
        echo "Usage: backlog.sh delete <id>" >&2
        exit 1
    fi

    init_db

    local changes
    changes=$(sqlite3 "$DB_PATH" << SQL
UPDATE tasks_backlog SET status = 'deleted' WHERE id = $id;
SELECT changes();
SQL
)

    if [ "$changes" -gt 0 ]; then
        echo "Deleted task #$id"
    else
        echo "Task #$id not found" >&2
        exit 1
    fi
}

search_tasks() {
    local query="$1"

    if [ -z "$query" ]; then
        echo "Error: search query is required" >&2
        echo "Usage: backlog.sh search <query>" >&2
        exit 1
    fi

    init_db

    echo "=== Search Results for: $query ==="
    echo ""

    sqlite3 -header -column "$DB_PATH" << SQL
SELECT
    id,
    priority,
    substr(title, 1, 60) as title,
    source,
    status
FROM tasks_backlog
WHERE status != 'deleted'
  AND (title LIKE '%$query%' OR description LIKE '%$query%')
ORDER BY
    CASE priority WHEN 'critical' THEN 1 WHEN 'important' THEN 2 WHEN 'suggestion' THEN 3 END,
    created_at DESC
LIMIT 50;
SQL
}

show_stats() {
    init_db

    echo "=== Backlog Statistics ==="
    echo ""

    echo "By Status:"
    sqlite3 "$DB_PATH" "SELECT status, COUNT(*) as count FROM tasks_backlog GROUP BY status ORDER BY count DESC;"
    echo ""

    echo "By Priority (excluding deleted):"
    sqlite3 "$DB_PATH" "SELECT priority, COUNT(*) as count FROM tasks_backlog WHERE status != 'deleted' GROUP BY priority ORDER BY CASE priority WHEN 'critical' THEN 1 WHEN 'important' THEN 2 WHEN 'suggestion' THEN 3 END;"
    echo ""

    echo "By Source (excluding deleted):"
    sqlite3 "$DB_PATH" "SELECT source, COUNT(*) as count FROM tasks_backlog WHERE status != 'deleted' GROUP BY source ORDER BY count DESC;"
}

get_task() {
    local id="$1"

    if [ -z "$id" ]; then
        echo "Error: task ID is required" >&2
        echo "Usage: backlog.sh get <id>" >&2
        exit 1
    fi

    init_db

    sqlite3 -header -column "$DB_PATH" << SQL
SELECT * FROM tasks_backlog WHERE id = $id;
SQL
}

next_task() {
    local mode="${1:-any}"
    init_db

    # Mode: prd = only PRD tasks, regular = non-PRD tasks, any = PRDs first then regular
    local result=""

    if [ "$mode" = "prd" ] || [ "$mode" = "any" ]; then
        # Try PRD tasks first (have prd_id in metadata)
        result=$(sqlite3 -json "$DB_PATH" << 'SQL'
SELECT id, source, priority, title, description, file_path, line_number, status, created_at, metadata
FROM tasks_backlog
WHERE status = 'pending'
  AND metadata IS NOT NULL
  AND json_extract(metadata, '$.prd_id') IS NOT NULL
  AND (metadata IS NULL OR metadata NOT LIKE '%"autopilot_attempts":2%')
ORDER BY
    CASE priority
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'important' THEN 3
        WHEN 'medium' THEN 4
        WHEN 'suggestion' THEN 5
    END,
    json_extract(metadata, '$.series_order') ASC,
    created_at ASC
LIMIT 1;
SQL
)
    fi

    # If no PRD task found and mode allows regular tasks
    if ([ -z "$result" ] || [ "$result" = "[]" ]) && ([ "$mode" = "regular" ] || [ "$mode" = "any" ]); then
        result=$(sqlite3 -json "$DB_PATH" << 'SQL'
SELECT id, source, priority, title, description, file_path, line_number, status, created_at, metadata
FROM tasks_backlog
WHERE status = 'pending'
  AND title NOT LIKE '%INFRASTRUCTURE%'
  AND title NOT LIKE '%insurance%'
  AND title NOT LIKE '%attorney%'
  AND title NOT LIKE '%Privacy Officer%'
  AND title NOT LIKE '%Security Officer%'
  AND title NOT LIKE '%BAA%'
  AND title NOT LIKE '%HIPAA Risk Assessment%'
  AND title NOT LIKE '%cyber liability%'
  AND title NOT LIKE '%staging environment%'
  AND (metadata IS NULL OR json_extract(metadata, '$.prd_id') IS NULL)
  AND (metadata IS NULL OR metadata NOT LIKE '%"autopilot_attempts":2%')
ORDER BY
    CASE priority
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'important' THEN 3
        WHEN 'medium' THEN 4
        WHEN 'suggestion' THEN 5
    END,
    created_at ASC
LIMIT 1;
SQL
)
    fi

    if [ -z "$result" ] || [ "$result" = "[]" ]; then
        echo "{}"
        return 1
    fi

    # sqlite3 -json returns an array; extract the first element
    echo "$result" | jq -c '.[0]'
}

# ---------------------------------------------------------------------------
# PRD Ingest: Parse YAML frontmatter from a PRD file and create a backlog entry
# ---------------------------------------------------------------------------
prd_ingest() {
    local prd_path="$1"

    if [ -z "$prd_path" ] || [ ! -f "$prd_path" ]; then
        echo "Error: PRD file not found: ${prd_path:-<none>}" >&2
        echo "Usage: backlog.sh prd-ingest <path-to-prd.md>" >&2
        exit 1
    fi

    init_db

    # Extract YAML frontmatter between --- delimiters
    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$prd_path" | sed '1d;$d')

    if [ -z "$frontmatter" ]; then
        echo "Error: No YAML frontmatter found in $prd_path" >&2
        exit 1
    fi

    # Parse YAML fields (simple key: value extraction — no yq dependency)
    local prd_id series series_order priority
    prd_id=$(echo "$frontmatter" | grep '^prd_id:' | sed 's/^prd_id:[[:space:]]*//')
    series=$(echo "$frontmatter" | grep '^series:' | sed 's/^series:[[:space:]]*//')
    series_order=$(echo "$frontmatter" | grep '^series_order:' | sed 's/^series_order:[[:space:]]*//')
    priority=$(echo "$frontmatter" | grep '^priority:' | sed 's/^priority:[[:space:]]*//')

    # Parse depends_on array (lines starting with "  - ")
    local depends_on_json
    depends_on_json=$(echo "$frontmatter" | sed -n '/^depends_on:/,/^[^ ]/p' | grep '^  - ' | sed 's/^  - //' | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo "[]")

    if [ -z "$prd_id" ]; then
        echo "Error: prd_id not found in frontmatter of $prd_path" >&2
        exit 1
    fi

    # Deduplicate on prd_id
    local existing
    existing=$(sqlite3 "$DB_PATH" "SELECT id FROM tasks_backlog WHERE status != 'deleted' AND metadata IS NOT NULL AND json_extract(metadata, '\$.prd_id') = '$prd_id' LIMIT 1;")
    if [ -n "$existing" ]; then
        echo "Skipped (duplicate prd_id '$prd_id', existing task #$existing)"
        return 0
    fi

    # Extract title from first markdown heading
    local title
    title=$(grep -m1 '^# ' "$prd_path" | sed 's/^# //')
    [ -z "$title" ] && title="PRD: $prd_id"

    # Build metadata JSON
    local metadata
    metadata=$(jq -n -c \
        --arg prd_id "$prd_id" \
        --arg series "$series" \
        --argjson series_order "${series_order:-0}" \
        --argjson depends_on "$depends_on_json" \
        --arg prd_file "$prd_path" \
        '{
            prd_id: $prd_id,
            series: $series,
            series_order: $series_order,
            depends_on: $depends_on,
            prd_file: $prd_file
        }')

    local created_at
    created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local escaped_title
    escaped_title=$(echo "$title" | sed "s/'/''/g")
    local escaped_meta
    escaped_meta=$(echo "$metadata" | sed "s/'/''/g")

    local id
    id=$(sqlite3 "$DB_PATH" << SQL
INSERT INTO tasks_backlog (source, priority, title, description, file_path, status, created_at, metadata)
VALUES ('prd', '${priority:-important}', '$escaped_title', 'Auto-ingested from PRD file', '$prd_path', 'pending', '$created_at', '$escaped_meta');
SELECT last_insert_rowid();
SQL
)

    echo "Ingested PRD task #$id: $title (prd_id: $prd_id, series: ${series:-none}, order: ${series_order:-0})"
}

# ---------------------------------------------------------------------------
# PRD Deps: Show dependency status for a PRD task
# ---------------------------------------------------------------------------
prd_deps() {
    local task_id="$1"

    if [ -z "$task_id" ]; then
        echo "Error: task ID is required" >&2
        echo "Usage: backlog.sh prd-deps <task_id>" >&2
        exit 1
    fi

    init_db

    # Get this task's metadata
    local meta
    meta=$(sqlite3 "$DB_PATH" "SELECT metadata FROM tasks_backlog WHERE id = $task_id;")

    if [ -z "$meta" ]; then
        echo "Error: Task #$task_id not found" >&2
        exit 1
    fi

    local prd_id
    prd_id=$(echo "$meta" | jq -r '.prd_id // empty')
    if [ -z "$prd_id" ]; then
        echo "Task #$task_id is not a PRD task (no prd_id in metadata)"
        return 0
    fi

    echo "=== PRD Dependencies for Task #$task_id ($prd_id) ==="
    echo ""

    # Get depends_on list
    local deps
    deps=$(echo "$meta" | jq -r '.depends_on[]? // empty' 2>/dev/null)

    if [ -z "$deps" ]; then
        echo "No dependencies — ready to execute."
        return 0
    fi

    local all_resolved=true
    while IFS= read -r dep_prd_id; do
        [ -z "$dep_prd_id" ] && continue
        local dep_info
        dep_info=$(sqlite3 -json "$DB_PATH" "SELECT id, status, title FROM tasks_backlog WHERE metadata IS NOT NULL AND json_extract(metadata, '\$.prd_id') = '$dep_prd_id' AND status != 'deleted' LIMIT 1;" 2>/dev/null | jq -c '.[0] // empty')

        if [ -z "$dep_info" ]; then
            echo "  [ ] $dep_prd_id — NOT INGESTED"
            all_resolved=false
        else
            local dep_status dep_task_id
            dep_status=$(echo "$dep_info" | jq -r '.status')
            dep_task_id=$(echo "$dep_info" | jq -r '.id')
            if [ "$dep_status" = "completed" ]; then
                echo "  [x] $dep_prd_id (task #$dep_task_id) — completed"
            else
                echo "  [ ] $dep_prd_id (task #$dep_task_id) — $dep_status"
                all_resolved=false
            fi
        fi
    done <<< "$deps"

    echo ""
    if [ "$all_resolved" = true ]; then
        echo "All dependencies resolved — ready to execute."
    else
        echo "Blocked — unresolved dependencies remain."
    fi
}

start_task() {
    local id="$1"
    local run_id="${2:-}"

    if [ -z "$id" ]; then
        echo "Error: task ID is required" >&2
        echo "Usage: backlog.sh start <id> [run_id]" >&2
        exit 1
    fi

    init_db

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Read current metadata and increment attempts
    local current_meta
    current_meta=$(sqlite3 "$DB_PATH" "SELECT COALESCE(metadata, '{}') FROM tasks_backlog WHERE id = $id;")
    if [ -z "$current_meta" ] || [ "$current_meta" = "" ]; then
        current_meta="{}"
    fi

    local new_meta
    new_meta=$(echo "$current_meta" | jq -c --arg ts "$now" --arg rid "$run_id" '
        .autopilot_started_at = $ts |
        .autopilot_run_id = $rid |
        .autopilot_attempts = ((.autopilot_attempts // 0) + 1)
    ')

    local escaped_meta
    escaped_meta=$(echo "$new_meta" | sed "s/'/''/g")

    local changes
    changes=$(sqlite3 "$DB_PATH" << SQL
UPDATE tasks_backlog SET status = 'in_progress', metadata = '$escaped_meta' WHERE id = $id AND status = 'pending';
SELECT changes();
SQL
)

    if [ "$changes" -gt 0 ]; then
        echo "Started task #$id (run: ${run_id:-none})"
    else
        echo "Task #$id not found or not in pending status" >&2
        exit 1
    fi
}

reset_task() {
    local id="$1"

    if [ -z "$id" ]; then
        echo "Error: task ID is required" >&2
        exit 1
    fi

    init_db

    local changes
    changes=$(sqlite3 "$DB_PATH" << SQL
UPDATE tasks_backlog SET status = 'pending' WHERE id = $id AND status = 'in_progress';
SELECT changes();
SQL
)

    if [ "$changes" -gt 0 ]; then
        echo "Reset task #$id to pending"
    else
        echo "Task #$id not found or not in_progress" >&2
        exit 1
    fi
}

dedup_tasks() {
    init_db

    # Find and remove duplicate pending tasks (keep lowest ID)
    local removed
    removed=$(sqlite3 "$DB_PATH" << 'SQL'
DELETE FROM tasks_backlog
WHERE id NOT IN (
    SELECT MIN(id) FROM tasks_backlog
    WHERE status = 'pending'
    GROUP BY title
)
AND status = 'pending'
AND id NOT IN (
    SELECT MIN(id) FROM tasks_backlog
    WHERE status = 'pending'
    GROUP BY title
);
SELECT changes();
SQL
)

    echo "Removed $removed duplicate pending tasks"
}

cleanup_garbage() {
    init_db

    # Remove entries that are clearly code fragments, not real tasks
    # (less than 10 chars, contain shell syntax, etc.)
    local removed
    removed=$(sqlite3 "$DB_PATH" << 'SQL'
UPDATE tasks_backlog SET status = 'deleted'
WHERE status = 'pending'
AND (
    length(title) < 10
    OR title LIKE '%${%'
    OR title LIKE '%$(%'
    OR title LIKE '%\${NC}%'
    OR title LIKE '%2>/dev/null%'
    OR title LIKE '%]; then%'
    OR title LIKE '%_FILES%'
    OR title LIKE '%...${%'
    OR title LIKE '%CHANGEME%'
    OR title GLOB '*[|]*[|]*'
);
SELECT changes();
SQL
)

    echo "Cleaned up $removed garbage entries"
}

show_help() {
    echo "Tasks Backlog Management"
    echo ""
    echo "Usage: backlog.sh <command> [args]"
    echo ""
    echo "Commands:"
    echo "  add <title> [options]     - Add a new task (skips duplicates)"
    echo "    --priority <level>      - critical, important, or suggestion (default: suggestion)"
    echo "    --source <source>       - project, review, or manual (default: manual)"
    echo "    --description <text>    - Optional description"
    echo "    --file <path>           - Optional file path reference"
    echo "    --line <number>         - Optional line number reference"
    echo ""
    echo "  list [options]            - List tasks"
    echo "    --status <status>       - pending, completed, or all (default: pending)"
    echo "    --priority <level>      - Filter by priority"
    echo "    --limit <n>             - Limit results (default: 50)"
    echo ""
    echo "  get <id>                  - Get full details of a task"
    echo "  complete <id>             - Mark task as completed"
    echo "  delete <id>               - Delete a task (soft delete)"
    echo "  search <query>            - Search tasks by title or description"
    echo "  stats                     - Show backlog statistics"
    echo "  next [--mode prd|regular|any]  - Get highest-priority actionable item (JSON)"
    echo "  start <id> [run_id]       - Mark task as in_progress for autopilot"
    echo "  reset <id>                - Reset in_progress task back to pending"
    echo "  dedup                     - Remove duplicate pending tasks"
    echo "  cleanup                   - Remove garbage entries (code fragments)"
    echo "  prd-ingest <path>         - Ingest a PRD file into the backlog"
    echo "  prd-deps <id>             - Show dependency status for a PRD task"
    echo ""
    echo "Examples:"
    echo "  backlog.sh add 'Add input validation to API' --priority important --source review"
    echo "  backlog.sh list --status pending --priority critical"
    echo "  backlog.sh complete 42"
    echo "  backlog.sh search 'validation'"
    echo "  backlog.sh dedup"
}

# Parse command and arguments
command="${1:-}"
shift || true

case "$command" in
    add)
        # Parse options
        title=""
        priority="suggestion"
        source="manual"
        description=""
        file_path=""
        line_number=""

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --priority) priority="$2"; shift 2 ;;
                --source) source="$2"; shift 2 ;;
                --description) description="$2"; shift 2 ;;
                --file) file_path="$2"; shift 2 ;;
                --line) line_number="$2"; shift 2 ;;
                *)
                    if [ -z "$title" ]; then
                        title="$1"
                    else
                        title="$title $1"
                    fi
                    shift
                    ;;
            esac
        done

        add_task "$title" "$priority" "$source" "$description" "$file_path" "$line_number"
        ;;
    list)
        status="pending"
        priority=""
        limit="50"

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --status) status="$2"; shift 2 ;;
                --priority) priority="$2"; shift 2 ;;
                --limit) limit="$2"; shift 2 ;;
                *) shift ;;
            esac
        done

        list_tasks "$status" "$priority" "$limit"
        ;;
    get) get_task "$1" ;;
    complete) complete_task "$1" ;;
    delete) delete_task "$1" ;;
    search) search_tasks "$*" ;;
    stats) show_stats ;;
    next)
        mode="any"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --mode) mode="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        next_task "$mode"
        ;;
    start) start_task "$1" "$2" ;;
    reset) reset_task "$1" ;;
    dedup) dedup_tasks ;;
    cleanup) cleanup_garbage ;;
    prd-ingest) prd_ingest "$1" ;;
    prd-deps) prd_deps "$1" ;;
    -h|--help|help|"") show_help ;;
    *) echo "Unknown command: $command"; show_help; exit 1 ;;
esac
