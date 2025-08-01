#!/bin/sh
set -e

# =============================================================================
# Test Script: Verify RUTOS Script Version Conflicts Are Resolved
# This script tests that the version conflict fixes work correctly
# =============================================================================

SCRIPT_VERSION="2.8.0"

# Simple test logging
test_log() {
    printf "[TEST] %s\n" "$1"
}

test_error() {
    printf "[ERROR] %s\n" "$1" >&2
}

test_success() {
    printf "[SUCCESS] %s\n" "$1"
}

# Test function to verify script version handling
test_script_version_handling() {
    script_path="$1"
    script_name="$(basename "$script_path")"
    
    test_log "Testing: $script_name"
    
    # Test if script can source without readonly conflicts
    if echo "$script_path" | grep -q -- "-rutos\.sh$"; then
        test_log "RUTOS script detected: $script_name"
        
        # Check that no readonly SCRIPT_VERSION exists
        readonly_count=$(grep -c "^[[:space:]]*readonly[[:space:]]*SCRIPT_VERSION" "$script_path" 2>/dev/null || echo 0)
        if [ "$readonly_count" -gt 0 ]; then
            test_error "❌ $script_name still has readonly SCRIPT_VERSION (conflict source)"
            return 1
        else
            test_success "✅ $script_name has no readonly SCRIPT_VERSION conflicts"
        fi
        
        # Check that SCRIPT_VERSION is defined
        version_count=$(grep -c "^[[:space:]]*SCRIPT_VERSION=" "$script_path" 2>/dev/null || echo 0)
        if [ "$version_count" -eq 1 ]; then
            test_success "✅ $script_name has exactly one SCRIPT_VERSION definition"
        else
            test_error "❌ $script_name has $version_count SCRIPT_VERSION definitions (should be 1)"
            return 1
        fi
        
    else
        test_log "Standalone script detected: $script_name"
        # For standalone scripts, readonly is OK
    fi
    
    return 0
}

# Main test execution
main() {
    test_log "=========================================="
    test_log "RUTOS Script Version Conflict Test"
    test_log "=========================================="
    
    failed_tests=0
    total_tests=0
    
    # Test the specific scripts mentioned in the original error
    test_scripts="
        Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh
        Starlink-RUTOS-Failover/starlink_logger_unified-rutos.sh
    "
    
    for script_path in $test_scripts; do
        if [ -f "$script_path" ]; then
            total_tests=$((total_tests + 1))
            if ! test_script_version_handling "$script_path"; then
                failed_tests=$((failed_tests + 1))
            fi
        else
            test_error "Script not found: $script_path"
            failed_tests=$((failed_tests + 1))
            total_tests=$((total_tests + 1))
        fi
    done
    
    # Test a few more RUTOS scripts
    test_log "Testing additional RUTOS scripts..."
    find scripts -name "*-rutos.sh" -type f | head -5 | while IFS= read -r script_path; do
        total_tests=$((total_tests + 1))
        if ! test_script_version_handling "$script_path"; then
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    # Summary
    test_log "=========================================="
    test_log "Test Results"
    test_log "=========================================="
    test_log "Total tests: $total_tests"
    test_log "Failed tests: $failed_tests"
    test_log "Passed tests: $((total_tests - failed_tests))"
    
    if [ "$failed_tests" -eq 0 ]; then
        test_success "🎉 All tests passed! RUTOS version conflicts are resolved."
        test_log ""
        test_log "You can now run the problematic scripts without readonly errors:"
        test_log "  DEBUG=1 CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_monitor_unified-rutos.sh"
        test_log "  DEBUG=1 CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_logger_unified-rutos.sh"
        return 0
    else
        test_error "❌ $failed_tests tests failed. Some version conflicts remain."
        return 1
    fi
}

# Run tests
main "$@"
