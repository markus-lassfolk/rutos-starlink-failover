#!/bin/bash

# RUTOS Script Compatibility Audit
# This script checks all shell scripts in the repository for RUTOS compatibility issues
# and enforces POSIX compliance for busybox shell compatibility

echo "======================================"
echo "RUTOS Script Compatibility Audit"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
TOTAL_SCRIPTS=0
BASH_SCRIPTS=0
POSIX_SCRIPTS=0
ISSUES_FOUND=0
CRITICAL_ISSUES=0

echo "Scanning all shell scripts in the repository..."
echo ""

# Find all shell scripts and process them without subshell
script_list=$(find . -type f -name "*.sh")

for script in $script_list; do
    TOTAL_SCRIPTS=$((TOTAL_SCRIPTS + 1))

    echo "=== Checking: $script ==="

    # Check shebang
    shebang=$(head -1 "$script")
    case "$shebang" in
        "#!/bin/bash")
            printf "%s[BASH]%s Uses bash shebang\n" "$BLUE" "$NC"
            BASH_SCRIPTS=$((BASH_SCRIPTS + 1))
            ;;

        "#!/bin/sh")
            printf "%s[POSIX]%s Uses POSIX shell shebang\n" "$GREEN" "$NC"
            POSIX_SCRIPTS=$((POSIX_SCRIPTS + 1))
            ;;

        *)
            printf "%s[UNKNOWN]%s Unknown or missing shebang: %s\n" "$YELLOW" "$NC" "$shebang"
            ;;
    esac

    # CRITICAL POSIX COMPATIBILITY CHECKS
    echo "  Critical POSIX compatibility checks:"
    
    # Check for 'local' variables (not supported in busybox sh)
    local_count=$(grep -c "^[[:space:]]*local[[:space:]]" "$script" 2>/dev/null || true)
    if [ -n "$local_count" ] && [ "$local_count" -gt 0 ]; then
        printf "    %s✗ CRITICAL%s Uses 'local' variables (%s occurrences) - not supported in busybox\n" "$RED" "$NC" "$local_count"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for function() syntax (should be function_name() {)
    if grep -qE "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(" "$script"; then
        printf "    %s✗ CRITICAL%s Uses 'function()' syntax - use 'function_name() {' instead\n" "$RED" "$NC"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for double brackets [[ ]] (should use single brackets [ ])
    if grep -q "\[\[" "$script"; then
        printf "    %s✗ CRITICAL%s Uses double brackets [[ ]] - use single brackets [ ] instead\n" "$RED" "$NC"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for bash arrays
    if grep -q "\${.*\[@\].*}" "$script" || grep -q "declare -a" "$script" || grep -q "array\[" "$script"; then
        printf "    %s✗ CRITICAL%s Uses bash arrays - not supported in busybox\n" "$RED" "$NC"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for echo -e (should use printf)
    if grep -qE "^[[:space:]]*echo[[:space:]]+-e[[:space:]]" "$script"; then
        printf "    %s✗ CRITICAL%s Uses 'echo -e' - use 'printf' instead\n" "$RED" "$NC"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for 'source' command (should use '.')
    if grep -q "^[[:space:]]*source[[:space:]]" "$script"; then
        printf "    %s✗ CRITICAL%s Uses 'source' command - use '.' instead\n" "$RED" "$NC"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for $'\n' constructs (should use actual newlines or printf)
    if grep -q "\$'.*\\n.*'" "$script"; then
        printf "    %s✗ CRITICAL%s Uses \$'\\n' constructs - use actual newlines or printf instead\n" "$RED" "$NC"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Additional bash-specific checks
    echo "  Bash-specific syntax checks:"
    
    # Check for == comparison (should use =)
    if grep -q "==" "$script"; then
        if [ "$shebang" = "#!/bin/sh" ]; then
            printf "    %s⚠%s POSIX script uses == comparison - prefer = for compatibility\n" "$YELLOW" "$NC"
        else
            printf "    %s[INFO]%s Uses == comparison (bash preference)\n" "$CYAN" "$NC"
        fi
    fi

    # Check for RUTOS-specific compatibility issues
    echo "  RUTOS-specific compatibility checks:"

    # Check for bc usage
    if grep -q " bc " "$script"; then
        if grep -q "bc.*2>/dev/null.*echo" "$script"; then
            printf "    %s✓%s bc usage has fallbacks\n" "$GREEN" "$NC"
        else
            printf "    %s⚠%s bc usage without fallbacks\n" "$YELLOW" "$NC"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi

    # Check for stat usage
    if grep -q "stat -[cf]" "$script"; then
        printf "    %s✗%s Uses stat with -c/-f flags (RUTOS incompatible)\n" "$RED" "$NC"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    elif grep -q "wc -c" "$script"; then
        printf "    %s✓%s Uses wc -c for file sizes (RUTOS compatible)\n" "$GREEN" "$NC"
    fi

    # Check for curl flags
    if grep -q "curl.*-L" "$script"; then
        printf "    %s⚠%s Uses curl -L flag (not supported on RUTOS)\n" "$YELLOW" "$NC"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    if grep -q "curl.*--max-time" "$script"; then
        printf "    %s✓%s Uses curl --max-time (RUTOS compatible)\n" "$GREEN" "$NC"
    fi

    # Check for timeout usage
    timeout_count=$(grep -c "timeout.*grpcurl" "$script" 2>/dev/null || true)
    if [ -n "$timeout_count" ] && [ "$timeout_count" -gt 0 ]; then
        printf "    %s✓%s Uses timeout with grpcurl (%s instances)\n" "$GREEN" "$NC" "$timeout_count"
    fi

    echo ""
done

echo "======================================"
echo "AUDIT SUMMARY"
echo "======================================"
echo "Total scripts scanned: $TOTAL_SCRIPTS"
echo "Bash scripts: $BASH_SCRIPTS"
echo "POSIX scripts: $POSIX_SCRIPTS"
echo "Total compatibility issues found: $ISSUES_FOUND"
echo "Critical POSIX issues found: $CRITICAL_ISSUES"

if [ $ISSUES_FOUND -eq 0 ]; then
    printf "%s✅ No compatibility issues found - All scripts are RUTOS compatible%s\n" "$GREEN" "$NC"
elif [ $CRITICAL_ISSUES -eq 0 ]; then
    printf "%s⚠ %d minor compatibility issues found (no critical issues)%s\n" "$YELLOW" "$ISSUES_FOUND" "$NC"
else
    printf "%s❌ %d compatibility issues found (%d CRITICAL for busybox compatibility)%s\n" "$RED" "$ISSUES_FOUND" "$CRITICAL_ISSUES" "$NC"
fi

echo ""
echo "======================================"
echo "RECOMMENDATIONS"
echo "======================================"

if [ $CRITICAL_ISSUES -gt 0 ]; then
    printf "%s⚠ CRITICAL ACTIONS REQUIRED:%s\n" "$RED" "$NC"
    echo "1. Fix all CRITICAL issues marked above - they will break on RUTOS"
    echo "2. Replace 'local' variables with function parameters or global variables"
    echo "3. Change 'function()' syntax to 'function_name() {' format"
    echo "4. Replace '[[ ]]' double brackets with '[ ]' single brackets"
    echo "5. Replace bash arrays with space-separated strings or multiple variables"
    echo "6. Replace 'echo -e' with 'printf' for formatted output"
    echo "7. Replace 'source' commands with '.' (dot) sourcing"
    echo "8. Replace \$'\\n' constructs with actual newlines or printf"
    echo ""
fi

printf "%s📋 GENERAL RECOMMENDATIONS:%s\n" "$BLUE" "$NC"
echo "1. Use deploy-starlink-solution-rutos.sh for RUTOS deployment"
echo "2. Keep original scripts with bash shebangs for CI/CD workflows"
echo "3. Test RUTOS-specific scripts on actual hardware before deployment"
echo "4. Consider creating POSIX versions of critical deployment scripts"
echo "5. Use ShellCheck with POSIX compliance checks for validation"

echo ""
printf "%s🔧 POSIX COMPLIANCE GUIDELINES:%s\n" "$PURPLE" "$NC"
echo "• Use '#!/bin/sh' shebang for RUTOS-deployed scripts"
echo "• Use '[ ]' instead of '[[ ]]' for all conditional tests"
echo "• Use 'printf' instead of 'echo -e' for formatted output"
echo "• Use '.' instead of 'source' for sourcing files"
echo "• Avoid 'local' variables - use function parameters or globals"
echo "• Use space-separated strings instead of bash arrays"
echo "• Use 'function_name() {' instead of 'function function_name()'"

echo ""
if [ $CRITICAL_ISSUES -gt 0 ]; then
    printf "%s⚠ DEPLOYMENT BLOCKED: Fix %d critical issues before RUTOS deployment%s\n" "$RED" "$CRITICAL_ISSUES" "$NC"
    exit 1
else
    printf "%s✅ DEPLOYMENT READY: No critical POSIX compatibility issues%s\n" "$GREEN" "$NC"
    exit 0
fi
