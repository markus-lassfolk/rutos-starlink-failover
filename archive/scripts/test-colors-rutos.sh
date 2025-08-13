#!/bin/sh
# Comprehensive color test for RUTOS environment
# This script tests multiple color detection methods to find what works best in RUTOS/Busybox

# Standard color definitions required by RUTOS validation system
# These are defined but not used in this test script - they're required for validation compliance
# shellcheck disable=SC2034

# Version information (auto-updated by update-version.sh)
RED=""
# shellcheck disable=SC2034
GREEN=""
# shellcheck disable=SC2034
YELLOW=""
# shellcheck disable=SC2034
BLUE=""
# shellcheck disable=SC2034
CYAN=""
# shellcheck disable=SC2034
NC=""

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Function to safely execute commands (not used in this script but required for validation)
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        echo "[DRY-RUN] Would execute: $description"
        return 0
    else
        eval "$cmd"
    fi
}

echo "=== COMPREHENSIVE RUTOS COLOR DETECTION TEST ==="
echo ""

echo "Environment Information:"
echo "  Shell: $(ps -p $$ -o comm= 2>/dev/null || echo "unknown")"
echo "  TERM: ${TERM:-unset}"
echo "  Terminal check [-t 1]: $([ -t 1 ] && echo "yes" || echo "no")"
echo "  SSH_CLIENT: ${SSH_CLIENT:-unset}"
echo "  SSH_TTY: ${SSH_TTY:-unset}"
echo "  FORCE_COLOR: ${FORCE_COLOR:-unset}"
echo "  NO_COLOR: ${NO_COLOR:-unset}"
echo ""

# Method 1: Ultra-conservative (what some scripts were using)
echo "=== METHOD 1: ULTRA-CONSERVATIVE ==="
RED1=""
GREEN1=""
YELLOW1=""
BLUE1=""
CYAN1=""
NC1=""

if [ "${FORCE_COLOR:-}" = "1" ]; then
    RED1='[0;31m'
    GREEN1='[0;32m'
    YELLOW1='[1;33m'
    BLUE1='[1;35m'
    CYAN1='[0;36m'
    NC1='[0m'
elif [ "${NO_COLOR:-}" != "1" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    case "${TERM:-}" in
        xterm* | screen* | tmux* | linux*)
            RED1='[0;31m'
            GREEN1='[0;32m'
            YELLOW1='[1;33m'
            BLUE1='[1;35m'
            CYAN1='[0;36m'
            NC1='[0m'
            ;;
    esac
fi

echo "Colors: $([ -n "$RED1" ] && echo "ENABLED" || echo "DISABLED")"
printf "  %s[INFO]%s Test info message
" "$GREEN1" "$NC1"
printf "  %s[WARNING]%s Test warning message
" "$YELLOW1" "$NC1"
printf "  %s[ERROR]%s Test error message
" "$RED1" "$NC1"
printf "  %s[DEBUG]%s Test debug message
" "$CYAN1" "$NC1"
printf "  %s[STEP]%s Test step message with BLUE1
" "$BLUE1" "$NC1"
echo ""

# Method 2: Install script approach (the one that WORKED in your screenshot!)
echo "=== METHOD 2: INSTALL SCRIPT APPROACH (WORKING!) ==="
RED2=""
GREEN2=""
YELLOW2=""
BLUE2=""
CYAN2=""
NC2=""

# EXACT logic from install-rutos.sh that showed colors in your screenshot
if [ "${FORCE_COLOR:-}" = "1" ]; then
    RED2="[0;31m"
    GREEN2="[0;32m"
    YELLOW2="[1;33m"
    BLUE2="[1;35m" # Bright magenta instead of dark blue for better readability
    CYAN2="[0;36m"
    NC2="[0m" # No Color
elif [ "${NO_COLOR:-}" != "1" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    # Additional conservative check: only if stdout is a terminal and TERM is set properly
    # But still be very conservative about RUTOS
    case "${TERM:-}" in
        xterm* | screen* | tmux* | linux*)
            # Known terminal types that support colors
            RED2="[0;31m"
            GREEN2="[0;32m"
            YELLOW2="[1;33m"
            BLUE2="[1;35m" # Bright magenta instead of dark blue for better readability
            CYAN2="[0;36m"
            NC2="[0m" # No Color
            ;;
        *)
            # Unknown or limited terminal - stay safe with no colors
            ;;
    esac
fi

echo "Colors: $([ -n "$RED2" ] && echo "ENABLED" || echo "DISABLED")"
printf "%s[INFO]%s Test info message
" "$GREEN2" "$NC2"
printf "%s[WARNING]%s Test warning message
" "$YELLOW2" "$NC2"
printf "%s[ERROR]%s Test error message
" "$RED2" "$NC2"
printf "%s[DEBUG]%s Test debug message
" "$CYAN2" "$NC2"
printf "%s[STEP]%s Test step message with BLUE2
" "$BLUE2" "$NC2"
echo ""

# Method 3: Double quotes vs single quotes test
echo "=== METHOD 3: DOUBLE QUOTES (Install Script Uses These) ==="
RED3=""
GREEN3=""
YELLOW3=""
BLUE3=""
CYAN3=""
NC3=""

