#!/bin/bash
# Claude Code Orchestrator - Installation Script
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/[org]/claude-orchestrator/main/install.sh | bash
#   ./install.sh [-y] [-v VERSION]
#
# Options:
#   -y, --yes       Skip confirmation prompts
#   -v, --version   Install specific version (default: latest)
#   --uninstall     Remove installation
#   --update        Update to latest version

set -eo pipefail

# Configuration
VERSION="${VERSION:-local}"
REPO="${REPO:-reshashi/claude-orchestrator}"
INSTALL_DIR="$HOME/.claude-orchestrator"
CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
COMMANDS_DIR="$CLAUDE_DIR/commands"
AGENTS_DIR="$CLAUDE_DIR/agents"
TEMPLATES_DIR="$INSTALL_DIR/templates"
WORKTREES_DIR="$HOME/.worktrees"

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Parse arguments
FORCE=false
UNINSTALL=false
UPDATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            FORCE=true
            shift
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --update)
            UPDATE=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Utility functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running from curl (no script directory)
is_curl_install() {
    [[ ! -f "$(dirname "$0")/scripts/orchestrator.sh" ]]
}

# Get latest version from GitHub
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | \
        grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || echo "unknown"
}

# Get installed version
get_installed_version() {
    if [[ -f "$INSTALL_DIR/version" ]]; then
        cat "$INSTALL_DIR/version"
    else
        echo "none"
    fi
}

# Detect shell profile
detect_shell_profile() {
    local shell_name
    shell_name=$(basename "$SHELL")

    case "$shell_name" in
        zsh)
            if [[ -f "$HOME/.zshrc" ]]; then
                echo "$HOME/.zshrc"
            else
                echo "$HOME/.zprofile"
            fi
            ;;
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                echo "$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.profile"
            fi
            ;;
        fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            echo "$HOME/.profile"
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    local has_errors=false

    info "Checking prerequisites..."

    # macOS check (required)
    if [[ "$(uname)" != "Darwin" ]]; then
        error "This tool is macOS-only (requires iTerm2 + AppleScript)"
        error "For other platforms, see: https://github.com/$REPO#other-platforms"
        exit 1
    fi
    success "macOS detected"

    # iTerm2 check (required)
    if [[ ! -d "/Applications/iTerm.app" ]]; then
        error "iTerm2 not found at /Applications/iTerm.app"
        error "Please install from: https://iterm2.com"
        has_errors=true
    else
        success "iTerm2 found"
    fi

    # Git check (required)
    if ! command -v git &> /dev/null; then
        error "git not found. Please install git."
        has_errors=true
    else
        # Check git version for worktree support
        local git_version
        git_version=$(git --version | awk '{print $3}')
        if [[ "$(printf '%s\n' "2.20" "$git_version" | sort -V | head -n1)" != "2.20" ]]; then
            warn "Git version $git_version may have limited worktree support. Recommend 2.20+"
        else
            success "Git $git_version (worktree support: OK)"
        fi
    fi

    # Claude Code CLI check (warning only)
    if ! command -v claude &> /dev/null; then
        warn "Claude Code CLI not found. Install from: https://claude.ai/code"
    else
        success "Claude Code CLI found"
    fi

    # GitHub CLI check (warning only)
    if ! command -v gh &> /dev/null; then
        warn "GitHub CLI (gh) not found. Some features require it."
        warn "Install with: brew install gh"
    else
        success "GitHub CLI found"
    fi

    # jq check (required for project mode in v2.0)
    if ! command -v jq &> /dev/null; then
        warn "jq not found. Required for /project command (v2.0)."
        warn "Install with: brew install jq"
    else
        success "jq found"
    fi

    if [[ "$has_errors" == true ]]; then
        error "Prerequisites check failed. Please fix the errors above."
        exit 1
    fi

    echo ""
}

