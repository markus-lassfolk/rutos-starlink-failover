#!/bin/sh

# RUTOS Script Compatibility Audit
# This script checks all shell scripts in the repository for RUTOS compatibility issues

echo "======================================"
echo "RUTOS Script Compatibility Audit"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TOTAL_SCRIPTS=0
BASH_SCRIPTS=0
POSIX_SCRIPTS=0
ISSUES_FOUND=0

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

            # Check for bash-specific syntax
            if grep -q "\[\[" "$script"; then
                printf "%s[WARN]%s Uses double brackets (bash-specific)\n" "$YELLOW" "$NC"
            fi

            if grep -q "==" "$script"; then
                printf "%s[INFO]%s Uses == comparison (bash preference)\n" "$YELLOW" "$NC"
            fi

            if grep -q "\${.*\[@\].*}" "$script"; then
                printf "%s[WARN]%s Uses bash array syntax\n" "$YELLOW" "$NC"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
            ;;

        "#!/bin/sh")
            printf "%s[POSIX]%s Uses POSIX shell shebang\n" "$GREEN" "$NC"
            POSIX_SCRIPTS=$((POSIX_SCRIPTS + 1))

            # Check for problematic syntax in POSIX scripts
            if grep -q "\[\[" "$script"; then
                printf "%s[ERROR]%s POSIX script uses double brackets\n" "$RED" "$NC"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi

            if grep -q "==" "$script"; then
                printf "%s[WARN]%s POSIX script uses == (should use =)\n" "$YELLOW" "$NC"
            fi
            ;;

        *)
            printf "%s[UNKNOWN]%s Unknown or missing shebang: %s\n" "$YELLOW" "$NC" "$shebang"
            ;;
    esac

    # Check for RUTOS-specific compatibility issues
    echo "  Compatibility checks:"

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
    timeout_count=$(grep -c "timeout.*grpcurl" "$script" 2>/dev/null || echo "0")
    if [ "$timeout_count" -gt 0 ]; then
        echo "    [✓] Uses timeout with grpcurl ($timeout_count instances)"
    fi

    echo ""
done

echo "======================================"
echo "AUDIT SUMMARY"
echo "======================================"
echo "Total scripts scanned: $TOTAL_SCRIPTS"
echo "Bash scripts: $BASH_SCRIPTS"
echo "POSIX scripts: $POSIX_SCRIPTS"
echo "Compatibility issues found: $ISSUES_FOUND"

if [ $ISSUES_FOUND -eq 0 ]; then
    printf "%s✅ No critical compatibility issues found%s\n" "$GREEN" "$NC"
else
    printf "%s⚠ %d compatibility issues need attention%s\n" "$YELLOW" "$ISSUES_FOUND" "$NC"
fi

echo ""
echo "Recommendations:"
echo "1. Use deploy-starlink-solution-rutos.sh for RUTOS deployment"
echo "2. Keep original scripts with bash shebangs for CI/CD"
echo "3. Test RUTOS-specific scripts on actual hardware"
echo "4. Consider creating POSIX versions of critical scripts"