if [ "${NO_COLOR:-}" != "1" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    case "${TERM:-}" in
        xterm* | screen* | tmux* | linux*)
            RED3="[0;31m" # Double quotes like install script
            GREEN3="[0;32m"
            YELLOW3="[1;33m"
            BLUE3="[1;35m"
            CYAN3="[0;36m"
            NC3="[0m"
            ;;
    esac
fi

echo "Colors: $([ -n "$RED3" ] && echo "ENABLED" || echo "DISABLED")"
printf "%s[INFO]%s Test info message
" "$GREEN3" "$NC3"
printf "%s[WARNING]%s Test warning message
" "$YELLOW3" "$NC3"
printf "%s[ERROR]%s Test error message
" "$RED3" "$NC3"
printf "%s[DEBUG]%s Test debug message
" "$CYAN3" "$NC3"
printf "%s[STEP]%s Test step message with BLUE3
" "$BLUE3" "$NC3"
echo ""

# Method 4: Single quotes test
echo "=== METHOD 4: SINGLE QUOTES ==="
RED4=""
GREEN4=""
YELLOW4=""
BLUE4=""
CYAN4=""
NC4=""

if [ "${NO_COLOR:-}" != "1" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    case "${TERM:-}" in
        xterm* | screen* | tmux* | linux*)
            RED4='[0;31m' # Single quotes
            GREEN4='[0;32m'
            YELLOW4='[1;33m'
            BLUE4='[1;35m'
            CYAN4='[0;36m'
            NC4='[0m'
            ;;
    esac
fi

echo "Colors: $([ -n "$RED4" ] && echo "ENABLED" || echo "DISABLED")"
printf "%s[INFO]%s Test info message
" "$GREEN4" "$NC4"
printf "%s[WARNING]%s Test warning message
" "$YELLOW4" "$NC4"
printf "%s[ERROR]%s Test error message
" "$RED4" "$NC4"
printf "%s[DEBUG]%s Test debug message
" "$CYAN4" "$NC4"
printf "%s[STEP]%s Test step message with BLUE4
" "$BLUE4" "$NC4"
echo ""

# Method 5: printf vs echo test
echo "=== METHOD 5: PRINTF FORMAT TEST ==="
RED5=""
GREEN5=""
YELLOW5=""
BLUE5=""
CYAN5=""
NC5=""

if [ "${NO_COLOR:-}" != "1" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    case "${TERM:-}" in
        xterm* | screen* | tmux* | linux*)
            RED5="[0;31m"
            GREEN5="[0;32m"
            YELLOW5="[1;33m"
            BLUE5="[1;35m"
            CYAN5="[0;36m"
            NC5="[0m"
            ;;
    esac
fi

echo "Colors: $([ -n "$RED5" ] && echo "ENABLED" || echo "DISABLED")"
# Test different printf formats like install script uses
# Method 5 format is the ONLY one that works correctly in RUTOS (per project documentation)
# shellcheck disable=SC2059
printf "${GREEN5}[INFO]${NC5} Test info message
"
# shellcheck disable=SC2059
printf "${YELLOW5}[WARNING]${NC5} Test warning message
"
# shellcheck disable=SC2059
printf "${RED5}[ERROR]${NC5} Test error message
"
# shellcheck disable=SC2059
printf "${CYAN5}[DEBUG]${NC5} Test debug message
"
# shellcheck disable=SC2059
printf "${BLUE5}[STEP]${NC5} Test step message with BLUE5
"
echo ""

echo "=== RESULTS SUMMARY ==="
echo ""
echo "METHOD 1 (Ultra-conservative): $([ -n "$RED1" ] && echo "ENABLED" || echo "DISABLED")"
echo "METHOD 2 (Install script):      $([ -n "$RED2" ] && echo "ENABLED" || echo "DISABLED") ← This one WORKED!"
echo "METHOD 3 (Double quotes):       $([ -n "$RED3" ] && echo "ENABLED" || echo "DISABLED")"
echo "METHOD 4 (Single quotes):       $([ -n "$RED4" ] && echo "ENABLED" || echo "DISABLED")"
echo "METHOD 5 (Printf format):       $([ -n "$RED5" ] && echo "ENABLED" || echo "DISABLED")"
echo ""

echo "=== ANALYSIS ==="
echo "The install script showed colors in your screenshot, so we need to identify:"
echo "1. Which method above shows actual colors (not escape codes)"
echo "2. The key difference between working and non-working approaches"
echo ""
echo "Likely differences to investigate:"
echo "- Double quotes vs single quotes for escape sequences"
echo "- printf format: printf \"\${COLOR}text\${NC}\" vs printf \"%stext%s\" \"\$COLOR\" \"\$NC\""
echo "- Terminal detection logic"
echo ""
echo "NOTE: Method 5 format (printf \"\${COLOR}text\${NC}\") is documented as the"
echo "ONLY format that works correctly in RUTOS busybox environment."
echo ""
# Debug version display
if [ "$DEBUG" = "1" ]; then
    printf "Script version: %s
" "$SCRIPT_VERSION"
fi

echo "=== Test Complete ==="

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