# Uninstall function
uninstall() {
    info "Uninstalling Claude Code Orchestrator..."

    local profile
    profile=$(detect_shell_profile)

    # Remove aliases from shell profile
    if [[ -f "$profile" ]]; then
        # Create backup
        cp "$profile" "$profile.bak"

        # Remove orchestrator block
        sed -i '' '/# Claude Code Orchestrator/,/^$/d' "$profile" 2>/dev/null || true
        success "Removed aliases from $profile (backup: $profile.bak)"
    fi

    # Remove symlinks (but not the directories themselves)
    info "Removing symlinks..."
    for script in orchestrator.sh orchestrator-loop.sh orchestrator-stop.sh orchestrator-status.sh \
                  start-worker.sh start-all-workers.sh worker-init.sh worker-read.sh \
                  worker-send.sh worker-status.sh wt.sh; do
        if [[ -L "$SCRIPTS_DIR/$script" ]]; then
            rm "$SCRIPTS_DIR/$script"
        fi
    done

    # Remove install directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        success "Removed $INSTALL_DIR"
    fi

    echo ""
    success "Uninstallation complete!"
    echo ""
    echo "Note: Commands in ~/.claude/commands/ and agents in ~/.claude/agents/ were preserved."
    echo "To fully remove, run: rm -rf ~/.claude/commands ~/.claude/agents"
}

