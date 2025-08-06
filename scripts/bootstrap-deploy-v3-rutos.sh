#!/bin/sh
# VALIDATION_SKIP_LIBRARY_CHECK: Bootstrap script downloads library itself
# VALIDATION_SKIP_RUTOS_INIT: Bootstrap script doesn't use library initially
# VALIDATION_SKIP_PRINTF: Bootstrap logging (full library unavailable during bootstrap)
# ==============================================================================
# RUTOS Starlink Failover - Bootstrap Deployment Script for v3.0
#
# SPECIAL BOOTSTRAP SCRIPT - LIBRARY EXEMPT
# This script cannot use the RUTOS library because it downloads the library itself.
# It provides its own minimal logging that will be replaced by full RUTOS library
# logging once the library is downloaded and the main deployment script is executed.
#
# This is a lightweight bootstrap script that:
# 1. Performs automatic system cleanup (enhanced-cleanup-rutos.sh --auto)
# 2. Downloads the RUTOS library system to a temporary location
# 3. Downloads the main deploy-starlink-solution-v3-rutos.sh script
# 4. Executes deploy-starlink-solution-v3-rutos.sh with full library support
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/bootstrap-deploy-v3-rutos.sh | sh
#
# With debug mode:
#   curl -fsSL https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/bootstrap-deploy-v3-rutos.sh | DEBUG=1 RUTOS_TEST_MODE=1 sh
# ==============================================================================

set -e

# Version information (auto-updated by update-version.sh)
readonly SCRIPT_VERSION="3.0.0"
# Configuration
GITHUB_REPO="${GITHUB_REPO:-markus-lassfolk/rutos-starlink-failover}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"

# Logging setup (minimal bootstrap-only logging - will be replaced by full RUTOS library)
DRY_RUN="${DRY_RUN:-0}"
DEBUG="${DEBUG:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Store original values for handoff to main deployment script
ORIGINAL_DRY_RUN="$DRY_RUN"
ORIGINAL_DEBUG="$DEBUG"
ORIGINAL_RUTOS_TEST_MODE="$RUTOS_TEST_MODE"

# === BOOTSTRAP LOG FILE SETUP ===
# Set up installation log file location
INSTALL_LOG_DIR="/tmp"
# Try to find a better persistent location if available
for log_dir in "/usr/local/starlink/logs" "/opt/starlink/logs" "/var/log"; do
    if [ -d "$log_dir" ] && [ -w "$log_dir" ]; then
        INSTALL_LOG_DIR="$log_dir"
        break
    fi
done

# Create installation log with unique timestamp
INSTALL_LOG_FILE="$INSTALL_LOG_DIR/starlink-bootstrap-install-$(date +%Y%m%d_%H%M%S).log"
MAIN_INSTALL_LOG_FILE="$INSTALL_LOG_DIR/starlink-deployment-install-$(date +%Y%m%d_%H%M%S).log"

# Create log directory if it doesn't exist
mkdir -p "$INSTALL_LOG_DIR" 2>/dev/null || true

# Export log file path for main deployment script
export INSTALL_LOG_FILE="$MAIN_INSTALL_LOG_FILE"

# VALIDATION_SKIP_LIBRARY_CHECK: Bootstrap logging functions (replaced by full library after download)
log_info() { # VALIDATION_SKIP_LIBRARY_CHECK: Bootstrap-only logging
    msg="[INFO] [$(date '+%Y-%m-%d %H:%M:%S')] $1"
    printf "%s\n" "$msg" >&2 # VALIDATION_SKIP_PRINTF: Bootstrap logging (library unavailable)
    printf "%s\n" "$msg" >>"$INSTALL_LOG_FILE" 2>/dev/null || true
}

log_debug() { # VALIDATION_SKIP_LIBRARY_CHECK: Bootstrap-only logging
    if [ "$DEBUG" = "1" ]; then
        msg="[DEBUG] [$(date '+%Y-%m-%d %H:%M:%S')] $1"
        printf "%s\n" "$msg" >&2
        printf "%s\n" "$msg" >>"$INSTALL_LOG_FILE" 2>/dev/null || true
    fi
}

