#!/bin/bash

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

# Find all shell scripts
find . -type f -name "*.sh" | while read -r script; do
    TOTAL_SCRIPTS=$((TOTAL_SCRIPTS + 1))
    
    echo "=== Checking: $script ==="
    
    # Check shebang
    shebang=$(head -1 "$script")
    case "$shebang" in
        "#!/bin/bash")
            echo -e "${BLUE}[BASH]${NC} Uses bash shebang"
            BASH_SCRIPTS=$((BASH_SCRIPTS + 1))
            
            # Check for bash-specific syntax
            if grep -q "\[\[" "$script"; then
                echo -e "${YELLOW}[WARN]${NC} Uses double brackets (bash-specific)"
            fi
            
            if grep -q "==" "$script"; then
                echo -e "${YELLOW}[INFO]${NC} Uses == comparison (bash preference)"
            fi
            
            if grep -q "\${.*\[@\].*}" "$script"; then
                echo -e "${YELLOW}[WARN]${NC} Uses bash array syntax"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
            ;;
            
        "#!/bin/sh")
            echo -e "${GREEN}[POSIX]${NC} Uses POSIX shell shebang"
            POSIX_SCRIPTS=$((POSIX_SCRIPTS + 1))
            
            # Check for problematic syntax in POSIX scripts
            if grep -q "\[\[" "$script"; then
                echo -e "${RED}[ERROR]${NC} POSIX script uses double brackets"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
            
            if grep -q "==" "$script"; then
                echo -e "${YELLOW}[WARN]${NC} POSIX script uses == (should use =)"
            fi
            ;;
            
        *)
            echo -e "${YELLOW}[UNKNOWN]${NC} Unknown or missing shebang: $shebang"
            ;;
    esac
    
    # Check for RUTOS-specific compatibility issues
    echo "  Compatibility checks:"
    
    # Check for bc usage
    if grep -q " bc " "$script"; then
        if grep -q "bc.*2>/dev/null.*echo" "$script"; then
            echo -e "    ${GREEN}✓${NC} bc usage has fallbacks"
        else
            echo -e "    ${YELLOW}⚠${NC} bc usage without fallbacks"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi
    
    # Check for stat usage
    if grep -q "stat -[cf]" "$script"; then
        echo -e "    ${RED}✗${NC} Uses stat with -c/-f flags (RUTOS incompatible)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    elif grep -q "wc -c" "$script"; then
        echo -e "    ${GREEN}✓${NC} Uses wc -c for file sizes (RUTOS compatible)"
    fi
    
    # Check for curl flags
    if grep -q "curl.*-L" "$script"; then
        echo -e "    ${YELLOW}⚠${NC} Uses curl -L flag (not supported on RUTOS)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
    
    if grep -q "curl.*--max-time" "$script"; then
        echo -e "    ${GREEN}✓${NC} Uses curl --max-time (RUTOS compatible)"
    fi
    
    # Check for timeout usage
    timeout_count=$(grep -c "timeout.*grpcurl" "$script" 2>/dev/null || echo "0")
    if [ "$timeout_count" -gt 0 ]; then
        echo -e "    ${GREEN}✓${NC} Uses timeout with grpcurl ($timeout_count instances)"
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
    echo -e "${GREEN}✅ No critical compatibility issues found${NC}"
else
    echo -e "${YELLOW}⚠ $ISSUES_FOUND compatibility issues need attention${NC}"
fi

echo ""
echo "Recommendations:"
echo "1. Use deploy-starlink-solution-rutos.sh for RUTOS deployment"
echo "2. Keep original scripts with bash shebangs for CI/CD"
echo "3. Test RUTOS-specific scripts on actual hardware"
echo "4. Consider creating POSIX versions of critical scripts"
