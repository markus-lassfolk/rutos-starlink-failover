#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC2154
# System Configuration for RUTOS Starlink Monitoring

# Template version (auto-updated by update-version.sh)
TEMPLATE_VERSION="2.7.0"
readonly TEMPLATE_VERSION
# This file defines expected system components for dynamic testing and validation

# Version information for validation compliance
# Note: Only set SCRIPT_VERSION if not already set (prevents conflicts when sourced)
if [ -z "${SCRIPT_VERSION:-}" ]; then
    # Version information (auto-updated by update-version.sh)
    SCRIPT_VERSION="2.7.0"
    readonly SCRIPT_VERSION
fi
# Used for troubleshooting: echo "Configuration version: $SCRIPT_VERSION"

# Expected cron jobs and their patterns

EXPECTED_CRON_JOBS="
starlink_monitor_unified-rutos.sh:every_minute:Monitor primary connectivity and failover
starlink_logger_unified-rutos.sh:every_minute:Log connection status and events  
check_starlink_api-rutos.sh:daily_6am:Check Starlink API connectivity
system-maintenance-rutos.sh:every_6_hours:Perform system maintenance and issue fixes
"

# Expected script locations
SCRIPT_LOCATIONS="
starlink_monitor_unified-rutos.sh:/usr/local/starlink-monitor/scripts/
starlink_logger_unified-rutos.sh:/usr/local/starlink-monitor/scripts/
check_starlink_api-rutos.sh:/usr/local/starlink-monitor/scripts/
system-maintenance-rutos.sh:/usr/local/starlink-monitor/scripts/
99-pushover_notify-rutos.sh:/etc/hotplug.d/iface/
"

# Expected configuration files
# shellcheck disable=SC2034  # These variables are used by external test scripts
EXPECTED_CONFIGS="
/etc/starlink-config/config.sh:primary_config:Primary system configuration
/usr/local/starlink-monitor/config/config.sh:backup_config:Backup configuration copy
"

# Expected binaries and their locations
# shellcheck disable=SC2034  # These variables are used by external test scripts
EXPECTED_BINARIES="
grpcurl:/usr/local/starlink-monitor/grpcurl:gRPC communication tool
jq:/usr/local/starlink-monitor/jq:JSON processing tool
"

# Expected directories
# shellcheck disable=SC2034  # These variables are used by external test scripts
EXPECTED_DIRECTORIES="
/usr/local/starlink-monitor:main_install:Main installation directory
/etc/starlink-config:persistent_config:Persistent configuration directory
/etc/starlink-logs:persistent_logs:Persistent log directory
/usr/local/starlink-monitor/scripts:script_dir:Main scripts directory
/usr/local/starlink-monitor/scripts/tests:test_dir:Test scripts directory
"

# Expected services and processes
# shellcheck disable=SC2034  # These variables are used by external test scripts
EXPECTED_SERVICES="
crond:cron_daemon:Cron daemon for scheduled tasks
"

# Cron schedule patterns for validation
CRON_PATTERNS="
starlink_monitor_unified-rutos.sh:^\* \* \* \* \*.*starlink_monitor_unified-rutos\.sh
starlink_logger_unified-rutos.sh:^\* \* \* \* \*.*starlink_logger_unified-rutos\.sh  
check_starlink_api-rutos.sh:^0 6 \* \* \*.*check_starlink_api.*\.sh
system-maintenance-rutos.sh:^0 \*/6 \* \* \*.*system-maintenance-rutos\.sh
"

# Helper functions for parsing configuration

# Get expected cron jobs
get_expected_cron_jobs() {
    echo "$EXPECTED_CRON_JOBS" | grep -v "^$" | grep -v "^#"
}

# Get expected script locations
get_expected_script_locations() {
    echo "$SCRIPT_LOCATIONS" | grep -v "^$" | grep -v "^#"
}

# Get cron pattern for a script
get_cron_pattern() {
    script_name="$1"
    echo "$CRON_PATTERNS" | grep "^$script_name:" | cut -d: -f2
}

# Get script description
get_script_description() {
    script_name="$1"
    echo "$EXPECTED_CRON_JOBS" | grep "^$script_name:" | cut -d: -f3
}

# Get expected location for script
get_script_location() {
    script_name="$1"
    echo "$SCRIPT_LOCATIONS" | grep "^$script_name:" | cut -d: -f2
}

# List all expected scripts
list_expected_scripts() {
    get_expected_cron_jobs | cut -d: -f1
}

# Count expected cron jobs
count_expected_cron_jobs() {
    get_expected_cron_jobs | wc -l
}

# Validate if all expected components exist
validate_system_components() {
    # This function can be called by test scripts to validate the system
    echo "System validation functions available in system-config.sh"
}