log_error() { # VALIDATION_SKIP_LIBRARY_CHECK: Bootstrap-only logging
    msg="[ERROR] [$(date '+%Y-%m-%d %H:%M:%S')] $1"
    printf "%s\n" "$msg" >&2
    printf "%s\n" "$msg" >>"$INSTALL_LOG_FILE" 2>/dev/null || true
}

log_trace() { # VALIDATION_SKIP_LIBRARY_CHECK: Bootstrap-only logging
    if [ "$RUTOS_TEST_MODE" = "1" ]; then
        msg="[TRACE] [$(date '+%Y-%m-%d %H:%M:%S')] $1"
        printf "%s\n" "$msg" >&2
        printf "%s\n" "$msg" >>"$INSTALL_LOG_FILE" 2>/dev/null || true
    fi
}

# Generate unique session ID for this bootstrap session
SESSION_ID="bootstrap_deploy_v3_$$_$(date +%s)"

# Create temporary directory for bootstrap files
create_bootstrap_temp_dir() {
    # Try different locations with fallback
    for temp_base in /tmp /var/tmp /root/tmp; do
        if [ -d "$temp_base" ] && [ -w "$temp_base" ]; then
            BOOTSTRAP_TEMP_DIR="$temp_base/rutos-bootstrap-deploy-v3-$SESSION_ID"

            if mkdir -p "$BOOTSTRAP_TEMP_DIR" 2>/dev/null; then
                log_debug "Created bootstrap temp directory: $BOOTSTRAP_TEMP_DIR"
                return 0
            fi
        fi
    done

    # Fallback to current directory
    BOOTSTRAP_TEMP_DIR="./rutos-bootstrap-deploy-v3-$SESSION_ID"
    if mkdir -p "$BOOTSTRAP_TEMP_DIR" 2>/dev/null; then
        log_debug "Created bootstrap temp directory in current dir: $BOOTSTRAP_TEMP_DIR"
        return 0
    fi

    log_error "Failed to create temporary directory for bootstrap"
    return 1
}

# Download a file with error handling
download_file() {
    url="$1"
    output_file="$2"
    description="$3"

    log_trace "Downloading $description from: $url"
    log_trace "Target file: $output_file"

    # Try curl first (VALIDATION_SKIP_SAFE_EXECUTE: Bootstrap phase before library available)
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$output_file"; then
            log_debug "Downloaded $description successfully (curl)"
            return 0
        else
            curl_exit_code=$?
            log_debug "curl failed with exit code $curl_exit_code for $description"
        fi
    fi

    # Fallback to wget (VALIDATION_SKIP_SAFE_EXECUTE: Bootstrap phase before library available)
    if command -v wget >/dev/null 2>&1; then
        if wget -q -O "$output_file" "$url"; then
            log_debug "Downloaded $description successfully (wget)"
            return 0
        else
            wget_exit_code=$?
            log_debug "wget failed with exit code $wget_exit_code for $description"
        fi
    fi

    log_error "Failed to download $description from $url"
    return 1
}

# Download RUTOS library system
download_library_system() {
    log_info "Downloading RUTOS library system..."

    # Create lib subdirectory
    lib_dir="$BOOTSTRAP_TEMP_DIR/lib"
    mkdir -p "$lib_dir"

    # Download all library components including compatibility module
    library_files="rutos-lib.sh rutos-colors.sh rutos-logging.sh rutos-common.sh rutos-compatibility.sh"

    for file in $library_files; do
        url="$BASE_URL/scripts/lib/$file"
        output_file="$lib_dir/$file"

        if ! download_file "$url" "$output_file" "$file"; then
            log_error "Failed to download library component: $file"
            return 1
        fi

        log_trace "Downloaded library file: $file ($(wc -c <"$output_file" 2>/dev/null || echo 'unknown') bytes)"
    done

    log_debug "Library system downloaded successfully to: $lib_dir"
    return 0
}

# Download main deployment script
download_deployment_script() {
    log_info "Downloading main deployment script..."

    url="$BASE_URL/deploy-starlink-solution-v3-rutos.sh"
    output_file="$BOOTSTRAP_TEMP_DIR/deploy-starlink-solution-v3-rutos.sh"

    if ! download_file "$url" "$output_file" "deploy-starlink-solution-v3-rutos.sh"; then
        log_error "Failed to download main deployment script"
        return 1
    fi

    # Make executable
    chmod +x "$output_file" 2>/dev/null || true

    log_debug "Deployment script downloaded: $output_file ($(wc -c <"$output_file" 2>/dev/null || echo 'unknown') bytes)"
    return 0
}

