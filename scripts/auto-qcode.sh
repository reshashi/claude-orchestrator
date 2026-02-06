#!/usr/bin/env bash
# Automated Code Quality/Simplification - Heuristic cleanup
# This runs the mechanical/static parts of /qcode automatically
#
# Usage: auto-qcode.sh [--fix] [--dry-run]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Options
FIX_MODE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --fix) FIX_MODE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) shift ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           AUTOMATED CODE QUALITY                             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

FIXES_APPLIED=0
FIXES_AVAILABLE=0

report_fix() {
    local type="$1"
    local message="$2"
    local fixed="$3"

    if [ "$fixed" = true ]; then
        echo -e "  ${GREEN}[FIXED]${NC} $message"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
    else
        echo -e "  ${YELLOW}[AVAILABLE]${NC} $message"
        FIXES_AVAILABLE=$((FIXES_AVAILABLE + 1))
    fi
}

# ============================================================
# FIX 1: Remove trailing whitespace
# ============================================================
echo -e "\n${YELLOW}[1/6] Checking trailing whitespace...${NC}"

TRAILING_WS_FILES=$(git ls-files '*.ts' '*.js' '*.tsx' '*.jsx' '*.py' '*.md' '*.json' 2>/dev/null | xargs grep -l '[[:space:]]$' 2>/dev/null || true)

if [ -n "$TRAILING_WS_FILES" ]; then
    count=$(echo "$TRAILING_WS_FILES" | wc -l | tr -d ' ')
    if [ "$FIX_MODE" = true ]; then
        for file in $TRAILING_WS_FILES; do
            if [ "$DRY_RUN" = false ]; then
                sed -i '' 's/[[:space:]]*$//' "$file" 2>/dev/null || sed -i 's/[[:space:]]*$//' "$file"
            fi
        done
        report_fix "whitespace" "$count file(s) with trailing whitespace" true
    else
        report_fix "whitespace" "$count file(s) with trailing whitespace" false
    fi
else
    echo -e "  ${GREEN}✓ No trailing whitespace${NC}"
fi

# ============================================================
# FIX 2: Ensure files end with newline
# ============================================================
echo -e "\n${YELLOW}[2/6] Checking final newlines...${NC}"

MISSING_NEWLINE=0
while IFS= read -r file; do
    if [ -f "$file" ] && [ -s "$file" ]; then
        # Check if file ends with newline
        if [ "$(tail -c1 "$file" | wc -l)" -eq 0 ]; then
            MISSING_NEWLINE=$((MISSING_NEWLINE + 1))
            if [ "$FIX_MODE" = true ] && [ "$DRY_RUN" = false ]; then
                echo "" >> "$file"
            fi
        fi
    fi
done < <(git ls-files '*.ts' '*.js' '*.tsx' '*.jsx' '*.py' '*.sh' 2>/dev/null || true)

if [ $MISSING_NEWLINE -gt 0 ]; then
    if [ "$FIX_MODE" = true ]; then
        report_fix "newline" "$MISSING_NEWLINE file(s) missing final newline" true
    else
        report_fix "newline" "$MISSING_NEWLINE file(s) missing final newline" false
    fi
else
    echo -e "  ${GREEN}✓ All files end with newline${NC}"
fi

# ============================================================
# FIX 3: Run Prettier (if available)
# ============================================================
echo -e "\n${YELLOW}[3/6] Checking code formatting (Prettier)...${NC}"

if [ -f "package.json" ]; then
    if command -v npx &> /dev/null && [ -f "node_modules/.bin/prettier" ]; then
        if [ "$FIX_MODE" = true ]; then
            if [ "$DRY_RUN" = false ]; then
                npx prettier --write "**/*.{ts,tsx,js,jsx,json,md}" 2>/dev/null || true
            fi
            report_fix "prettier" "Code formatted with Prettier" true
        else
            UNFORMATTED=$(npx prettier --check "**/*.{ts,tsx,js,jsx,json,md}" 2>&1 | grep -c "Forgot to run" || echo "0")
            if [ "$UNFORMATTED" -gt 0 ]; then
                report_fix "prettier" "$UNFORMATTED unformatted file(s)" false
            else
                echo -e "  ${GREEN}✓ All files properly formatted${NC}"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠ Prettier not installed${NC}"
    fi
