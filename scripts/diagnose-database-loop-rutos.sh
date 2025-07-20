#!/bin/sh
# Script: diagnose-database-loop-rutos.sh
# Version: 1.0.0
# Description: Quick diagnostic for RUTOS database optimization loop

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
NC='\033[0m'

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

printf "${BLUE}=== RUTOS Database Loop Diagnostic ===${NC}\n\n"

# 1. Check for the loop pattern in recent logs
printf "${BLUE}1. Checking for database loop pattern in logs:${NC}\n"
recent_errors=$(logread | tail -100 | grep -c "Unable to reduce max rows\|Unable to optimize database\|Failed to restore database" 2>/dev/null || echo "0")
if [ "$recent_errors" -gt 0 ]; then
    printf "${RED}   ✗ FOUND: %d database optimization errors in recent logs${NC}\n" "$recent_errors"
    
    # Show the pattern
    printf "${YELLOW}   Recent error pattern:${NC}\n"
    logread | tail -20 | grep "Unable to reduce max rows\|Unable to optimize database\|Failed to restore database" | tail -5 | while IFS= read -r line; do
        printf "${YELLOW}     %s${NC}\n" "$line"
    done
else
    printf "${GREEN}   ✓ No database optimization errors found${NC}\n"
fi

# 2. Check for processes that might be causing the issue
printf "\n${BLUE}2. Checking for database-related processes:${NC}\n"
db_processes=$(ps | grep -E "(sqlite|database|collectd)" | grep -v grep || echo "")
if [ -n "$db_processes" ]; then
    printf "${YELLOW}   Database-related processes found:${NC}\n"
    echo "$db_processes" | while IFS= read -r process; do
        printf "${YELLOW}     %s${NC}\n" "$process"
    done
else
    printf "${GREEN}   No specific database processes found${NC}\n"
fi

# 3. Check for database files
printf "\n${BLUE}3. Looking for database files:${NC}\n"
db_files=$(find /tmp /var -name "*.db" -o -name "*.sqlite" 2>/dev/null | head -10 || echo "")
if [ -n "$db_files" ]; then
    printf "${YELLOW}   Database files found:${NC}\n"
    echo "$db_files" | while IFS= read -r dbfile; do
        size=$(ls -lh "$dbfile" 2>/dev/null | awk '{print $5}' || echo "unknown")
        printf "${YELLOW}     %s (%s)${NC}\n" "$dbfile" "$size"
    done
else
    printf "${GREEN}   No database files found in common locations${NC}\n"
fi

# 4. Check system resource usage
printf "\n${BLUE}4. System resource usage:${NC}\n"
printf "${YELLOW}   Memory:${NC}\n"
free | head -2 | while IFS= read -r line; do
    printf "${YELLOW}     %s${NC}\n" "$line"
done

printf "${YELLOW}   Disk usage:${NC}\n"
df -h / /tmp /var 2>/dev/null | while IFS= read -r line; do
    printf "${YELLOW}     %s${NC}\n" "$line"
done

# 5. Check for lock files
printf "\n${BLUE}5. Checking for database lock files:${NC}\n"
lock_files=$(find /tmp /var/lock -name "*database*" -o -name "*db*" -o -name "*sqlite*" 2>/dev/null || echo "")
if [ -n "$lock_files" ]; then
    printf "${RED}   ✗ Lock files found:${NC}\n"
    echo "$lock_files" | while IFS= read -r lockfile; do
        printf "${RED}     %s${NC}\n" "$lockfile"
    done
else
    printf "${GREEN}   ✓ No database lock files found${NC}\n"
fi

# 6. Check cron jobs for database maintenance
printf "\n${BLUE}6. Checking cron jobs for database maintenance:${NC}\n"
if [ -f "/etc/crontabs/root" ]; then
    db_crons=$(grep -i "database\|sqlite\|optimize" /etc/crontabs/root 2>/dev/null || echo "")
    if [ -n "$db_crons" ]; then
        printf "${YELLOW}   Database-related cron jobs:${NC}\n"
        echo "$db_crons" | while IFS= read -r cronjob; do
            printf "${YELLOW}     %s${NC}\n" "$cronjob"
        done
    else
        printf "${GREEN}   No database-related cron jobs found${NC}\n"
    fi
else
    printf "${YELLOW}   Crontab file not found${NC}\n"
fi

# 7. Recent system messages
printf "\n${BLUE}7. Recent system messages (last 5):${NC}\n"
logread | tail -5 | while IFS= read -r line; do
    printf "${YELLOW}   %s${NC}\n" "$line"
done

printf "\n${BLUE}=== Diagnostic Summary ===${NC}\n"
if [ "$recent_errors" -gt 5 ]; then
    printf "${RED}❌ CRITICAL: Database optimization loop detected!${NC}\n"
    printf "${YELLOW}📋 Recommended action: Run fix-database-loop-rutos.sh repair${NC}\n"
elif [ "$recent_errors" -gt 0 ]; then
    printf "${YELLOW}⚠ WARNING: Some database errors found${NC}\n"
    printf "${YELLOW}📋 Recommended action: Monitor or run fix-database-loop-rutos.sh check${NC}\n"
else
    printf "${GREEN}✅ OK: No database loop issues detected${NC}\n"
fi

printf "\n${BLUE}Next steps:${NC}\n"
printf "${YELLOW}  1. To fix: ./fix-database-loop-rutos.sh repair${NC}\n"
printf "${YELLOW}  2. To monitor: watch -n 30 './diagnose-database-loop-rutos.sh'${NC}\n"
printf "${YELLOW}  3. To check logs: logread | tail -50${NC}\n"
