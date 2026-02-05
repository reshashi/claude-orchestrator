#!/usr/bin/env bash
# Migrate memory from ~/.claude/memory to ~/.claude/orchestrator/global
#
# Usage: migrate-memory.sh [--dry-run]
#
# This script migrates data from the legacy memory location to the new
# 3-tier memory structure introduced in v3.3. It is safe to run multiple
# times - it will skip files that already exist at the destination.

OLD_DIR="$HOME/.claude/memory"
NEW_DIR="$HOME/.claude/orchestrator/global"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Nothing to migrate
if [[ ! -d "$OLD_DIR" ]]; then
    echo "[OK] No legacy memory found at $OLD_DIR - nothing to migrate."
    exit 0
fi

# Already migrated
if [[ -f "$OLD_DIR/.migrated" ]]; then
    echo "[OK] Already migrated (marker found at $OLD_DIR/.migrated)."
    exit 0
fi

# New location already has data and old location exists - merge carefully
mkdir -p "$NEW_DIR"

migrated=0
skipped=0

for file in "$OLD_DIR"/*.json; do
    [[ -f "$file" ]] || continue
    filename=$(basename "$file")

    if [[ -f "$NEW_DIR/$filename" ]]; then
        if $DRY_RUN; then
            echo "[SKIP] $filename already exists at destination"
        fi
        skipped=$((skipped + 1))
    else
        if $DRY_RUN; then
            echo "[WOULD COPY] $filename → $NEW_DIR/$filename"
        else
            cp "$file" "$NEW_DIR/$filename"
            echo "[MIGRATED] $filename → $NEW_DIR/$filename"
        fi
        migrated=$((migrated + 1))
    fi
done

# Migrate subdirectories (projects/, sessions/)
for subdir in projects sessions; do
    if [[ -d "$OLD_DIR/$subdir" ]]; then
        if $DRY_RUN; then
            echo "[WOULD COPY] $subdir/ → $NEW_DIR/$subdir/"
        else
            cp -rn "$OLD_DIR/$subdir" "$NEW_DIR/" 2>/dev/null || true
            echo "[MIGRATED] $subdir/ → $NEW_DIR/$subdir/"
        fi
        migrated=$((migrated + 1))
    fi
done

if $DRY_RUN; then
    echo ""
    echo "[DRY RUN] Would migrate $migrated items, skip $skipped existing."
    echo "Run without --dry-run to execute."
else
    # Mark migration complete
    date -u +%Y-%m-%dT%H:%M:%SZ > "$OLD_DIR/.migrated"
    echo ""
    echo "[OK] Migration complete: $migrated migrated, $skipped skipped."
    echo "Legacy data preserved at $OLD_DIR (marked as migrated)."
fi
