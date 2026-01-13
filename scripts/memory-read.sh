#!/bin/bash
# Read from memory files
# Usage: memory-read.sh <type> [name/search]
#   memory-read.sh toolchain [name]  - Read toolchain entry
#   memory-read.sh repos [name]      - Read repo entry
#   memory-read.sh facts [search]    - Search facts
#   memory-read.sh all               - Dump all memory

set -e

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude/memory}"
TOOLCHAIN_FILE="$MEMORY_DIR/toolchain.json"
REPOS_FILE="$MEMORY_DIR/repos.json"
FACTS_FILE="$MEMORY_DIR/facts.json"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# Initialize memory directory and files if they don't exist
init_memory() {
    if [ ! -d "$MEMORY_DIR" ]; then
        mkdir -p "$MEMORY_DIR"
    fi

    # Get script directory to find templates
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEMPLATE_DIR="$SCRIPT_DIR/../templates"

    if [ ! -f "$TOOLCHAIN_FILE" ]; then
        if [ -f "$TEMPLATE_DIR/memory-toolchain.json" ]; then
            cp "$TEMPLATE_DIR/memory-toolchain.json" "$TOOLCHAIN_FILE"
        else
            echo '{"$schema": "memory-toolchain-schema", "$description": "Tools and CLIs"}' > "$TOOLCHAIN_FILE"
        fi
    fi

    if [ ! -f "$REPOS_FILE" ]; then
        if [ -f "$TEMPLATE_DIR/memory-repos.json" ]; then
            cp "$TEMPLATE_DIR/memory-repos.json" "$REPOS_FILE"
        else
            echo '{"$schema": "memory-repos-schema", "$description": "Known repositories"}' > "$REPOS_FILE"
        fi
    fi

    if [ ! -f "$FACTS_FILE" ]; then
        if [ -f "$TEMPLATE_DIR/memory-facts.json" ]; then
            cp "$TEMPLATE_DIR/memory-facts.json" "$FACTS_FILE"
        else
            echo '{"$schema": "memory-facts-schema", "$description": "Facts to remember", "facts": []}' > "$FACTS_FILE"
        fi
    fi
}

read_toolchain() {
    local name="$1"
    init_memory

    if [ -z "$name" ]; then
        # List all toolchain entries
        jq -r 'to_entries | map(select(.key | startswith("$") | not)) | .[].key' "$TOOLCHAIN_FILE"
    else
        # Get specific entry
        jq -r ".[\"$name\"] // empty" "$TOOLCHAIN_FILE"
    fi
}

read_repos() {
    local name="$1"
    init_memory

    if [ -z "$name" ]; then
        # List all repo entries
        jq -r 'to_entries | map(select(.key | startswith("$") | not)) | .[].key' "$REPOS_FILE"
    else
        # Get specific entry
        jq -r ".[\"$name\"] // empty" "$REPOS_FILE"
    fi
}

read_facts() {
    local search="$1"
    init_memory

    if [ -z "$search" ]; then
        # List all facts
        jq -r '.facts[] | "\(.id): \(.content)"' "$FACTS_FILE"
    else
        # Search facts
        jq -r ".facts[] | select(.content | test(\"$search\"; \"i\")) | \"\(.id): \(.content)\"" "$FACTS_FILE"
    fi
}

read_all() {
    init_memory

    echo "=== Toolchain ==="
    jq '.' "$TOOLCHAIN_FILE"
    echo ""
    echo "=== Repos ==="
    jq '.' "$REPOS_FILE"
    echo ""
    echo "=== Facts ==="
    jq '.' "$FACTS_FILE"
}

show_help() {
    echo "Memory Read - Access Claude's persistent memory"
    echo ""
    echo "Usage: memory-read.sh <type> [name/search]"
    echo ""
    echo "Commands:"
    echo "  toolchain [name]  - Read toolchain entry (list all if no name)"
    echo "  repos [name]      - Read repo entry (list all if no name)"
    echo "  facts [search]    - Search facts (list all if no search)"
    echo "  all               - Dump all memory files"
    echo ""
    echo "Environment:"
    echo "  CLAUDE_MEMORY_DIR - Override memory directory (default: ~/.claude/memory)"
}

case "$1" in
    toolchain) read_toolchain "$2" ;;
    repos) read_repos "$2" ;;
    facts) read_facts "$2" ;;
    all) read_all ;;
    -h|--help|help) show_help ;;
    *) show_help; exit 1 ;;
esac