fi

# ============================================================
# FIX 4: Run ESLint --fix (if available)
# ============================================================
echo -e "\n${YELLOW}[4/6] Running ESLint auto-fix...${NC}"

if [ -f "package.json" ]; then
    SCRIPTS=$(node -e "console.log(Object.keys(require('./package.json').scripts || {}).join(' '))" 2>/dev/null || echo "")

    if echo "$SCRIPTS" | grep -qE "lint:fix|lint --fix"; then
        if [ "$FIX_MODE" = true ]; then
            if [ "$DRY_RUN" = false ]; then
                npm run lint:fix 2>/dev/null || npm run lint -- --fix 2>/dev/null || true
            fi
            report_fix "eslint" "ESLint auto-fixes applied" true
        else
            echo -e "  ${YELLOW}⚠ Run with --fix to apply ESLint fixes${NC}"
        fi
    elif echo "$SCRIPTS" | grep -qw "lint"; then
        if [ "$FIX_MODE" = true ]; then
            if [ "$DRY_RUN" = false ]; then
                npm run lint -- --fix 2>/dev/null || true
            fi
            report_fix "eslint" "ESLint auto-fixes applied" true
        fi
    else
        echo -e "  ${YELLOW}⚠ No lint script found${NC}"
    fi
fi

# ============================================================
# FIX 5: Remove console.log (with confirmation)
# ============================================================
echo -e "\n${YELLOW}[5/6] Checking removable console.log statements...${NC}"

CONSOLE_FILES=$(git ls-files '*.ts' '*.js' '*.tsx' '*.jsx' 2>/dev/null | grep -v '\.test\.' | grep -v '__tests__' | xargs grep -l 'console\.log' 2>/dev/null || true)

if [ -n "$CONSOLE_FILES" ]; then
    count=$(echo "$CONSOLE_FILES" | wc -l | tr -d ' ')
    if [ "$FIX_MODE" = true ]; then
        echo -e "  ${YELLOW}⚠ $count file(s) with console.log - manual review recommended${NC}"
        echo "    Files: $(echo "$CONSOLE_FILES" | tr '\n' ' ' | head -c 100)..."
    else
        report_fix "console" "$count file(s) with console.log statements" false
    fi
else
    echo -e "  ${GREEN}✓ No console.log statements in production code${NC}"
fi

# ============================================================
# FIX 6: Sort imports (if tool available)
# ============================================================
echo -e "\n${YELLOW}[6/6] Checking import organization...${NC}"

if command -v npx &> /dev/null && [ -f "node_modules/.bin/organize-imports-cli" ]; then
    if [ "$FIX_MODE" = true ]; then
        if [ "$DRY_RUN" = false ]; then
            npx organize-imports-cli tsconfig.json 2>/dev/null || true
        fi
        report_fix "imports" "Imports organized" true
    fi
else
    echo -e "  ${YELLOW}⚠ organize-imports-cli not installed${NC}"
fi

# ============================================================
# SUMMARY
# ============================================================
echo -e "\n${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    QCODE SUMMARY                              ${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"

if [ "$FIX_MODE" = true ]; then
    echo -e "\n  ${GREEN}Fixes Applied:${NC}    $FIXES_APPLIED"
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}(Dry run - no changes made)${NC}"
    fi
else
    echo -e "\n  ${YELLOW}Fixes Available:${NC}  $FIXES_AVAILABLE"
    echo -e "\n  Run with ${BLUE}--fix${NC} to apply automatic fixes"
fi

echo -e "\n${BLUE}══════════════════════════════════════════════════════════════${NC}\n"

if [ "$FIX_MODE" = true ]; then
    echo -e "${GREEN}✓ Code quality fixes applied${NC}"
else
    echo -e "${GREEN}✓ Code quality check complete${NC}"
fi
