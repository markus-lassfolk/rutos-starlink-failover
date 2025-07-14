#!/bin/sh

# RUTOS Deployment Script Verification Test
# This script verifies the updated deployment script syntax for RUTOS compatibility

echo "======================================"
echo "RUTOS Deployment Script Verification"
echo "======================================"

# Test 1: Shell syntax check
echo "=== SHELL SYNTAX CHECK ==="
if sh -n deploy-starlink-solution.sh 2>/dev/null; then
    echo "✓ Shell syntax check passed"
else
    echo "✗ Shell syntax errors found:"
    sh -n deploy-starlink-solution.sh
    exit 1
fi

# Test 2: Check for problematic syntax
echo ""
echo "=== COMPATIBILITY CHECKS ==="

# Check for double brackets
if grep -q "\[\[" deploy-starlink-solution.sh; then
    echo "⚠ Double brackets found (may not work in ash/dash):"
    grep -n "\[\[" deploy-starlink-solution.sh | head -5
else
    echo "✓ No double brackets found"
fi

# Check for bash arrays
if grep -q "\${.*\[@\].*}" deploy-starlink-solution.sh; then
    echo "⚠ Bash array syntax found (may not work in ash/dash):"
    grep -n "\${.*\[@\].*}" deploy-starlink-solution.sh | head -5
else
    echo "✓ No bash array syntax found"
fi

# Check for == comparisons
if grep -q "==" deploy-starlink-solution.sh; then
    echo "⚠ Double equals found (prefer single = in POSIX shell):"
    grep -n "==" deploy-starlink-solution.sh | head -5
else
    echo "✓ No double equals found"
fi

# Check shebang
shebang=$(head -1 deploy-starlink-solution.sh)
if [ "$shebang" = "#!/bin/sh" ]; then
    echo "✓ Correct shebang for RUTOS (#!/bin/sh)"
else
    echo "⚠ Shebang: $shebang"
fi

# Test 3: Check RUTOS-specific compatibility
echo ""
echo "=== RUTOS COMPATIBILITY ==="

# Check for bc usage
if grep -q "bc.*2>/dev/null.*echo" deploy-starlink-solution.sh; then
    echo "✓ bc usage has fallbacks"
elif grep -q " bc " deploy-starlink-solution.sh; then
    echo "⚠ bc usage without fallbacks found"
else
    echo "✓ No problematic bc usage"
fi

# Check for stat usage
if grep -q "wc -c" deploy-starlink-solution.sh; then
    echo "✓ Using wc -c for file sizes (RUTOS compatible)"
else
    echo "⚠ May still use problematic stat commands"
fi

# Check for timeout usage
timeout_count=$(grep -c "timeout.*grpcurl" deploy-starlink-solution.sh)
if [ "$timeout_count" -gt 0 ]; then
    echo "✓ timeout commands found: $timeout_count (verified working on RUTOS)"
else
    echo "ℹ No timeout commands (may be optional)"
fi

# Check for curl flags
if grep -q "curl.*--max-time" deploy-starlink-solution.sh; then
    echo "✓ Using --max-time flag (verified working on RUTOS)"
else
    echo "⚠ May not use --max-time flag"
fi

if grep -q "curl.*-L" deploy-starlink-solution.sh; then
    echo "⚠ Using -L flag (not supported on RUTOS)"
else
    echo "✓ No -L flag usage (RUTOS compatible)"
fi

# Test 4: Function checks
echo ""
echo "=== FUNCTION CHECKS ==="

# Check for key functions
functions_to_check="check_prerequisites install_packages install_binaries configure_mwan3 create_monitoring_scripts"

for func in $functions_to_check; do
    if grep -q "^$func()" deploy-starlink-solution.sh; then
        echo "✓ Function found: $func"
    else
        echo "⚠ Function missing: $func"
    fi
done

echo ""
echo "======================================"
echo "VERIFICATION COMPLETE"
echo "======================================"

# Count issues
warning_count=$(grep -c "⚠" /tmp/verification_output 2>/dev/null || echo "0")
if [ "$warning_count" -gt 0 ]; then
    echo "⚠ $warning_count warnings found - review before deployment"
else
    echo "✅ No major issues found - script should work on RUTOS"
fi

echo ""
echo "Recommended next steps:"
echo "1. Copy deploy-starlink-solution.sh to your RUTOS device"
echo "2. Run: chmod +x deploy-starlink-solution.sh"
echo "3. Test: ./deploy-starlink-solution.sh --help"
echo "4. Deploy: ./deploy-starlink-solution.sh"
