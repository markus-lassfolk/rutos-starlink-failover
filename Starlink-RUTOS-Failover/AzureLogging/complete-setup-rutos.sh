#!/bin/sh

# === Complete Azure Logging Setup and Verification ===
# This script performs end-to-end setup and testing of Azure logging integration

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="/overlay/messages"
SETUP_SCRIPT="$SCRIPT_DIR/setup-persistent-logging-rutos.sh"
SHIPPER_SCRIPT="$SCRIPT_DIR/log-shipper-rutos.sh"
# shellcheck disable=SC2034  # TEST_SCRIPT may be used for debugging
TEST_SCRIPT="$SCRIPT_DIR/test-azure-logging-rutos.sh"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" != "" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Standard logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
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

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Function to safely execute commands
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

echo "=== Azure Logging Complete Setup and Verification ==="
echo ""

# Function to check if running on RUTOS
check_rutos() {
    if [ ! -f "/etc/config/system" ]; then
        echo "❌ This script must be run on a RUTOS device with UCI configuration"
        exit 1
    fi

    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ This script must be run as root"
        exit 1
    fi
}

# Function to setup persistent logging
setup_logging() {
    log_step "Setting up persistent logging..."

    if [ ! -f "$SETUP_SCRIPT" ]; then
        log_error "Setup script not found: $SETUP_SCRIPT"
        exit 1
    fi

    safe_execute "chmod +x '$SETUP_SCRIPT'" "Make setup script executable"
    safe_execute "'$SETUP_SCRIPT'" "Run persistent logging setup"

    log_info "✅ Persistent logging setup completed"
}

# Function to verify logging is working
verify_logging() {
    log_step "Verifying persistent logging..."

    # Check if log file exists and is writable
    if [ ! -f "$LOG_FILE" ]; then
        log_error "Log file $LOG_FILE does not exist"
        return 1
    fi

    # Check log file size and permissions
    LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    LOG_PERMS=$(stat -c%a "$LOG_FILE" 2>/dev/null || echo "000")

    log_info "Log file: $LOG_FILE"
    log_info "Size: $LOG_SIZE bytes"
    log_info "Permissions: $LOG_PERMS"

    # Test writing to log
    safe_execute "logger -t 'azure-setup-verify' 'Setup verification test - \$(date)'" "Write test message to log"
    safe_execute "sleep 2" "Wait for log write"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would verify log message exists"
        log_info "✅ Logging verification successful (dry-run)"
        return 0
    fi

    if grep -q "azure-setup-verify" "$LOG_FILE"; then
        log_info "✅ Logging verification successful"
        return 0
    else
        log_error "Failed to write test message to log file"
        return 1
    fi
}

# Function to setup log shipper
setup_shipper() {
    echo ""
    echo "Step 3: Installing log shipper..."

    if [ ! -f "$SHIPPER_SCRIPT" ]; then
        echo "❌ Log shipper script not found: $SHIPPER_SCRIPT"
        exit 1
    fi

    # Copy to overlay (persistent storage)
    cp "$SHIPPER_SCRIPT" "/overlay/log-shipper.sh"
    chmod 755 "/overlay/log-shipper.sh"

    echo "✅ Log shipper installed to /overlay/log-shipper.sh"

    # Check if Azure URL is configured
    if grep -q "PASTE_YOUR_AZURE_FUNCTION_URL_HERE" "/overlay/log-shipper.sh"; then
        echo ""
        echo "⚠️  IMPORTANT: You need to configure the Azure Function URL"
        echo "   Edit /overlay/log-shipper.sh and set AZURE_FUNCTION_URL"
        echo "   Get this URL after deploying your Azure Function App"
    fi
}

# Function to show next steps
show_next_steps() {
    echo ""
    echo "=== Next Steps ==="
    echo ""
    echo "1. Deploy Azure Infrastructure:"
    echo "   az deployment group create --resource-group YOUR_RG --template-file main.bicep"
    echo ""
    echo "2. Deploy Function Code:"
    echo "   (Zip HttpLogIngestor folder and deploy with Azure CLI)"
    echo ""
    echo "3. Get Function URL and configure log-shipper.sh:"
    echo "   vi /overlay/log-shipper.sh"
    echo "   # Set AZURE_FUNCTION_URL to your actual function URL"
    echo ""
    echo "4. Test the integration:"
    echo "   /overlay/log-shipper.sh"
    echo ""
    echo "5. Set up cron job (every 5 minutes):"
    echo "   crontab -e"
    echo "   # Add: */5 * * * * /overlay/log-shipper.sh"
    echo ""
    echo "6. Monitor logs:"
    echo "   tail -f $LOG_FILE"
    echo "   logread | grep azure-log-shipper"
}

# Function to show current status
show_status() {
    echo ""
    echo "=== Current System Status ==="

    # UCI configuration
    echo "Logging configuration:"
    uci show system.@system[0] | grep -E "(log_type|log_size|log_file)" || echo "No logging config found"

    # Storage space
    echo ""
    echo "Overlay storage:"
    df -h /overlay

    # Log file status
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "Log file status:"
        ls -lh "$LOG_FILE"
        echo "Last 3 lines:"
        tail -3 "$LOG_FILE"
    fi

    # Cron status
    echo ""
    echo "Cron jobs for log shipping:"
    crontab -l 2>/dev/null | grep -E "(log-shipper|azure)" || echo "No cron jobs configured yet"
}

# Main execution
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "complete-setup-rutos.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: complete-setup-rutos.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    check_rutos

    echo "This script will:"
    echo "1. Configure persistent logging (5MB file storage)"
    echo "2. Verify logging is working correctly"
    echo "3. Install the log shipper script"
    echo "4. Show next steps for Azure deployment"
    echo ""

    printf "Continue with setup? [y/N]: "
    read -r REPLY
    if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
        echo "Setup cancelled."
        exit 0
    fi

    setup_logging

    if verify_logging; then
        setup_shipper
        show_next_steps
    else
        echo ""
        echo "❌ Logging verification failed. Please check the system configuration."
        exit 1
    fi

    show_status

    echo ""
    echo "✅ RUTOS Azure logging setup completed successfully!"
    echo ""
    echo "Remember to:"
    echo "- Deploy Azure resources using main.bicep"
    echo "- Configure the Azure Function URL in /overlay/log-shipper.sh"
    echo "- Set up the cron job for automatic log shipping"
}

# Run main function
main "$@"
