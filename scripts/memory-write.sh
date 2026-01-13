#!/bin/bash
# Write to memory files
# Usage: memory-write.sh <type> <args...>
#   memory-write.sh toolchain <name> <json>  - Add/update toolchain entry
#   memory-write.sh repos <name> <json>      - Add/update repo entry
#   memory-write.sh fact <text>              - Add a fact

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

write_toolchain() {
    local name="$1"
    local json="$2"

    if [ -z "$name" ] || [ -z "$json" ]; then
        echo "Error: toolchain requires <name> and <json>" >&2
        echo "Usage: memory-write.sh toolchain <name> '<json>'" >&2
        exit 1
    fi

    init_memory

    # Validate JSON
    if ! echo "$json" | jq . > /dev/null 2>&1; then
        echo "Error: Invalid JSON provided" >&2
        exit 1
    fi

    # Update the file
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg name "$name" --argjson value "$json" '.[$name] = $value' "$TOOLCHAIN_FILE" > "$tmp_file"
    mv "$tmp_file" "$TOOLCHAIN_FILE"

    echo "Added/updated toolchain entry: $name"
}

write_repos() {
    local name="$1"
    local json="$2"

    if [ -z "$name" ] || [ -z "$json" ]; then
        echo "Error: repos requires <name> and <json>" >&2
        echo "Usage: memory-write.sh repos <name> '<json>'" >&2
        exit 1
    fi

    init_memory

    # Validate JSON
    if ! echo "$json" | jq . > /dev/null 2>&1; then
        echo "Error: Invalid JSON provided" >&2
        exit 1
    fi

    # Update the file
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg name "$name" --argjson value "$json" '.[$name] = $value' "$REPOS_FILE" > "$tmp_file"
    mv "$tmp_file" "$REPOS_FILE"

    echo "Added/updated repo entry: $name"
}

write_fact() {
    local text="$1"
    local category="${2:-general}"

    if [ -z "$text" ]; then
        echo "Error: fact requires <text>" >&2
        echo "Usage: memory-write.sh fact '<text>' [category]" >&2
        exit 1
    fi

    init_memory

    # Generate unique ID
    local id
    id="fact-$(date +%s)-$RANDOM"
    local added
    added=$(date +%Y-%m-%d)

    # Add the fact
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg id "$id" --arg category "$category" --arg content "$text" --arg added "$added" \
        '.facts += [{"id": $id, "category": $category, "content": $content, "added": $added}]' \
        "$FACTS_FILE" > "$tmp_file"
    mv "$tmp_file" "$FACTS_FILE"

    echo "Added fact: $id"
}

delete_fact() {
    local id="$1"

    if [ -z "$id" ]; then
        echo "Error: delete-fact requires <id>" >&2
        echo "Usage: memory-write.sh delete-fact <id>" >&2
        exit 1
    fi

    init_memory

    # Delete the fact
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg id "$id" '.facts = [.facts[] | select(.id != $id)]' "$FACTS_FILE" > "$tmp_file"
    mv "$tmp_file" "$FACTS_FILE"

    echo "Deleted fact: $id"
}

show_help() {
    echo "Memory Write - Update Claude's persistent memory"
    echo ""
    echo "Usage: memory-write.sh <command> <args...>"
    echo ""
    echo "Commands:"
    echo "  toolchain <name> <json>    - Add/update toolchain entry"
    echo "  repos <name> <json>        - Add/update repo entry"
    echo "  fact <text> [category]     - Add a fact (category: general, preference, context)"
    echo "  delete-fact <id>           - Delete a fact by ID"
    echo ""
    echo "Examples:"
    echo "  memory-write.sh toolchain node '{\"version\": \"20.x\", \"install\": \"nvm install 20\"}'"
    echo "  memory-write.sh repos myapp '{\"url\": \"https://github.com/me/app\", \"default_branch\": \"main\"}'"
    echo "  memory-write.sh fact 'Prefer TypeScript over JavaScript' preference"
    echo ""
    echo "Environment:"
    echo "  CLAUDE_MEMORY_DIR - Override memory directory (default: ~/.claude/memory)"
}

case "$1" in
    toolchain) write_toolchain "$2" "$3" ;;
    repos) write_repos "$2" "$3" ;;
    fact) write_fact "$2" "$3" ;;
    delete-fact) delete_fact "$2" ;;
    -h|--help|help) show_help ;;
    *) show_help; exit 1 ;;
esac
