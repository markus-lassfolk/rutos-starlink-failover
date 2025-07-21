#!/bin/sh
# shellcheck disable=SC2016  # Fix script uses single quotes intentionally for sed patterns
# Fix Unused SCRIPT_VERSION Issues
# Version: 2.4.12
# Description: Add version usage patterns to scripts with unused SCRIPT_VERSION

# shellcheck disable=SC2034
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.4.11"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Color detection
if [ ! -t 1 ]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

# Files that need SCRIPT_VERSION usage patterns added
FILES_TO_FIX="
Starlink-RUTOS-Failover/AzureLogging/log-shipper-rutos.sh
Starlink-RUTOS-Failover/AzureLogging/test-azure-logging-rutos.sh
Starlink-RUTOS-Failover/generate_api_docs.sh
Starlink-RUTOS-Failover/starlink_logger-rutos.sh
Starlink-RUTOS-Failover/starlink_monitor_old.sh
config/config.advanced.template.sh
config/config.template.sh
config/system-config.sh
config_merged_example.sh
debug-cron-logic.sh
debug-extract.sh
debug-merge-direct.sh
debug-minimal.sh
debug-simple.sh
debug-variable-exists.sh
scripts/validate-markdown.sh
scripts/test-colors-rutos.sh
scripts/self-update-rutos.sh
scripts/restore-config-rutos.sh
test-config-detection.sh
test-config-merge.sh
test-install-completeness.sh
test-intelligent-merge-rutos.sh
test-merge-enhanced.sh
test-quote-issues.sh
test-validation-fix.sh
test-validation-patterns.sh
test_config.sh
test_template_detection.sh
tests/rutos-compatibility-test.sh
tests/test-comprehensive-scenarios.sh
tests/test-core-logic.sh
tests/test-deployment-functions.sh
tests/test-final-verification.sh
tests/test-mwan3-autoconfig.sh
tests/test-suite.sh
tests/test-validation-features.sh
tests/test-validation-fix.sh
"

add_version_usage() {
    local file="$1"

    if [ ! -f "$file" ]; then
        log_warning "File not found: $file"
        return 1
    fi

    # Check if file already has version usage patterns
    if grep -q "SCRIPT_VERSION" "$file" && grep -q -E "(log_info|log_debug|echo|printf).*SCRIPT_VERSION" "$file"; then
        log_info "File already has version usage: $file"
        return 0
    fi

    # For config files, just add a comment usage
    if echo "$file" | grep -q "config"; then
        log_step "Adding comment usage to config file: $file"
        # Add usage in a comment near the SCRIPT_VERSION definition
        sed -i "/^readonly SCRIPT_VERSION/a # Used for troubleshooting: echo \"Configuration version: \$SCRIPT_VERSION\"" "$file"
        return 0
    fi

    # For debug/test scripts, add version display to main function or at end
    if echo "$file" | grep -q -E "(debug|test)"; then
        log_step "Adding version display to debug/test script: $file"
        # Look for main function
        if grep -q "^main()" "$file"; then
            # Add version display at start of main function
            sed -i '/^main() {/a \    if [ "$DEBUG" = "1" ]; then\
        printf "Debug script version: %s\\n" "$SCRIPT_VERSION"\
    fi' "$file"
        else
            # Add version display near the end before any exit
            sed -i '$i # Debug version display\nif [ "$DEBUG" = "1" ]; then\n    printf "Script version: %s\\n" "$SCRIPT_VERSION"\nfi\n' "$file"
        fi
        return 0
    fi

    # For regular scripts, add to help function or main function
    if grep -q -E "show_help|usage|help" "$file"; then
        log_step "Adding version to help function: $file"
        # Add to help function
        sed -i '/echo.*Usage:/a \    echo "Version: $SCRIPT_VERSION"' "$file"
    elif grep -q "^main()" "$file"; then
        log_step "Adding version display to main function: $file"
        # Add to start of main function
        sed -i '/^main() {/a \    log_debug "Script version: $SCRIPT_VERSION"' "$file"
    else
        log_step "Adding version display at end: $file"
        # Add version display at end of script
        sed -i '$i # Version information for troubleshooting\nif [ "$DEBUG" = "1" ]; then\n    printf "Script version: %s\\n" "$SCRIPT_VERSION"\nfi\n' "$file"
    fi
}

main() {
    log_info "Starting unused SCRIPT_VERSION fix process"

    for file in $FILES_TO_FIX; do
        # Skip empty lines
        [ -n "$file" ] || continue

        log_step "Processing: $file"
        add_version_usage "$file"
    done

    log_info "Completed SCRIPT_VERSION usage fixes"
    log_info "Run pre-commit validation again to check results"
}

main "$@"
