#!/bin/sh
# shellcheck disable=SC1091 # Dynamic source files

# RUTOS Deployment Script Verification Test
# This script verifies the updated deployment script syntax for RUTOS compatibility

# Initialize warning counter
warning_count=0

# Logging functions
log_warn() {
	printf "⚠ %s\n" "$1"
	warning_count=$((warning_count + 1))
}

log_success() {
	printf "✓ %s\n" "$1"
}

log_info() {
	printf "ℹ %s\n" "$1"
}

echo "======================================"
echo "RUTOS Deployment Script Verification"
echo "======================================"

# Determine which script to check
if [ -f "deploy-starlink-solution-rutos.sh" ]; then
	SCRIPT_FILE="deploy-starlink-solution-rutos.sh"
	echo "Checking RUTOS-specific version: $SCRIPT_FILE"
elif [ -f "deploy-starlink-solution.sh" ]; then
	SCRIPT_FILE="deploy-starlink-solution.sh"
	echo "Checking bash version: $SCRIPT_FILE"
else
	echo "❌ No deployment script found!"
	exit 1
fi
echo

# Test 1: Shell syntax check
echo "=== SHELL SYNTAX CHECK ==="
if sh -n "$SCRIPT_FILE" 2>/dev/null; then
	log_success "Shell syntax check passed"
else
	echo "✗ Shell syntax errors found:"
	sh -n "$SCRIPT_FILE"
	exit 1
fi

# Test 2: Check for problematic syntax
echo ""
echo "=== COMPATIBILITY CHECKS ==="

# Check for double brackets
if grep -q "\[\[" "$SCRIPT_FILE"; then
	log_warn "Double brackets found (may not work in ash/dash):"
	grep -n "\[\[" "$SCRIPT_FILE" | head -5
else
	log_success "No double brackets found"
fi

# Check for bash arrays
if grep -q "\${.*\[@\].*}" "$SCRIPT_FILE"; then
	log_warn "Bash array syntax found (may not work in ash/dash):"
	grep -n "\${.*\[@\].*}" "$SCRIPT_FILE" | head -5
else
	log_success "No bash array syntax found"
fi

# Check for == comparisons (but not in comments)
if grep -v '^[[:space:]]*#' "$SCRIPT_FILE" | grep -q "=="; then
	log_warn "Double equals found (prefer single = in POSIX shell):"
	grep -v '^[[:space:]]*#' "$SCRIPT_FILE" | grep -n "==" | head -5
else
	log_success "No double equals found"
fi

# Check shebang
shebang=$(head -1 "$SCRIPT_FILE")
case "$shebang" in
"#!/bin/sh"* | "#!/bin/dash"* | "#!/bin/ash"*)
	log_success "POSIX shell shebang: $shebang"
	;;
"#!/bin/bash"*)
	if [ "$SCRIPT_FILE" = "deploy-starlink-solution.sh" ]; then
		log_info "Bash shebang (expected for CI/CD version): $shebang"
	else
		log_warn "Bash shebang in RUTOS script: $shebang"
	fi
	;;
*)
	log_warn "Unknown shebang: $shebang"
	;;
esac

# Test 3: Check RUTOS-specific compatibility
echo ""
echo "=== RUTOS COMPATIBILITY ==="

# Check for bc usage
if grep -q "bc.*2>/dev/null.*echo" "$SCRIPT_FILE"; then
	log_success "bc usage has fallbacks"
elif grep -q " bc " "$SCRIPT_FILE"; then
	log_warn "bc usage without fallbacks found"
else
	log_success "No problematic bc usage"
fi

# Check for stat usage
if grep -q "wc -c" "$SCRIPT_FILE"; then
	log_success "Using wc -c for file sizes (RUTOS compatible)"
else
	log_warn "May still use problematic stat commands"
fi

# Check for timeout usage
timeout_count=$(grep -c "timeout.*grpcurl" "$SCRIPT_FILE" 2>/dev/null || echo "0")
if [ "$timeout_count" -gt 0 ]; then
	log_success "timeout commands found: $timeout_count (verified working on RUTOS)"
else
	log_info "No timeout commands (may be optional)"
fi

# Check for curl flags
if grep -q "curl.*--max-time" "$SCRIPT_FILE"; then
	log_success "Using --max-time flag (verified working on RUTOS)"
else
	log_warn "May not use --max-time flag"
fi

if grep -q "curl.*-L" "$SCRIPT_FILE"; then
	log_warn "Using -L flag (not supported on RUTOS)"
else
	log_success "No problematic curl -L flag usage"
fi

# Test 4: Function checks
echo ""
echo "=== FUNCTION CHECKS ==="

# Check for key functions
functions_to_check="check_prerequisites install_packages install_binaries configure_mwan3 create_monitoring_scripts"

for func in $functions_to_check; do
	if grep -q "^$func()" "$SCRIPT_FILE"; then
		log_success "Function found: $func"
	else
		log_warn "Function missing: $func"
	fi
done

echo ""
echo "======================================"
echo "VERIFICATION COMPLETE"
echo "======================================"

# Use our warning counter instead of non-existent file
if [ "$warning_count" -gt 0 ]; then
	echo "⚠ $warning_count warnings found - review before deployment"
else
	echo "✅ No major issues found - script should work on RUTOS"
fi

echo ""
echo "Recommended next steps:"
echo "1. Copy $SCRIPT_FILE to your RUTOS device"
echo "2. Run: chmod +x $SCRIPT_FILE"
echo "3. Test: ./$SCRIPT_FILE --help"
echo "4. Deploy: ./$SCRIPT_FILE"
