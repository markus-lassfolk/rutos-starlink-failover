#!/bin/sh
# ==============================================================================
# Autonomous RUTOS Deployment System
#
# This script runs on a monitoring host and performs autonomous deployment
# and monitoring of RUTOS devices with full error reporting to GitHub.
#
# Features:
# - Automated SSH connection and deployment
# - Comprehensive error logging and parsing
# - Automatic GitHub issue creation for errors
# - Integration with existing PowerShell issue creation scripts
# - Self-healing deployment pipeline
# ==============================================================================

set -e

# Configuration
# Version information (auto-updated by update-version.sh)
readonly SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
# shellcheck disable=SC1091 # Library path is dynamic based on deployment location
. "$(dirname "$0")/../scripts/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "autonomous-deployer-rutos.sh" "$SCRIPT_VERSION"

# === DEBUG AND TESTING VARIABLES ===
# Support DRY_RUN mode for testing
DRY_RUN="${DRY_RUN:-0}"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "autonomous-deployer-rutos.sh" "$SCRIPT_VERSION"

CONFIG_FILE="${CONFIG_FILE:-./autonomous-config.conf}"
LOG_DIR="${LOG_DIR:-./logs}"
ERROR_LOG="$LOG_DIR/autonomous-errors.log"
DEPLOYMENT_LOG="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
else
    echo "❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Required configuration variables
: "${RUTOS_HOSTS:?RUTOS_HOSTS must be defined in config}"
: "${SSH_KEY:?SSH_KEY path must be defined in config}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be defined in config}"
: "${REPO_OWNER:?REPO_OWNER must be defined in config}"
: "${REPO_NAME:?REPO_NAME must be defined in config}"

# Create log directory
mkdir -p "$LOG_DIR"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$DEPLOYMENT_LOG"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$DEPLOYMENT_LOG" "$ERROR_LOG"
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" | tee -a "$DEPLOYMENT_LOG"
    fi
}

# Enhanced error parser for RUTOS logs
parse_error_details() {
    log_content="$1"
    host="$2"

    # Extract structured error information
    errors=$(echo "$log_content" | grep -E "\[ERROR\]|\[CRITICAL\]|failed|error:|ERROR:" | head -10)

    # Parse specific error patterns
    echo "$errors" | while IFS= read -r error_line; do
        if [ -n "$error_line" ]; then
            # Extract timestamp, script name, line number if available
            timestamp=$(echo "$error_line" | grep -oP '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]' || echo "[$(date '+%Y-%m-%d %H:%M:%S')]")
            script_name=$(echo "$error_line" | grep -oP '\w+\.sh|\w+-rutos\.sh' | head -1 || echo "unknown_script")
            error_msg=$(echo "$error_line" | sed 's/.*\[ERROR\]//g' | sed 's/.*ERROR://g' | xargs)

            # Create structured error entry
            cat >>"$ERROR_LOG" <<EOF
==== AUTONOMOUS ERROR ENTRY =====
Timestamp: $timestamp
Host: $host
Script: $script_name
Error: $error_msg
Full Line: $error_line
Deployment Log: $DEPLOYMENT_LOG
=====================================

EOF
        fi
    done
}

# SSH deployment function with comprehensive logging
deploy_to_rutos() {
    host="$1"
    deployment_cmd="${2:-bootstrap-install-rutos.sh}"

    log_info "🚀 Starting autonomous deployment to $host"
    log_info "📋 Deployment command: $deployment_cmd"

    # SSH connection with detailed logging
    ssh_output
    ssh_exit_code=0

    # Construct the full deployment command
    deployment_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/scripts/${deployment_cmd}"
    full_cmd="smart_safe_execute 'curl -fsSL $deployment_url | DEBUG=1 RUTOS_TEST_MODE=1 VERBOSE=1 sh'"

    log_debug "🔗 SSH Command: ssh -i $SSH_KEY -o ConnectTimeout=30 -o StrictHostKeyChecking=no root@$host"
    log_debug "📜 Remote Command: $full_cmd"

    # Execute deployment with comprehensive output capture
    if ssh_output=$(ssh -i "$SSH_KEY" \
        -o ConnectTimeout=30 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "root@$host" \
        "$full_cmd" 2>&1); then
        log_info "✅ Deployment to $host completed successfully"
        ssh_exit_code=0
    else
        ssh_exit_code=$?
        log_error "❌ Deployment to $host failed with exit code: $ssh_exit_code"
    fi

    # Log full output for analysis
    {
        echo "==== DEPLOYMENT OUTPUT FOR \"$host\" ===="
        echo "$ssh_output"
        echo "==== END DEPLOYMENT OUTPUT ===="
    } >>"$DEPLOYMENT_LOG"

    # Parse errors from output
    if [ "$ssh_exit_code" -ne 0 ] || echo "$ssh_output" | grep -qE "\\[ERROR\\]|\\[CRITICAL\\]|failed|error:"; then
        log_error "🔍 Parsing errors from deployment output"
        parse_error_details "$ssh_output" "$host"
        return 1
    fi

    return 0
}

