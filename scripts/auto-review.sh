#!/usr/bin/env bash
# Automated Code Review - Heuristic quality checks
# This runs the mechanical/static parts of /review automatically
#
# Usage: auto-review.sh [--fix] [--add-to-backlog]

# shellcheck disable=SC2034  # FIX_MODE reserved for future auto-fix capability
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Options
FIX_MODE=false
ADD_TO_BACKLOG=true  # Always record findings to backlog by default
BACKLOG_SCRIPT="$HOME/.claude/scripts/backlog.sh"

while [[ $# -gt 0 ]]; do
    case $1 in
        --fix) FIX_MODE=true; shift ;;
        --add-to-backlog) ADD_TO_BACKLOG=true; shift ;;  # kept for backwards compat
        --no-backlog) ADD_TO_BACKLOG=false; shift ;;
        *) shift ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           AUTOMATED CODE REVIEW                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

CRITICAL_ISSUES=0
IMPORTANT_ISSUES=0
SUGGESTIONS=0

add_issue() {
    local priority="$1"
    local message="$2"
    local file="$3"

    case $priority in
        critical)
            echo -e "  ${RED}[CRITICAL]${NC} $message"
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
            if [ "$ADD_TO_BACKLOG" = true ] && [ -x "$BACKLOG_SCRIPT" ]; then
                "$BACKLOG_SCRIPT" add "$message" --priority critical --source review --file "$file" >/dev/null 2>&1 || true
            fi
            ;;
        important)
            echo -e "  ${YELLOW}[IMPORTANT]${NC} $message"
            IMPORTANT_ISSUES=$((IMPORTANT_ISSUES + 1))
            if [ "$ADD_TO_BACKLOG" = true ] && [ -x "$BACKLOG_SCRIPT" ]; then
                "$BACKLOG_SCRIPT" add "$message" --priority important --source review --file "$file" >/dev/null 2>&1 || true
            fi
            ;;
        suggestion)
            echo -e "  ${GREEN}[SUGGESTION]${NC} $message"
            SUGGESTIONS=$((SUGGESTIONS + 1))
            if [ "$ADD_TO_BACKLOG" = true ] && [ -x "$BACKLOG_SCRIPT" ]; then
                "$BACKLOG_SCRIPT" add "$message" --priority suggestion --source review --file "$file" >/dev/null 2>&1 || true
            fi
            ;;
    esac
}

# ============================================================
# CHECK 1: Security - Hardcoded Secrets
# ============================================================
echo -e "\n${YELLOW}[1/7] Checking for hardcoded secrets...${NC}"

SECRET_PATTERNS='(password|secret|api_key|apikey|api_secret|token|credential|private_key)\s*[=:]\s*["\x27][^"\x27]{8,}["\x27]'
EXCLUDE_PATTERNS='example|sample|test|mock|fake|dummy|placeholder|TODO|CHANGEME'

while IFS= read -r file; do
    if [ -f "$file" ]; then
        matches=$(grep -inE "$SECRET_PATTERNS" "$file" 2>/dev/null | grep -ivE "$EXCLUDE_PATTERNS" || true)
        if [ -n "$matches" ]; then
            add_issue "critical" "Potential hardcoded secret in $file" "$file"
        fi
    fi
done < <(git ls-files '*.ts' '*.js' '*.tsx' '*.jsx' '*.py' '*.env*' '*.json' '*.yaml' '*.yml' 2>/dev/null || find . -name "*.ts" -o -name "*.js" 2>/dev/null)

echo -e "  ${GREEN}✓ Secret check complete${NC}"

# ============================================================
# CHECK 2: Security - Dangerous Functions
# ============================================================
echo -e "\n${YELLOW}[2/7] Checking for dangerous functions...${NC}"

# Check for eval
while IFS= read -r file; do
    if [ -f "$file" ]; then
        if grep -qE '\beval\s*\(' "$file" 2>/dev/null; then
            add_issue "critical" "Use of eval() in $file - potential code injection" "$file"
        fi
    fi
done < <(git ls-files '*.ts' '*.js' '*.tsx' '*.jsx' 2>/dev/null || true)

# Check for dangerouslySetInnerHTML with variables
while IFS= read -r file; do
    if [ -f "$file" ]; then
        if grep -qE 'dangerouslySetInnerHTML.*\{.*\}' "$file" 2>/dev/null; then
            add_issue "important" "dangerouslySetInnerHTML usage in $file - verify input is sanitized" "$file"
        fi
    fi
done < <(git ls-files '*.tsx' '*.jsx' 2>/dev/null || true)

echo -e "  ${GREEN}✓ Dangerous function check complete${NC}"

# ============================================================
# CHECK 3: Code Quality - Console.log statements
# ============================================================
echo -e "\n${YELLOW}[3/7] Checking for debug statements...${NC}"

CONSOLE_TOTAL=0
while IFS= read -r file; do
    if [ -f "$file" ]; then
        count=$(grep -cE 'console\.(log|debug|info)\(' "$file" 2>/dev/null || true)
        count=$(echo "$count" | tr -d '[:space:]')
        if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
            CONSOLE_TOTAL=$((CONSOLE_TOTAL + count))
        fi
    fi
done < <(git ls-files '*.ts' '*.js' '*.tsx' '*.jsx' 2>/dev/null | grep -v '\.test\.' | grep -v '__tests__' || true)

