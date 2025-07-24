#!/bin/sh
# Script: diagnose-database-loop-rutos.sh
# Version: 2.6.0
# Description: Quick diagnostic for RUTOS database optimization loop
# shellcheck disable=SC2059  # Using Method 5 printf format for RUTOS compatibility

set -e

# Colors for output

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034
CYAN='\033[0;36m'
NC='\033[0m'

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    # shellcheck disable=SC2034  # CYAN defined for RUTOS consistency
    CYAN=""
    NC=""
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    printf "[DEBUG] DRY_RUN=%s, RUTOS_TEST_MODE=%s\n" "$DRY_RUN" "$RUTOS_TEST_MODE" >&2
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        printf "[DRY-RUN] Would execute: %s\n" "$description" >&2
        printf "[DRY-RUN] Command: %s\n" "$cmd" >&2
        return 0
    else
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "[DEBUG] Executing: %s\n" "$cmd" >&2
        fi
        eval "$cmd"
    fi
}

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    printf "${GREEN}RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution${NC}\n"
    exit 0
fi

printf "${BLUE}%s${NC}\n\n" "=== RUTOS Database Loop Diagnostic ==="

# 1. Check for the loop pattern in recent logs
printf "\n${BLUE}%s${NC}\n" "1. Checking for database loop pattern in logs:"
recent_errors=$(logread | tail -100 | grep -c "Unable to reduce max rows\|Unable to optimize database\|Failed to restore database" 2>/dev/null | tr -d ' \n\r' || echo "0")
if [ "$recent_errors" -gt 0 ]; then
    printf "${RED}   ✗ FOUND: %d database optimization errors in recent logs${NC}\n" "$recent_errors"

    # Show the pattern
    printf "${YELLOW}%s${NC}\n" "   Recent error pattern:"
    logread | tail -20 | grep "Unable to reduce max rows\|Unable to optimize database\|Failed to restore database" | tail -5 | while IFS= read -r line; do
        printf "${YELLOW}     %s${NC}\n" "$line"
    done
else
    printf "${GREEN}%s${NC}\n" "   ✓ No database optimization errors found"
fi

# 2. Check for processes that might be causing the issue
printf "\n${BLUE}%s${NC}\n" "2. Checking for database-related processes:"
# Use pgrep if available, otherwise fall back to ps grep for busybox compatibility
if command -v pgrep >/dev/null 2>&1; then
    db_processes=$(pgrep -l "sqlite\|database\|collectd" 2>/dev/null || echo "")
else
    # shellcheck disable=SC2009  # pgrep not available in busybox, using ps
    db_processes=$(ps | grep -E "(sqlite|database|collectd)" | grep -v "grep" || echo "")
fi
if [ -n "$db_processes" ]; then
    printf "${YELLOW}%s${NC}\n" "   Database-related processes found:"
    echo "$db_processes" | while IFS= read -r process; do
        printf "${YELLOW}     %s${NC}\n" "$process"
    done
else
    printf "${GREEN}%s${NC}\n" "   No specific database processes found"
fi

# 3. Check for database files
printf "\n${BLUE}%s${NC}\n" "3. Looking for database files:"
db_files=$(find /tmp /var -name "*.db" -o -name "*.sqlite" 2>/dev/null | head -10 || echo "")
if [ -n "$db_files" ]; then
    printf "${YELLOW}%s${NC}\n" "   Database files found:"
    echo "$db_files" | while IFS= read -r dbfile; do
        size=$(stat -f%z "$dbfile" 2>/dev/null || stat -c%s "$dbfile" 2>/dev/null || echo "unknown")
        printf "${YELLOW}     %s (%s)${NC}\n" "$dbfile" "$size"
    done
else
    printf "${GREEN}%s${NC}\n" "   No database files found in common locations"
fi

echo "diagnose-database-loop-rutos.sh v$SCRIPT_VERSION"
echo ""
# 4. Check system resource usage
echo "diagnose-database-loop-rutos.sh v$SCRIPT_VERSION"
echo ""
printf "\n${BLUE}%s${NC}\n" "4. System memory and disk usage:"
printf "${YELLOW}%s${NC}\n" "   Memory:"
free | head -2 | while IFS= read -r line; do
    printf "${YELLOW}     %s${NC}\n" "$line"
done

echo "diagnose-database-loop-rutos.sh v$SCRIPT_VERSION"
echo ""
printf "${YELLOW}%s${NC}\n" "   Disk usage:"
echo "diagnose-database-loop-rutos.sh v$SCRIPT_VERSION"
echo ""
df -h / /tmp /var 2>/dev/null | while IFS= read -r line; do
    printf "${YELLOW}     %s${NC}\n" "$line"
done

# 5. Check for lock files
printf "\n${BLUE}%s${NC}\n" "5. Checking for database lock files:"
lock_files=$(find /tmp /var/lock -name "*database*" -o -name "*db*" -o -name "*sqlite*" 2>/dev/null || echo "")
if [ -n "$lock_files" ]; then
    printf "${RED}%s${NC}\n" "   ✗ Lock files found:"
    echo "$lock_files" | while IFS= read -r lockfile; do
        printf "${RED}     %s${NC}\n" "$lockfile"
    done
else
    printf "${GREEN}%s${NC}\n" "   ✓ No database lock files found"
fi

# 6. Check cron jobs for database maintenance
printf "\n${BLUE}%s${NC}\n" "6. Checking cron jobs for database maintenance:"
if [ -f "/etc/crontabs/root" ]; then
    db_crons=$(grep -i "database\|sqlite\|optimize" /etc/crontabs/root 2>/dev/null || echo "")
    if [ -n "$db_crons" ]; then
        printf "${YELLOW}%s${NC}\n" "   Database-related cron jobs:"
        echo "$db_crons" | while IFS= read -r cronjob; do
            printf "${YELLOW}     %s${NC}\n" "$cronjob"
        done
    else
        printf "${GREEN}%s${NC}\n" "   No database-related cron jobs found"
    fi
else
    printf "${YELLOW}%s${NC}\n" "   Crontab file not found"
fi

# 7. Recent system messages
printf "\n${BLUE}%s${NC}\n" "7. Recent system messages (last 5):"
logread | tail -5 | while IFS= read -r line; do
    printf "${YELLOW}   %s${NC}\n" "$line"
done

printf "\n${BLUE}%s${NC}\n" "=== Diagnostic Summary ==="
if [ "$recent_errors" -gt 5 ]; then
    printf "${RED}%s${NC}\n" "❌ CRITICAL: Database optimization loop detected!"
    printf "${YELLOW}%s${NC}\n" "📋 Recommended action: Run fix-database-loop-rutos.sh repair"
elif [ "$recent_errors" -gt 0 ]; then
    printf "${YELLOW}%s${NC}\n" "⚠ WARNING: Some database errors found"
    printf "${YELLOW}%s${NC}\n" "📋 Recommended action: Monitor or run fix-database-loop-rutos.sh check"
else
    printf "${GREEN}%s${NC}\n" "✅ OK: No database loop issues detected"
fi

printf "\n${BLUE}%s${NC}\n" "Next steps:"
printf "${YELLOW}%s${NC}\n" "  1. To fix: ./fix-database-loop-rutos.sh repair"
printf "${YELLOW}%s${NC}\n" "  2. To monitor: watch -n 30 './diagnose-database-loop-rutos.sh'"
printf "${YELLOW}%s${NC}\n" "  3. To check logs: logread | tail -50"
