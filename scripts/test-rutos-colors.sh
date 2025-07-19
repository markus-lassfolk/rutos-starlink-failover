#!/bin/sh
# Comprehensive color test for RUTOS environment
# This script tests multiple color detection methods to find what works best in RUTOS/Busybox

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

# Method 1: Ultra-conservative (current approach)
echo "=== METHOD 1: ULTRA-CONSERVATIVE (Current) ==="
RED1=""
GREEN1=""
YELLOW1=""
BLUE1=""
CYAN1=""
NC1=""

if [ "${FORCE_COLOR:-}" = "1" ]; then
    RED1='\033[0;31m'
    GREEN1='\033[0;32m'
    YELLOW1='\033[1;33m'
    BLUE1='\033[1;35m'
    CYAN1='\033[0;36m'
    NC1='\033[0m'
elif [ "${NO_COLOR:-}" != "1" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    case "${TERM:-}" in
        xterm*|screen*|tmux*|linux*)
            RED1='\033[0;31m'
            GREEN1='\033[0;32m'
            YELLOW1='\033[1;33m'
            BLUE1='\033[1;35m'
            CYAN1='\033[0;36m'
            NC1='\033[0m'
            ;;
    esac
fi

echo "Colors: $([ -n "$RED1" ] && echo "ENABLED" || echo "DISABLED")"
if [ -n "$RED1" ]; then
    printf "  %s[INFO]%s Test info message\n" "$GREEN1" "$NC1"
    printf "  %s[WARNING]%s Test warning message\n" "$YELLOW1" "$NC1"
    printf "  %s[ERROR]%s Test error message\n" "$RED1" "$NC1"
    printf "  %s[DEBUG]%s Test debug message\n" "$CYAN1" "$NC1"
else
    echo "  [INFO] Test info message (no colors)"
    echo "  [WARNING] Test warning message (no colors)"
    echo "  [ERROR] Test error message (no colors)"
    echo "  [DEBUG] Test debug message (no colors)"
fi
echo ""

# Method 2: SSH-aware (install script approach)
echo "=== METHOD 2: SSH-AWARE (Install Script Style) ==="
RED2=""
GREEN2=""
YELLOW2=""
BLUE2=""
CYAN2=""
NC2=""

if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED2='\033[0;31m'
    GREEN2='\033[0;32m'
    YELLOW2='\033[1;33m'
    BLUE2='\033[1;35m'
    CYAN2='\033[0;36m'
    NC2='\033[0m'
fi

echo "Colors: $([ -n "$RED2" ] && echo "ENABLED" || echo "DISABLED")"
if [ -n "$RED2" ]; then
    printf "  %s[INFO]%s Test info message\n" "$GREEN2" "$NC2"
    printf "  %s[WARNING]%s Test warning message\n" "$YELLOW2" "$NC2"
    printf "  %s[ERROR]%s Test error message\n" "$RED2" "$NC2"
    printf "  %s[DEBUG]%s Test debug message\n" "$CYAN2" "$NC2"
else
    echo "  [INFO] Test info message (no colors)"
    echo "  [WARNING] Test warning message (no colors)"
    echo "  [ERROR] Test error message (no colors)"
    echo "  [DEBUG] Test debug message (no colors)"
fi
echo ""

# Method 3: SSH-enhanced (check SSH environment)
echo "=== METHOD 3: SSH-ENHANCED (Check SSH Environment) ==="
RED3=""
GREEN3=""
YELLOW3=""
BLUE3=""
CYAN3=""
NC3=""

# Enable colors if SSH connection is detected OR terminal supports them
if [ "${NO_COLOR:-}" != "1" ]; then
    if [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ] || 
       ([ -t 1 ] && [ "${TERM:-}" != "dumb" ]); then
        RED3='\033[0;31m'
        GREEN3='\033[0;32m'
        YELLOW3='\033[1;33m'
        BLUE3='\033[1;35m'
        CYAN3='\033[0;36m'
        NC3='\033[0m'
    fi
fi