if [ "$CONSOLE_TOTAL" -gt 0 ]; then
    add_issue "suggestion" "$CONSOLE_TOTAL console.log statement(s) in production code" ""
fi

echo -e "  ${GREEN}✓ Debug statement check complete${NC}"

# ============================================================
# CHECK 4: Code Quality - TODO/FIXME comments
# ============================================================
echo -e "\n${YELLOW}[4/7] Checking for TODO/FIXME comments...${NC}"

TODO_FILES=$(git ls-files '*.ts' '*.js' '*.tsx' '*.jsx' '*.py' 2>/dev/null | xargs grep -l 'TODO\|FIXME' 2>/dev/null || true)
if [ -n "$TODO_FILES" ]; then
    for file in $TODO_FILES; do
        count=$(grep -cE 'TODO|FIXME' "$file" 2>/dev/null || echo "0")
        add_issue "suggestion" "$count TODO/FIXME comment(s) in $file" "$file"
    done
fi

echo -e "  ${GREEN}✓ TODO/FIXME check complete${NC}"

# ============================================================
# CHECK 5: TypeScript - Any types
# ============================================================
echo -e "\n${YELLOW}[5/7] Checking for 'any' type usage...${NC}"

ANY_TOTAL=0
while IFS= read -r file; do
    if [ -f "$file" ]; then
        # Look for explicit any usage (not in comments)
        any_count=$(grep -E ': any\b|<any>|as any' "$file" 2>/dev/null | grep -v '^\s*//' | wc -l || true)
        any_count=$(echo "$any_count" | tr -d '[:space:]')
        if [ -n "$any_count" ] && [ "$any_count" -gt 0 ] 2>/dev/null; then
            ANY_TOTAL=$((ANY_TOTAL + any_count))
        fi
    fi
done < <(git ls-files '*.ts' '*.tsx' 2>/dev/null || true)

if [ "$ANY_TOTAL" -gt 0 ]; then
    add_issue "important" "$ANY_TOTAL 'any' type usage(s) across TypeScript files" ""
fi

echo -e "  ${GREEN}✓ Any type check complete${NC}"

# ============================================================
# CHECK 6: Test Coverage (if available)
# ============================================================
echo -e "\n${YELLOW}[6/7] Checking test coverage...${NC}"

if [ -f "package.json" ]; then
    SCRIPTS=$(node -e "console.log(Object.keys(require('./package.json').scripts || {}).join(' '))" 2>/dev/null || echo "")

    if echo "$SCRIPTS" | grep -qE "test:coverage|coverage"; then
        echo "  Running coverage check..."
        COVERAGE_OUTPUT=$(npm run test:coverage 2>&1 || npm run coverage 2>&1 || true)

        # Try to extract coverage percentage
        COVERAGE=$(echo "$COVERAGE_OUTPUT" | grep -oE 'All files[^|]+\|[^|]+\|[^|]+\|[^|]+\|' | head -1 || true)
        if [ -n "$COVERAGE" ]; then
            echo "  $COVERAGE"
        fi
    else
        echo -e "  ${YELLOW}⚠ No coverage script found${NC}"
    fi
fi

echo -e "  ${GREEN}✓ Coverage check complete${NC}"

# ============================================================
# CHECK 7: Large Files
# ============================================================
echo -e "\n${YELLOW}[7/7] Checking for large files...${NC}"

LARGE_FILES=0
while IFS= read -r file; do
    if [ -f "$file" ]; then
        lines=$(wc -l < "$file" 2>/dev/null || true)
        lines=$(echo "$lines" | tr -d '[:space:]')
        if [ -n "$lines" ] && [ "$lines" -gt 500 ] 2>/dev/null; then
            add_issue "suggestion" "$file has $lines lines - consider splitting" "$file"
            LARGE_FILES=$((LARGE_FILES + 1))
        fi
    fi
done < <(git ls-files '*.ts' '*.js' '*.tsx' '*.jsx' '*.py' 2>/dev/null || true)

echo -e "  ${GREEN}✓ Large file check complete${NC}"

# ============================================================
# SUMMARY
# ============================================================
echo -e "\n${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    REVIEW SUMMARY                             ${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"

echo -e "\n  ${RED}Critical Issues:${NC}  $CRITICAL_ISSUES"
echo -e "  ${YELLOW}Important Issues:${NC} $IMPORTANT_ISSUES"
echo -e "  ${GREEN}Suggestions:${NC}      $SUGGESTIONS"

if [ "$ADD_TO_BACKLOG" = true ]; then
    TOTAL=$((CRITICAL_ISSUES + IMPORTANT_ISSUES + SUGGESTIONS))
    if [ $TOTAL -gt 0 ]; then
        echo -e "\n  ${BLUE}→ $TOTAL issue(s) added to backlog${NC}"
        echo "    Run '~/.claude/scripts/backlog.sh list' to view"
    fi
fi

echo -e "\n${BLUE}══════════════════════════════════════════════════════════════${NC}\n"

# Exit with error if critical issues found
if [ $CRITICAL_ISSUES -gt 0 ]; then
    echo -e "${RED}✗ Review failed: $CRITICAL_ISSUES critical issue(s) found${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Review passed (no critical issues)${NC}"
    exit 0
fi