# Install function
install() {
    local source_dir

    echo ""
    echo -e "${GREEN}Claude Code Orchestrator${NC}"
    echo "================================"
    echo ""

    # Determine source (curl download vs local clone)
    if is_curl_install; then
        info "Installing from GitHub..."

        # Download and extract
        local tmp_dir
        tmp_dir=$(mktemp -d)
        trap "rm -rf $tmp_dir" EXIT

        if [[ "$VERSION" == "latest" || "$VERSION" == "local" ]]; then
            VERSION=$(get_latest_version)
            if [[ "$VERSION" == "unknown" ]]; then
                error "Could not determine latest version. Check your internet connection."
                exit 1
            fi
        fi

        info "Downloading version $VERSION..."
        curl -fsSL "https://github.com/$REPO/archive/refs/tags/v$VERSION.tar.gz" | \
            tar -xz -C "$tmp_dir" --strip-components=1

        source_dir="$tmp_dir"
    else
        info "Installing from local directory..."
        source_dir="$(cd "$(dirname "$0")" && pwd)"

        # Use version file if present, otherwise "local"
        if [[ -f "$source_dir/version" ]]; then
            VERSION=$(cat "$source_dir/version")
        else
            VERSION="local"
        fi
    fi

    info "Version: $VERSION"
    echo ""

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$SCRIPTS_DIR"
    mkdir -p "$COMMANDS_DIR"
    mkdir -p "$AGENTS_DIR"
    mkdir -p "$WORKTREES_DIR"

    # Create memory directories (v2.4)
    MEMORY_DIR="$CLAUDE_DIR/memory"
    mkdir -p "$MEMORY_DIR/projects"
    mkdir -p "$MEMORY_DIR/sessions"

    # Copy memory templates if they don't exist (v2.4)
    for template in memory-toolchain.json memory-repos.json memory-facts.json; do
        local target_file="$MEMORY_DIR/${template#memory-}"
        if [[ ! -f "$target_file" && -f "$source_dir/templates/$template" ]]; then
            cp "$source_dir/templates/$template" "$target_file"
            info "  Created $target_file from template"
        fi
    done

    # Copy source to install directory (for reference/updates)
    if [[ "$source_dir" != "$INSTALL_DIR" ]]; then
        cp -r "$source_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
    fi

    # Save version
    echo "$VERSION" > "$INSTALL_DIR/version"

    # Install scripts (symlink for easy updates)
    info "Installing scripts..."
    for script in "$source_dir/scripts/"*.sh; do
        local script_name
        script_name=$(basename "$script")

        # Remove existing (file or symlink)
        rm -f "$SCRIPTS_DIR/$script_name"

        # Create symlink
        ln -sf "$INSTALL_DIR/scripts/$script_name" "$SCRIPTS_DIR/$script_name"
    done
    chmod +x "$SCRIPTS_DIR"/*.sh 2>/dev/null || true
    success "Scripts installed to $SCRIPTS_DIR"

    # Install commands (copy, preserve user customizations)
    info "Installing commands..."
    for cmd in "$source_dir/commands/"*.md; do
        local cmd_name
        cmd_name=$(basename "$cmd")

        if [[ -f "$COMMANDS_DIR/$cmd_name" ]]; then
            # Don't overwrite existing (user may have customized)
            if [[ "$FORCE" == true ]]; then
                cp "$cmd" "$COMMANDS_DIR/$cmd_name"
            else
                info "  Skipping $cmd_name (already exists, use -y to overwrite)"
            fi
        else
            cp "$cmd" "$COMMANDS_DIR/$cmd_name"
        fi
    done
    success "Commands installed to $COMMANDS_DIR"

    # Install agents (copy, preserve user customizations)
    info "Installing agents..."
    for agent in "$source_dir/agents/"*.md; do
        local agent_name
        agent_name=$(basename "$agent")

        if [[ -f "$AGENTS_DIR/$agent_name" ]]; then
            if [[ "$FORCE" == true ]]; then
                cp "$agent" "$AGENTS_DIR/$agent_name"
            else
                info "  Skipping $agent_name (already exists, use -y to overwrite)"
            fi
        else
            cp "$agent" "$AGENTS_DIR/$agent_name"
        fi
    done
    success "Agents installed to $AGENTS_DIR"

    # Add shell aliases
    local profile
    profile=$(detect_shell_profile)

    if ! grep -q "# Claude Code Orchestrator" "$profile" 2>/dev/null; then
        info "Adding shell aliases to $profile..."

        cat >> "$profile" << 'ALIASES'

# Claude Code Orchestrator
alias wt='~/.claude/scripts/wt.sh'
alias workers='~/.claude/scripts/orchestrator.sh'
alias orchestrator-start='~/.claude/scripts/orchestrator-loop.sh &'
alias orchestrator-stop='~/.claude/scripts/orchestrator-stop.sh'
alias orchestrator-status='~/.claude/scripts/orchestrator-status.sh'
alias claude-orchestrator='~/.claude/scripts/claude-orchestrator'

ALIASES
        success "Added aliases to $profile"
    else
        info "Shell aliases already configured"
    fi

    echo ""
    print_success
}

# Print success message
print_success() {
    local profile
    profile=$(detect_shell_profile)

    echo -e "${GREEN}Installation complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your terminal or run:"
    echo "     source $profile"
    echo ""
    echo "  2. Start Claude in your project:"
    echo "     cd your-project && claude"
    echo ""
    echo "  3. Run a full project autonomously (NEW in v2.0):"
    echo "     /project \"Add user authentication with magic links\""
    echo ""
    echo "     OR spawn workers manually:"
    echo "     /spawn auth \"implement authentication\""
    echo "     /spawn api \"create API endpoints\""
    echo ""
    echo "Quick commands:"
    echo "  /project \"desc\"        Full autonomous project (v2.0)"
    echo "  /spawn <name> \"task\"   Create worker in new iTerm tab"
    echo "  /status                Check all worktrees and workers"
    echo "  /workers list          List active worker tabs"
    echo "  /merge <name>          Merge worker branch and cleanup"
    echo ""
    echo "Fully automated mode:"
    echo "  orchestrator-start     Start background orchestrator loop"
    echo "  orchestrator-stop      Stop the loop"
    echo "  orchestrator-status    Check loop status"
    echo ""
    echo "Documentation: https://github.com/$REPO"
}

# Main
main() {
    if [[ "$UNINSTALL" == true ]]; then
        uninstall
        exit 0
    fi

    check_prerequisites

    if [[ "$UPDATE" == true ]]; then
        local current
        current=$(get_installed_version)
        local latest
        latest=$(get_latest_version)

        if [[ "$current" == "$latest" ]]; then
            success "Already at latest version ($current)"
            exit 0
        fi

        info "Updating from $current to $latest..."
        VERSION="$latest"
    fi

    install
}

main "$@"
