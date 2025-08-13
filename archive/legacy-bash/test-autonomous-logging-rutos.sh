#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/scripts/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "test-autonomous-logging-rutos.sh" "$SCRIPT_VERSION"

# Test autonomous error logging system
main() {
    log_info "=== Testing Autonomous Error Logging System ==="
    log_info "Bootstrap Mode Test: Centralized logging should be ENABLED (no config exists)"
    
    # Show autonomous logging status
    autonomous_logging_status
    
    log_info ""
    log_info "=== Config Detection Test ==="
    
    # Show config detection logic
    config_path="${CONFIG_DIR:-/etc/starlink-failover}/config.sh"
    if [ ! -f "$config_path" ]; then
        log_info "✓ Bootstrap mode detected: Config file does not exist ($config_path)"
        log_info "  → Centralized error logging should be AUTO-ENABLED"
    else
        log_info "✓ Post-installation mode: Config file exists ($config_path)"
        if grep -q "ENABLE_AUTONOMOUS_ERROR_LOGGING=.*true" "$config_path" 2>/dev/null; then
            log_info "  → ENABLE_AUTONOMOUS_ERROR_LOGGING=true found in config"
            log_info "  → Centralized error logging should be ENABLED"
        else
            log_info "  → ENABLE_AUTONOMOUS_ERROR_LOGGING not set to true in config"
            log_info "  → Centralized error logging should be DISABLED"
        fi
    fi
    
    log_info ""
    log_info "=== Testing Different Error Severities ==="
    
    # Test different error severities
    autonomous_error "LOW" "This is a low priority test error"
    autonomous_error "MEDIUM" "This is a medium priority test warning"
    autonomous_error "HIGH" "This is a high priority test error"
    autonomous_error "CRITICAL" "This is a critical test error"
    
    log_info ""
    log_info "=== Testing Traditional Error Functions with Enhanced Logging ==="
    
    # Test enhanced traditional functions
    capture_warning "This is a test warning for autonomous monitoring" "test-script.sh" "42" "test_function"
    capture_high_error "This is a high priority error for autonomous monitoring" "test-script.sh" "43" "test_function"
    capture_critical_error "This is a critical error for autonomous monitoring" "test-script.sh" "44" "test_function"
    
    log_info ""
    log_info "=== Testing Command Execution Failure Capture ==="
    
    # Test safe_execute error capture (this will fail intentionally)
    if ! safe_execute "false" "Test command that should fail"; then
        log_info "Expected command failure was captured by autonomous system"
    fi
    
    # Test another failing command
    if ! safe_execute "exit 42" "Test command with specific exit code"; then
        log_info "Command with exit code 42 was captured by autonomous system"
    fi
    
    log_info ""
    log_info "=== Testing log_error_with_context Enhancement ==="
    
    # Test enhanced context logging
    log_error_with_context "This error will be captured by autonomous system" "test-script.sh" "100" "test_context_function"
    
    log_info ""
    log_success "Autonomous error logging test completed!"
    
    if autonomous_logging_available; then
        log_info "Check the error log file for captured errors: ${RUTOS_ERROR_LOG:-/tmp/rutos-errors.log}"
        log_info "These errors would be processed by autonomous-error-monitor-rutos.sh for GitHub issue creation"
    else
        log_warning "Autonomous error logging not available - only basic logging was used"
    fi
}

# Execute main function
main "$@"
