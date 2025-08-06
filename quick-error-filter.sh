#!/bin/sh
set -e

# Quick error filter for RUTOS deployment logs
# Usage: ./quick-error-filter.sh [log_file]

DEFAULT_PATTERNS="ERROR|FAIL|CRITICAL|❌|⚠️|WARN|No such file|not found|command not found|Permission denied|uci: Entry not found|sed:"

if [ -n "$1" ] && [ -f "$1" ]; then
    echo "🔍 Filtering errors from: $1"
    echo "=========================================="
    grep -E -i -A 5 -B 5 -n "$DEFAULT_PATTERNS" "$1" 2>/dev/null || {
        echo "✅ No errors found in log file"
    }
else
    echo "🔍 Filtering errors from stdin"
    echo "=========================================="
    grep -E -i -A 5 -B 5 -n "$DEFAULT_PATTERNS" 2>/dev/null || {
        echo "✅ No errors found in input"
    }
fi

echo "=========================================="
echo "Pattern used: $DEFAULT_PATTERNS"
