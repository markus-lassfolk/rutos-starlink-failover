#!/bin/sh
# Simple color test for RUTOS environment
# This script tests basic color functionality in the actual RUTOS busybox environment

# RUTOS-compatible color detection (conservative busybox approach)
RED=""
GREEN=""
YELLOW=""
BLUE=""
CYAN=""
NC=""

# Only enable colors if we're confident they'll work in RUTOS
if [ "${NO_COLOR:-}" != "1" ]; then
    # Enable colors only in known-good scenarios
    if [ "${FORCE_COLOR:-}" = "1" ] || [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[1;35m'
        CYAN='\033[0;36m'
        NC='\033[0m'
    fi
fi

echo "=== RUTOS Color Test ==="
echo ""

echo "Environment Information:"
echo "  Shell: $(ps -p $$ -o comm= 2>/dev/null || echo "unknown")"
echo "  TERM: ${TERM:-unset}"
echo "  SSH_CLIENT: ${SSH_CLIENT:-unset}"
echo "  SSH_TTY: ${SSH_TTY:-unset}"
echo "  FORCE_COLOR: ${FORCE_COLOR:-unset}"
echo "  NO_COLOR: ${NO_COLOR:-unset}"
echo ""

if [ -n "$RED" ]; then
    echo "Colors are ENABLED"
    echo ""
    echo "Color Test:"
    printf "  %sRED text%s\n" "$RED" "$NC"
    printf "  %sGREEN text%s\n" "$GREEN" "$NC"
    printf "  %sYELLOW text%s\n" "$YELLOW" "$NC"
    printf "  %sBLUE text%s\n" "$BLUE" "$NC"
    printf "  %sCYAN text%s\n" "$CYAN" "$NC"
    echo ""

    echo "Logging Function Test:"
    printf "%s[INFO]%s Test info message\n" "$GREEN" "$NC"
    printf "%s[WARNING]%s Test warning message\n" "$YELLOW" "$NC"
    printf "%s[ERROR]%s Test error message\n" "$RED" "$NC"
    printf "%s[DEBUG]%s Test debug message\n" "$CYAN" "$NC"
else
    echo "Colors are DISABLED"
    echo ""
    echo "Plain Text Test:"
    echo "  [INFO] Test info message"
    echo "  [WARNING] Test warning message"
    echo "  [ERROR] Test error message"
    echo "  [DEBUG] Test debug message"
fi

echo ""
echo "To force colors: FORCE_COLOR=1 $0"
echo "To disable colors: NO_COLOR=1 $0"
echo ""
echo "=== Test Complete ==="