# Verify deployment success
verify_deployment() {
    host="$1"

    log_info "🔍 Verifying deployment on $host"

    # Check if monitoring script exists and is executable
    check_cmd="test -x /usr/local/starlink/bin/starlink_monitor_unified-rutos.sh && echo 'SCRIPT_OK' || echo 'SCRIPT_MISSING'"
    script_check=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 "root@$host" "$check_cmd" 2>/dev/null || echo "SSH_FAILED")

    if [ "$script_check" = "SCRIPT_OK" ]; then
        log_info "✅ Main script verified on $host"
    else
        log_error "❌ Main script verification failed on $host: $script_check"
        return 1
    fi

    # Check daemon status
    daemon_cmd="/etc/init.d/starlink-monitor status && echo 'DAEMON_OK' || echo 'DAEMON_ISSUE'"
    daemon_check=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 "root@$host" "$daemon_cmd" 2>/dev/null || echo "DAEMON_FAILED")

    if echo "$daemon_check" | grep -q "DAEMON_OK"; then
        log_info "✅ Daemon verified on $host"
    else
        log_error "❌ Daemon verification failed on $host: $daemon_check"
        return 1
    fi

    # Check crontab (if using hybrid mode)
    cron_cmd="smart_safe_execute 'crontab -l 2>/dev/null | grep -c starlink || echo 0'"
    cron_count=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 "root@$host" "$cron_cmd" 2>/dev/null || echo "0")

    log_info "📅 Crontab entries for $host: $cron_count"

    return 0
}

# Main deployment orchestrator
main_deployment() {
    total_hosts=0
    successful_hosts=0
    failed_hosts=0

    log_info "🎯 Starting autonomous deployment cycle"
    log_info "📊 Configuration:"
    log_info "   - Hosts: $(echo "$RUTOS_HOSTS" | wc -w)"
    log_info "   - SSH Key: $SSH_KEY"
    log_info "   - Log Directory: $LOG_DIR"
    log_info "   - Error Log: $ERROR_LOG"

    # Deploy to each host
    for host in $RUTOS_HOSTS; do
        total_hosts=$((total_hosts + 1))

        log_info "🎯 Processing host $total_hosts: $host"

        # Choose deployment script based on configuration
        deploy_script="${DEPLOYMENT_SCRIPT:-bootstrap-deploy-v3-rutos.sh}"

        if deploy_to_rutos "$host" "$deploy_script"; then
            if verify_deployment "$host"; then
                successful_hosts=$((successful_hosts + 1))
                log_info "✅ Host $host: Complete success"
            else
                failed_hosts=$((failed_hosts + 1))
                log_error "⚠️ Host $host: Deployment succeeded but verification failed"
            fi
        else
            failed_hosts=$((failed_hosts + 1))
            log_error "❌ Host $host: Deployment failed"
        fi
    done

    # Summary
    log_info "📈 Deployment Summary:"
    log_info "   - Total hosts: $total_hosts"
    log_info "   - Successful: $successful_hosts"
    log_info "   - Failed: $failed_hosts"

    if [ $failed_hosts -gt 0 ]; then
        log_error "⚠️ Some deployments failed - check $ERROR_LOG for details"
        return 1
    else
        log_info "🎉 All deployments successful!"
        return 0
    fi
}

# Execute main deployment
if [ "${0##*/}" = "autonomous-deployer-rutos.sh" ]; then
    main_deployment "$@"
fi
