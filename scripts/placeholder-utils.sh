#!/bin/sh

# ==============================================================================
# PLACEHOLDER DETECTION UTILITY
# ==============================================================================
# This utility provides functions to detect and handle placeholder values
# in configuration files, enabling graceful degradation of features.
# ==============================================================================

# Function to check if a value is a placeholder

# Note: This utility is sourced, so only set version if not already set
if [ -z "${SCRIPT_VERSION:-}" ]; then
    # Version information (auto-updated by update-version.sh)
    SCRIPT_VERSION="2.6.0"
    readonly SCRIPT_VERSION
fi

is_placeholder() {
    value="$1"

    # Check for common placeholder patterns
    case "$value" in
        "YOUR_"* | "CHANGE_ME" | "REPLACE_ME" | "TODO" | "FIXME" | "EXAMPLE" | "PLACEHOLDER" | "" | '""' | "''")
            return 0 # Is a placeholder
            ;;
        *)
            return 1 # Not a placeholder
            ;;
    esac
}

# Function to check if Pushover is properly configured
is_pushover_configured() {
    if [ -z "$PUSHOVER_TOKEN" ] || [ -z "$PUSHOVER_USER" ]; then
        return 1 # Not configured
    fi

    if is_placeholder "$PUSHOVER_TOKEN" || is_placeholder "$PUSHOVER_USER"; then
        return 1 # Still has placeholders
    fi

    return 0 # Properly configured
}

# Function to check if Azure logging is properly configured
is_azure_configured() {
    if [ -z "$AZURE_WORKSPACE_ID" ] || [ -z "$AZURE_SHARED_KEY" ]; then
        return 1 # Not configured
    fi

    if is_placeholder "$AZURE_WORKSPACE_ID" || is_placeholder "$AZURE_SHARED_KEY"; then
        return 1 # Still has placeholders
    fi

    return 0 # Properly configured
}

# Function to check if RUTOS API is properly configured
is_rutos_configured() {
    if [ -z "$RUTOS_USERNAME" ] || [ -z "$RUTOS_PASSWORD" ]; then
        return 1 # Not configured
    fi

    if is_placeholder "$RUTOS_USERNAME" || is_placeholder "$RUTOS_PASSWORD"; then
        return 1 # Still has placeholders
    fi

    return 0 # Properly configured
}

# Function to check if GPS is properly configured
is_gps_configured() {
    if [ -z "$GPS_DEVICE" ]; then
        return 1 # Not configured
    fi

    if is_placeholder "$GPS_DEVICE"; then
        return 1 # Still has placeholders
    fi

    # Check if GPS device actually exists
    if [ ! -e "$GPS_DEVICE" ]; then
        return 1 # Device doesn't exist
    fi

    return 0 # Properly configured
}

# Function to get a safe notification message about disabled features
get_disabled_feature_message() {
    feature="$1"
    reason="$2"

    case "$feature" in
        "pushover")
            echo "Pushover notifications disabled: $reason"
            ;;
        "azure")
            echo "Azure logging disabled: $reason"
            ;;
        "rutos")
            echo "RUTOS API disabled: $reason"
            ;;
        "gps")
            echo "GPS tracking disabled: $reason"
            ;;
        *)
            echo "Feature '$feature' disabled: $reason"
            ;;
    esac
}

# Function to safely send notification (only if Pushover is configured)
safe_notify() {
    title="$1"
    message="$2"
    priority="${3:-0}"

    # Log the notification attempt for troubleshooting
    logger -t "SafeNotify" -p daemon.info "PUSHOVER: Notification requested - Title: '$title', Priority: $priority"
    
    if is_pushover_configured; then
        logger -t "SafeNotify" -p daemon.info "PUSHOVER: Configuration valid, attempting to send notification"
        
        # Send notification using existing notification function
        if command -v send_notification >/dev/null 2>&1; then
            logger -t "SafeNotify" -p daemon.info "PUSHOVER: Calling send_notification function"
            send_notification "$title" "$message" "$priority"
            notify_result=$?
            
            if [ $notify_result -eq 0 ]; then
                logger -t "SafeNotify" -p daemon.info "PUSHOVER: Notification sent successfully"
            else
                logger -t "SafeNotify" -p daemon.warn "PUSHOVER: send_notification failed with exit code $notify_result"
            fi
            
            return $notify_result
        else
            logger -t "SafeNotify" -p daemon.warn "PUSHOVER: send_notification function not available"
            # Version information for troubleshooting
            if [ "${DEBUG:-0}" = "1" ]; then
                log_debug "Script: placeholder-utils.sh v$SCRIPT_VERSION"
            fi
            echo "INFO: Would send notification: $title - $message"
            return 1
        fi
    else
        logger -t "SafeNotify" -p daemon.info "PUSHOVER: Configuration not valid, skipping notification"
        echo "INFO: Notification skipped (Pushover not configured): $title - $message"
        return 1
    fi
}

# Function to safely log to Azure (only if Azure is configured)
safe_azure_log() {
    log_data="$1"

    if is_azure_configured; then
        # Send to Azure using existing Azure logging function
        if command -v send_azure_log >/dev/null 2>&1; then
            send_azure_log "$log_data"
        else
            echo "INFO: Would send to Azure: $log_data"
        fi
    else
        echo "INFO: Azure logging skipped (Azure not configured): $log_data"
    fi
}

# Function to safely get GPS data (only if GPS is configured)
safe_get_gps() {
    if is_gps_configured; then
        # Get GPS data using existing GPS function
        if command -v get_gps_data >/dev/null 2>&1; then
            get_gps_data
        else
            echo "INFO: Would get GPS data from $GPS_DEVICE"
        fi
    else
        echo "INFO: GPS data skipped (GPS not configured)"
        return 1
    fi
}

# Note: Functions are available when this script is sourced with . or source
# export -f is not supported in POSIX sh, so functions are available in the calling script's context
