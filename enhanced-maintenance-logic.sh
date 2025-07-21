#!/bin/sh
# Enhanced System Maintenance Script Logic
# Showing how the new configuration controls would work

# Current logic pattern:
#   if [ "$RUN_MODE" = "fix" ] || [ "$RUN_MODE" = "auto" ]; then
#       # Perform fix
#   fi

# Enhanced logic pattern with configuration controls:

# 1. Mode determination with config override

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
determine_effective_mode() {
    # Use config override if specified, otherwise use command line parameter
    if [ -n "$MAINTENANCE_MODE_OVERRIDE" ]; then
        EFFECTIVE_MODE="$MAINTENANCE_MODE_OVERRIDE"
        log_info "Using config override mode: $EFFECTIVE_MODE"
    else
        EFFECTIVE_MODE="${1:-auto}"
        log_debug "Using default/parameter mode: $EFFECTIVE_MODE"
    fi

    # If auto-fix is disabled, downgrade auto to check
    if [ "$MAINTENANCE_AUTO_FIX_ENABLED" = "false" ] && [ "$EFFECTIVE_MODE" = "auto" ]; then
        EFFECTIVE_MODE="check"
        log_warning "Auto-fix disabled - running in check-only mode"
    fi
}

# 2. Service restart control
attempt_service_restart() {
    service_name="$1"

    # Check if service restarts are allowed
    if [ "$MAINTENANCE_SERVICE_RESTART_ENABLED" != "true" ]; then
        log_info "Service restart disabled by configuration - skipping $service_name"
        record_action "FOUND" "Service $service_name needs restart" "Restart disabled by config"
        return 1
    fi

    # Proceed with restart
    if [ "$EFFECTIVE_MODE" = "fix" ] || [ "$EFFECTIVE_MODE" = "auto" ]; then
        log_step "Restarting service: $service_name"
        /etc/init.d/"$service_name" restart
        record_action "FIXED" "Service $service_name restarted" "Service restart"
    else
        record_action "FOUND" "Service $service_name needs restart" "Fix mode disabled"
    fi
}

# 3. Database fix control
attempt_database_fix() {
    database_path="$1"

    # Check if database fixes are allowed
    if [ "$MAINTENANCE_DATABASE_FIX_ENABLED" != "true" ]; then
        log_warning "Database fix disabled by configuration - skipping $database_path"
        record_action "FOUND" "Database $database_path corrupted" "Database fix disabled by config"
        return 1
    fi

    # Proceed with database fix
    if [ "$EFFECTIVE_MODE" = "fix" ] || [ "$EFFECTIVE_MODE" = "auto" ]; then
        log_step "Fixing database: $database_path"
        # Database fix logic here...
        record_action "FIXED" "Database $database_path fixed" "Database recreation"
    else
        record_action "FOUND" "Database $database_path corrupted" "Fix mode disabled"
    fi
}

# 4. System reboot consideration
consider_system_reboot() {
    critical_count="$1"

    # Check if system reboots are allowed
    if [ "$MAINTENANCE_AUTO_REBOOT_ENABLED" != "true" ]; then
        log_info "System reboot disabled by configuration"
        return 1
    fi

    # Check if we've reached the reboot threshold
    if [ "$critical_count" -ge "$MAINTENANCE_REBOOT_THRESHOLD" ]; then
        log_warning "Critical issues ($critical_count) exceed reboot threshold ($MAINTENANCE_REBOOT_THRESHOLD)"

        # Check reboot cooldown to prevent reboot loops
        reboot_file="/tmp/last_maintenance_reboot"
        if [ -f "$reboot_file" ]; then
            last_reboot=$(cat "$reboot_file")
            current_time=$(date +%s)
            time_since_reboot=$((current_time - last_reboot))

            # Require at least 1 hour between reboots
            if [ "$time_since_reboot" -lt 3600 ]; then
                log_warning "Reboot attempted recently - skipping (cooldown)"
                return 1
            fi
        fi

        # Schedule reboot and record it
        log_error "Scheduling system reboot due to critical maintenance issues"
        date +%s >"$reboot_file"
        record_action "CRITICAL" "System reboot scheduled" "Critical issues: $critical_count"

        # Notify before reboot
        send_maintenance_notification "CRITICAL: System rebooting due to maintenance issues"

        # Reboot in 60 seconds to allow notification to send
        (
            sleep 60
            reboot
        ) &

        return 0
    fi

    return 1
}

# 5. Safety limits
check_fix_limits() {
    fixes_this_run="$1"

    if [ "$fixes_this_run" -ge "$MAINTENANCE_MAX_FIXES_PER_RUN" ]; then
        log_warning "Maximum fixes per run reached ($MAINTENANCE_MAX_FIXES_PER_RUN) - stopping"
        record_action "FOUND" "Additional issues present" "Fix limit reached"
        return 1
    fi

    return 0
}

# Integration example:
main_maintenance_loop() {
    determine_effective_mode "$1"

    fixes_count=0

    # Example check
    echo "enhanced-maintenance-logic.sh v$SCRIPT_VERSION"
    echo ""
    if disk_usage_high; then
        if check_fix_limits "$fixes_count"; then
            attempt_disk_cleanup
            fixes_count=$((fixes_count + 1))
        fi
    fi

    # Another example
    if database_corrupted; then
        if check_fix_limits "$fixes_count"; then
            attempt_database_fix "/var/lib/uci.db"
            fixes_count=$((fixes_count + 1))
        fi
    fi

    # Cooldown after fixes
    if [ "$fixes_count" -gt 0 ] && [ "$MAINTENANCE_COOLDOWN_AFTER_FIXES" -gt 0 ]; then
        log_info "Applied $fixes_count fixes - cooling down for $MAINTENANCE_COOLDOWN_AFTER_FIXES seconds"
        sleep "$MAINTENANCE_COOLDOWN_AFTER_FIXES"
    fi

    # Consider reboot if critical issues persist
    if [ "$CRITICAL_ISSUES_COUNT" -gt 0 ]; then
        consider_system_reboot "$CRITICAL_ISSUES_COUNT"
    fi
}