echo "Colors: $([ -n "$RED3" ] && echo "ENABLED" || echo "DISABLED")"
if [ -n "$RED3" ]; then
    printf "  %s[INFO]%s Test info message\n" "$GREEN3" "$NC3"
    printf "  %s[WARNING]%s Test warning message\n" "$YELLOW3" "$NC3"
    printf "  %s[ERROR]%s Test error message\n" "$RED3" "$NC3"
    printf "  %s[DEBUG]%s Test debug message\n" "$CYAN3" "$NC3"
else
    echo "  [INFO] Test info message (no colors)"
    echo "  [WARNING] Test warning message (no colors)"
    echo "  [ERROR] Test error message (no colors)"
    echo "  [DEBUG] Test debug message (no colors)"
fi
echo ""

# Method 4: Always on (for comparison)
echo "=== METHOD 4: ALWAYS ON (For Comparison) ==="
RED4='\033[0;31m'
GREEN4='\033[0;32m'
YELLOW4='\033[1;33m'
BLUE4='\033[1;35m'
CYAN4='\033[0;36m'
NC4='\033[0m'

echo "Colors: ALWAYS ENABLED"
printf "  %s[INFO]%s Test info message\n" "$GREEN4" "$NC4"
printf "  %s[WARNING]%s Test warning message\n" "$YELLOW4" "$NC4"
printf "  %s[ERROR]%s Test error message\n" "$RED4" "$NC4"
printf "  %s[DEBUG]%s Test debug message\n" "$CYAN4" "$NC4"
echo ""

# Method 5: Double quotes (alternative format)
echo "=== METHOD 5: DOUBLE QUOTES (Alternative Format) ==="
RED5=""
GREEN5=""
YELLOW5=""
BLUE5=""
CYAN5=""
NC5=""

if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED5="\033[0;31m"
    GREEN5="\033[0;32m"
    YELLOW5="\033[1;33m"
    BLUE5="\033[1;35m"
    CYAN5="\033[0;36m"
    NC5="\033[0m"
fi

echo "Colors: $([ -n "$RED5" ] && echo "ENABLED" || echo "DISABLED")"
if [ -n "$RED5" ]; then
    printf "  %s[INFO]%s Test info message\n" "$GREEN5" "$NC5"
    printf "  %s[WARNING]%s Test warning message\n" "$YELLOW5" "$NC5"
    printf "  %s[ERROR]%s Test error message\n" "$RED5" "$NC5"
    printf "  %s[DEBUG]%s Test debug message\n" "$CYAN5" "$NC5"
else
    echo "  [INFO] Test info message (no colors)"
    echo "  [WARNING] Test warning message (no colors)"
    echo "  [ERROR] Test error message (no colors)"
    echo "  [DEBUG] Test debug message (no colors)"
fi
echo ""

echo "=== RESULTS SUMMARY ==="
echo ""
echo "METHOD 1 (Ultra-conservative): $([ -n "$RED1" ] && echo "ENABLED" || echo "DISABLED")"
echo "METHOD 2 (SSH-aware/Install):   $([ -n "$RED2" ] && echo "ENABLED" || echo "DISABLED")"
echo "METHOD 3 (SSH-enhanced):        $([ -n "$RED3" ] && echo "ENABLED" || echo "DISABLED")"
echo "METHOD 4 (Always on):           $([ -n "$RED4" ] && echo "ENABLED" || echo "DISABLED")"
echo "METHOD 5 (Double quotes):       $([ -n "$RED5" ] && echo "ENABLED" || echo "DISABLED")"
echo ""

echo "=== REPORTING INSTRUCTIONS ==="
echo ""
echo "Please tell me:"
echo "1. Which methods show ACTUAL COLORS (not escape codes like \\033[0;32m)?"
echo "2. Which methods show literal escape codes instead of colors?"
echo "3. Any methods that cause display issues or errors?"
echo ""
echo "Example response:"
echo "  METHOD 1: Shows colors properly"
echo "  METHOD 2: Shows escape codes literally"
echo "  METHOD 3: Shows colors properly" 
echo "  METHOD 4: Causes display problems"
echo "  METHOD 5: Shows colors properly"
echo ""
echo "This will help me choose the best color detection for RUTOS scripts!"
    echo "  [DEBUG] Test debug message"
fi

echo ""
echo "To force colors: FORCE_COLOR=1 $0"
echo "To disable colors: NO_COLOR=1 $0"
echo ""
echo "=== Test Complete ==="