# Execute deployment script with library support
execute_with_library() {
    log_info "Executing deployment with full RUTOS library support..."

    deployment_script="$BOOTSTRAP_TEMP_DIR/deploy-starlink-solution-v3-rutos.sh"
    lib_dir="$BOOTSTRAP_TEMP_DIR/lib"

    # Verify files exist
    if [ ! -f "$deployment_script" ]; then
        log_error "Deployment script not found: $deployment_script"
        return 1
    fi

    if [ ! -f "$lib_dir/rutos-lib.sh" ]; then
        log_error "Library system not found: $lib_dir/rutos-lib.sh"
        return 1
    fi

    log_trace "Changing to bootstrap directory: $BOOTSTRAP_TEMP_DIR"
    cd "$BOOTSTRAP_TEMP_DIR"

    # Export environment variables for the deployment script
    export DRY_RUN DEBUG RUTOS_TEST_MODE

    # Smart ALLOW_TEST_EXECUTION logic:
    # - If DRY_RUN=1: Allow test execution (safe mode)
    # - If DRY_RUN=0 and RUTOS_TEST_MODE=1: Allow test execution (real execution with enhanced logging)
    # - If DRY_RUN=0 and RUTOS_TEST_MODE=0: Don't need test execution (normal mode)
    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        ALLOW_TEST_EXECUTION=1
    else
        ALLOW_TEST_EXECUTION="${ALLOW_TEST_EXECUTION:-0}"
    fi
    export ALLOW_TEST_EXECUTION

    export USE_LIBRARY=1           # Signal to deployment script that library is available
    export LIBRARY_PATH="$lib_dir" # Tell deployment script where to find library

    log_trace "Environment for deployment script:"
    log_trace "  DRY_RUN=$DRY_RUN"
    log_trace "  DEBUG=$DEBUG"
    log_trace "  RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
    log_trace "  ALLOW_TEST_EXECUTION=$ALLOW_TEST_EXECUTION (auto-set: DRY_RUN=$DRY_RUN or RUTOS_TEST_MODE=$RUTOS_TEST_MODE)"
    log_trace "  USE_LIBRARY=$USE_LIBRARY"
    log_trace "  LIBRARY_PATH=$LIBRARY_PATH"

    # Execute the deployment script
    log_info "Starting deployment script with library support..."

    # Make script executable and run directly to preserve environment
    chmod +x "$deployment_script"

    # Capture both output and error code for better debugging
    # Use explicit variable passing to ensure environment is preserved
    log_info "Executing deployment with log file: $MAIN_INSTALL_LOG_FILE"
    
    # BusyBox compatible logging - use simple redirection
    printf "⏳ Starting deployment with logging enabled...\n"
    printf "📝 All output will be logged to: %s\n" "$MAIN_INSTALL_LOG_FILE"
    
    # Execute deployment and capture output
    if DRY_RUN="$DRY_RUN" DEBUG="$DEBUG" RUTOS_TEST_MODE="$RUTOS_TEST_MODE" \
        ALLOW_TEST_EXECUTION="$ALLOW_TEST_EXECUTION" USE_LIBRARY="$USE_LIBRARY" \
        LIBRARY_PATH="$LIBRARY_PATH" INSTALL_LOG_FILE="$MAIN_INSTALL_LOG_FILE" \
        "$deployment_script" > "$MAIN_INSTALL_LOG_FILE" 2>&1; then
        exit_code=0
        printf "\n✅ Deployment completed successfully!\n"
    else
        exit_code=$?
        printf "\n❌ Deployment failed with exit code: %d\n" $exit_code
    fi
    
    # Always show the final output
    printf "\n📋 DEPLOYMENT OUTPUT:\n"
    printf "=====================================\n"
    # Show last part of log for immediate feedback
    if command -v tail >/dev/null 2>&1; then
        printf "[... showing last 50 lines of output ...]\n"
        tail -n 50 "$MAIN_INSTALL_LOG_FILE" 2>/dev/null || cat "$MAIN_INSTALL_LOG_FILE"
    else
        cat "$MAIN_INSTALL_LOG_FILE" 2>/dev/null || printf "Error reading log file\n"
    fi
    printf "=====================================\n"

    if [ $exit_code -eq 0 ]; then
        log_info "Deployment completed successfully!"
        log_info "Full deployment log available at: $MAIN_INSTALL_LOG_FILE"
        return 0
    else
        log_error "Deployment script failed with exit code: $exit_code"
        log_error "Check the deployment script output above for details"
        log_error "Full deployment log available at: $MAIN_INSTALL_LOG_FILE"
        return $exit_code
    fi
}

