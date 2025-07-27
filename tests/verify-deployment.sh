#!/bin/sh

# RUTOS Deployment Script Verification Test
# Simple verification script for RUTOS compatibility

# Initialize warning counter

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION
warning_count=0

# Simple logging functions (RUTOS compatible)
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
SCRIPT_FILE=""

# Check if script path provided as argument
if [ -n "$1" ]; then
    if [ -f "$1" ]; then
        SCRIPT_FILE="$1"
        echo "Checking specified script: $SCRIPT_FILE"
    else
        echo "❌ Specified script not found: $1"
        exit 1
    fi
else
    # Look in common locations
    for location in \
        "deploy-starlink-solution-rutos.sh" \
        "deploy-starlink-solution.sh" \
        "/root/deploy-starlink-solution-rutos.sh" \
        "/root/deploy-starlink-solution.sh" \
        "/tmp/deploy-starlink-solution-rutos.sh" \
        "/tmp/deploy-starlink-solution.sh"; do
        if [ -f "$location" ]; then
            SCRIPT_FILE="$location"
            echo "Found script: $SCRIPT_FILE"
            break
        fi
    done

    if [ -z "$SCRIPT_FILE" ]; then
        echo "❌ No deployment script found!"
        echo ""
        echo "Usage: $0 [script-path]"
        echo "   or: Copy deployment script to current directory"
        echo ""
        echo "Searched locations:"
        echo "  - Current directory"
        echo "  - /root/"
        echo "  - /tmp/"
        exit 1
    fi
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

# Check for double brackets (avoid empty grep)
if [ -n "$SCRIPT_FILE" ] && grep -q "\[\[" "$SCRIPT_FILE" 2>/dev/null; then
    log_warn "Double brackets found (may not work in ash/dash)"
    grep -n "\[\[" "$SCRIPT_FILE" 2>/dev/null | head -3
else
    log_success "No double brackets found"
fi

# Check for bash arrays
if [ -n "$SCRIPT_FILE" ] && grep -q "\${.*\[@\].*}" "$SCRIPT_FILE" 2>/dev/null; then
    log_warn "Bash array syntax found (may not work in ash/dash)"
    grep -n "\${.*\[@\].*}" "$SCRIPT_FILE" 2>/dev/null | head -3
else
    log_success "No bash array syntax found"
fi

# Check for == comparisons (but not in comments)
if [ -n "$SCRIPT_FILE" ] && grep -v '^[[:space:]]*#' "$SCRIPT_FILE" 2>/dev/null | grep -q "==" 2>/dev/null; then
    log_warn "Double equals found (prefer single = in POSIX shell)"
else
    log_success "No problematic double equals found"
fi

# Check shebang
if [ -n "$SCRIPT_FILE" ]; then
    shebang=$(head -1 "$SCRIPT_FILE" 2>/dev/null)
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
fi

# Test 3: Check RUTOS-specific compatibility
echo ""
echo "=== RUTOS COMPATIBILITY ==="

echo "verify-deployment.sh v$SCRIPT_VERSION"
echo ""
# Check for bc usage
if [ -n "$SCRIPT_FILE" ] && grep -q "bc.*2>/dev/null" "$SCRIPT_FILE" 2>/dev/null; then
    echo "verify-deployment.sh v$SCRIPT_VERSION"
    echo ""
    log_success "bc usage has fallbacks"
elif [ -n "$SCRIPT_FILE" ] && grep -q " bc " "$SCRIPT_FILE" 2>/dev/null; then
    echo "verify-deployment.sh v$SCRIPT_VERSION"
    echo ""
    log_warn "bc usage without fallbacks found"
else
    echo "verify-deployment.sh v$SCRIPT_VERSION"
    echo ""
    log_success "No problematic bc usage"
fi

echo "verify-deployment.sh v$SCRIPT_VERSION"
echo ""
# Check for stat usage
if [ -n "$SCRIPT_FILE" ] && grep -q "wc -c" "$SCRIPT_FILE" 2>/dev/null; then
    log_success "Using wc -c for file sizes (RUTOS compatible)"
else
    log_info "File size detection method not confirmed"
fi

echo "verify-deployment.sh v$SCRIPT_VERSION"
echo ""
# Check for timeout usage
if [ -n "$SCRIPT_FILE" ]; then
    timeout_count=$(grep -c "timeout.*grpcurl" "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$timeout_count" -gt 0 ]; then
        log_success "timeout commands found: $timeout_count (verified working on RUTOS)"
    else
        log_info "No timeout commands (may be optional)"
    fi
fi

# Check for curl flags
if [ -n "$SCRIPT_FILE" ] && grep -q "curl.*--max-time" "$SCRIPT_FILE" 2>/dev/null; then
    log_success "Using --max-time flag (verified working on RUTOS)"
else
    log_info "curl timeout method not confirmed"
fi

if [ -n "$SCRIPT_FILE" ] && grep -q "curl.*-L" "$SCRIPT_FILE" 2>/dev/null; then
    log_warn "Using -L flag (not supported on RUTOS)"
else
    echo "verify-deployment.sh v$SCRIPT_VERSION"
    echo ""
    log_success "No problematic curl -L flag usage"
fi

# Test 4: Function checks
echo ""
echo "=== FUNCTION CHECKS ==="

# Check for key functions
functions_to_check="check_prerequisites install_packages install_binaries"

if [ -n "$SCRIPT_FILE" ]; then
    for func in $functions_to_check; do
        if grep -q "^$func()" "$SCRIPT_FILE" 2>/dev/null; then
            log_success "Function found: $func"
        else
            log_info "Function not found: $func (may be optional)"
        fi
    done
fi

echo ""
echo "======================================"
echo "VERIFICATION COMPLETE"
echo "======================================"

# Use our warning counter
if [ "$warning_count" -gt 0 ]; then
    printf "⚠ %d warnings found - review before deployment\n" "$warning_count"
else
    echo "✅ No major issues found - script should work on RUTOS"
fi

echo ""
echo "Recommended next steps:"
if [ -n "$SCRIPT_FILE" ]; then
    echo "1. Copy $SCRIPT_FILE to your RUTOS device"
    echo "2. Run: chmod +x $SCRIPT_FILE"
    echo "verify-deployment.sh v$SCRIPT_VERSION"
    echo ""
    echo "3. Test: ./$SCRIPT_FILE --help"
    echo "4. Deploy: ./$SCRIPT_FILE"
fi
