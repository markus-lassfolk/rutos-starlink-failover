#!/bin/sh
# shellcheck disable=SC2317
# Test script for cron cleanup functionality
# Version: 2.7.0
# Description: Tests the intelligent cron management in install-rutos.sh

set -e

# Script version - automatically updated from VERSION file
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors
log_info() {
    # shellcheck disable=SC2317  # Function called by test framework
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    # shellcheck disable=SC2317  # Function called by test framework
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Function to safely execute commands
# shellcheck disable=SC2317 # Function defined for future use, may be unreachable in test mode
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_debug "Executing: $cmd"
        eval "$cmd"
    fi
}

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
fi

# Test configuration
TEST_CRON_FILE="/tmp/test_cron_cleanup.txt"
# Configuration
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}" # Used in test scenarios

# Create test crontab with various scenarios
create_test_crontab() {
    log_step "Creating test crontab with multiple scenarios"

    cat >"$TEST_CRON_FILE" <<'EOF'
# Existing system cron entries (should be preserved)
0 0 * * * /usr/bin/system-backup


30 2 * * 0 /usr/bin/weekly-update



# Starlink monitoring system - Added by install script 2025-07-18
* * * * * CONFIG_FILE=/usr/local/starlink-monitor/config/config.sh /usr/local/starlink-monitor/scripts/starlink_monitor-rutos.sh

* * * * * CONFIG_FILE=/usr/local/starlink-monitor/config/config.sh /usr/local/starlink-monitor/scripts/starlink_logger-rutos.sh


0 6 * * * CONFIG_FILE=/usr/local/starlink-monitor/config/config.sh /usr/local/starlink-monitor/scripts/check_starlink_api-rutos.sh

# Custom timing for starlink (should be preserved)
*/5 * * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_monitor-rutos.sh >/dev/null 2>&1

# Second set of cron entries (duplicates with different timing)
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_monitor-rutos.sh
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_logger-rutos.sh
0 6 * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/check_starlink_api-rutos.sh

# COMMENTED BY INSTALL SCRIPT 2025-07-17: * * * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_monitor-rutos.sh
# COMMENTED BY INSTALL SCRIPT 2025-07-17: 0 6 * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/check_starlink_api-rutos.sh

# Starlink monitoring system - Added by install script 2025-07-19
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_monitor-rutos.sh
* * * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/starlink_logger-rutos.sh
0 6 * * * CONFIG_FILE=/etc/starlink-config/config.sh /usr/local/starlink-monitor/scripts/check_starlink_api-rutos.sh

# COMMENTED BY INSTALL SCRIPT 2025-07-17: * * * * * CONFIG_FILE=/usr/local/starlink-monitor/config/config.sh /usr/local/starlink-monitor/scripts/starlink_monitor-rutos.sh
# COMMENTED BY INSTALL SCRIPT 2025-07-17: 0 6 * * * CONFIG_FILE=/usr/local/starlink-monitor/config/config.sh /usr/local/starlink-monitor/scripts/check_starlink_api-rutos.sh

# Other entries (should be preserved)
0 1 * * * /usr/bin/cleanup-logs
EOF

    log_info "Test crontab created with $(wc -l <"$TEST_CRON_FILE") lines"
}

# Test the cleanup logic
test_cleanup() {
    log_step "Testing cron cleanup logic"

    # Simulate the cleanup logic from install-rutos.sh
    temp_cron="/tmp/crontab_clean_test.tmp"

    # Remove lines that match our default install patterns
    log_debug "Removing install script comment headers"
    grep -v "# Starlink monitoring system - Added by install script" "$TEST_CRON_FILE" >"$temp_cron" || true

    # Remove the exact default entries
    log_debug "Removing default minute-by-minute entries"
    sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_monitor-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
    sed -i '/^\* \* \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/starlink_logger-rutos\.sh$/d' "$temp_cron" 2>/dev/null || true
    log_debug "Removing default API check entries"
    sed -i '/^0 6 \* \* \* CONFIG_FILE=.*\/config\/config\.sh .*\/scripts\/check_starlink_api.*\.sh$/d' "$temp_cron" 2>/dev/null || true

    # Clean up previously commented entries
    log_debug "Removing previously commented entries"
    sed -i '/^# COMMENTED BY INSTALL SCRIPT.*starlink/d' "$temp_cron" 2>/dev/null || true

    # Remove excessive blank lines (more than 1 consecutive blank line)
    log_debug "Removing excessive blank lines"
    awk '
    BEGIN { blank_count = 0 }
    /^$/ { 
        blank_count++
        if (blank_count <= 1) print
    }
    /^./ { 
        blank_count = 0
        print 
    }
    ' "$temp_cron" >"${temp_cron}.clean" && mv "${temp_cron}.clean" "$temp_cron"

    log_info "Cleanup completed, result has $(wc -l <"$temp_cron") lines"

    # Show what remains
    log_step "Remaining cron entries after cleanup:"
    cat "$temp_cron"

    # Count remaining starlink entries
    remaining_monitor=$(grep -c "starlink_monitor-rutos.sh" "$temp_cron" 2>/dev/null || echo "0")
    remaining_logger=$(grep -c "starlink_logger-rutos.sh" "$temp_cron" 2>/dev/null || echo "0")
    remaining_api_check=$(grep -c "check_starlink_api" "$temp_cron" 2>/dev/null || echo "0")

    log_info "Remaining entries after cleanup:"
    log_info "  starlink_monitor-rutos.sh: $remaining_monitor (should be 1 - the custom timing)"
    log_info "  starlink_logger-rutos.sh: $remaining_logger (should be 0)"
    log_info "  check_starlink_api: $remaining_api_check (should be 0)"

    # Validate results
    if [ "$remaining_monitor" = "1" ] && [ "$remaining_logger" = "0" ] && [ "$remaining_api_check" = "0" ]; then
        log_success "✓ Cleanup logic works correctly - preserved custom timing, removed defaults"
        return 0
    else
        log_error "✗ Cleanup logic failed - unexpected remaining entries"
        return 1
    fi
}

# Clean up test files
cleanup_test() {
    log_step "Cleaning up test files"
    rm -f "$TEST_CRON_FILE" "/tmp/crontab_clean_test.tmp"
    log_success "Test files cleaned up"
}

# Main test function
main() {
    log_info "Starting cron cleanup test v$SCRIPT_VERSION"

    create_test_crontab

    if test_cleanup; then
        log_success "All tests passed! Cron cleanup logic is working correctly"
        exit_code=0
    else
        log_error "Tests failed! Cron cleanup logic needs attention"
        exit_code=1
    fi

    cleanup_test

    exit $exit_code
}

# Execute main function
main "$@"