# Cleanup function
cleanup_bootstrap() {
    if [ -n "$BOOTSTRAP_TEMP_DIR" ] && [ -d "$BOOTSTRAP_TEMP_DIR" ]; then
        log_debug "Cleaning up bootstrap temporary directory: $BOOTSTRAP_TEMP_DIR"
        # VALIDATION_SKIP_DRY_RUN: Bootstrap cleanup always runs (temp files only)
        rm -rf "$BOOTSTRAP_TEMP_DIR" 2>/dev/null || true
    fi
}

# Trap cleanup on exit
trap cleanup_bootstrap EXIT INT TERM

# Main bootstrap process
main() {
    log_info "Starting RUTOS Starlink Failover Bootstrap Deployment v$SCRIPT_VERSION"
    log_info "Bootstrap log file: $INSTALL_LOG_FILE"
    log_info "Main deployment will log to: $MAIN_INSTALL_LOG_FILE"

    # Show debug environment information
    if [ "$DEBUG" = "1" ]; then
        log_debug "Bootstrap deployment environment:"
        log_debug "  Script version: $SCRIPT_VERSION"
        log_debug "  GitHub repo: $GITHUB_REPO"
        log_debug "  GitHub branch: $GITHUB_BRANCH"
        log_debug "  Base URL: $BASE_URL"
        log_debug "  Session ID: $SESSION_ID"
        log_debug "  Working directory: $(pwd)"
        log_debug "  User: $(id -un 2>/dev/null || echo 'unknown')"
        log_debug "  System: $(uname -a 2>/dev/null || echo 'unknown')"
        log_debug "  LOGGING MODES:"
        log_debug "    DRY_RUN: $DRY_RUN (original: $ORIGINAL_DRY_RUN)"
        log_debug "    DEBUG: $DEBUG (original: $ORIGINAL_DEBUG)"
        log_debug "    RUTOS_TEST_MODE: $RUTOS_TEST_MODE (original: $ORIGINAL_RUTOS_TEST_MODE)"
    fi

    # Step 1: Create temporary directory
    if ! create_bootstrap_temp_dir; then
        log_error "Failed to create bootstrap temporary directory"
        exit 1
    fi

    # Step 2: Download library system
    if ! download_library_system; then
        log_error "Failed to download RUTOS library system"
        exit 1
    fi

    # Step 3: Download deployment script
    if ! download_deployment_script; then
        log_error "Failed to download deployment script"
        exit 1
    fi

    # Step 4: Execute deployment with library support
    if ! execute_with_library; then
        log_error "Deployment failed"
        exit 1
    fi

    log_info "Bootstrap deployment completed successfully!"
    log_info ""
    log_info "📋 LOG FILE LOCATIONS:"
    log_info "   Bootstrap Log: $INSTALL_LOG_FILE"
    log_info "   Deployment Log: $MAIN_INSTALL_LOG_FILE"
    log_info ""
    log_info "🔍 QUICK LOG ANALYSIS COMMANDS:"
    log_info "   View errors: grep -i error '$MAIN_INSTALL_LOG_FILE'"
    log_info "   View warnings: grep -i warning '$MAIN_INSTALL_LOG_FILE'"
    log_info "   View full log: less '$MAIN_INSTALL_LOG_FILE'"
    log_info "   Use log analyzer: ./scripts/analyze-installation-log-rutos.sh '$MAIN_INSTALL_LOG_FILE'"
}

# Execute main function
main "$@"

