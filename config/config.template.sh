#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC2154

# Template version (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
# ==============================================================================
# STARLINK MONITOR BASIC CONFIGURATION
# ==============================================================================
# This is the basic configuration for Starlink monitoring.
# Only essential settings are included.
#
# For advanced features (Azure logging, GPS tracking, etc.), run:
#   /root/starlink-monitor/scripts/upgrade-to-advanced.sh
#
# Template version: 1.0.0
# Compatible with install.sh: 1.0.0
# ==============================================================================

# --- Network Configuration ---

# Starlink gRPC endpoint IP and port
# Default: 192.168.100.1:9200 (standard Starlink configuration)

# Version information (auto-updated by update-version.sh)
readonly SCRIPT_VERSION="2.4.12"
# shellcheck disable=SC2034  # Template version variables used by scripts that source this
readonly SCRIPT_VERSION
# Used for troubleshooting: echo "Configuration version: $SCRIPT_VERSION"
export STARLINK_IP="192.168.100.1:9200"

# MWAN3 interface name for Starlink connection
# Check your MWAN3 config: uci show mwan3 | grep interface
export MWAN_IFACE="wan"

# MWAN3 member name for Starlink connection
# Check your MWAN3 config: uci show mwan3 | grep member
export MWAN_MEMBER="member1"

# --- Notification Settings ---

# Pushover API credentials for notifications
# Get your token from: https://pushover.net/apps/build
# Get your user key from: https://pushover.net/
# Leave as placeholders to disable notifications
export PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
export PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

# Notification triggers (1=enabled, 0=disabled)
export NOTIFY_ON_CRITICAL="1"  # Critical errors (recommended: 1)
export NOTIFY_ON_HARD_FAIL="1" # Complete failures (recommended: 1)
export NOTIFY_ON_RECOVERY="1"  # System recovery (recommended: 1)
export NOTIFY_ON_SOFT_FAIL="0" # Degraded performance (0=disabled for basic setup)
export NOTIFY_ON_INFO="0"      # Status updates (0=disabled for basic setup)

# --- Basic Failover Thresholds ---

# Packet loss threshold (percentage as decimal: 0.05 = 5%)
export PACKET_LOSS_THRESHOLD="0.05"

# Obstruction threshold (percentage as decimal: 0.001 = 0.1%)
export OBSTRUCTION_THRESHOLD="0.001"

# Latency threshold in milliseconds
export LATENCY_THRESHOLD_MS="150"

# --- System Settings ---

# Check interval in seconds (how often to test Starlink)
export CHECK_INTERVAL="30"

# API timeout in seconds
export API_TIMEOUT="10"

# Directory for log files (persistent across reboots)
export LOG_DIR="/etc/starlink-logs"

# Directory for runtime state files
export STATE_DIR="/tmp/run"

# Log retention in days (how long to keep log files)
export LOG_RETENTION_DAYS="7"

# Syslog tag for log messages (shown in system logs)
export LOG_TAG="StarlinkMonitor"

# --- System Maintenance Configuration ---

# Enable Pushover notifications for critical maintenance issues
export MAINTENANCE_PUSHOVER_ENABLED="true" # Uses PUSHOVER_TOKEN/PUSHOVER_USER if not overridden

# Optional: Override Pushover credentials specifically for maintenance (leave empty to use main settings)
export MAINTENANCE_PUSHOVER_TOKEN="" # Leave empty to use PUSHOVER_TOKEN
export MAINTENANCE_PUSHOVER_USER=""  # Leave empty to use PUSHOVER_USER

# =============================================================================
# ENHANCED MAINTENANCE NOTIFICATION CONTROL
# =============================================================================

# Notification levels - control what gets sent via Pushover
export MAINTENANCE_NOTIFY_ON_FIXES="true"    # Send notification for each successful fix (recommended)
export MAINTENANCE_NOTIFY_ON_FAILURES="true" # Send notification for each failed fix attempt (recommended)
export MAINTENANCE_NOTIFY_ON_CRITICAL="true" # Send notification for critical issues (always recommended)
export MAINTENANCE_NOTIFY_ON_FOUND="false"   # Send notification for issues found but not fixed (can be noisy)

# Notification thresholds and timing
export MAINTENANCE_CRITICAL_THRESHOLD="1"         # Send critical notification if 1+ critical issues (lowered for better monitoring)
export MAINTENANCE_NOTIFICATION_COOLDOWN="1800"   # Cooldown between notifications (30 minutes to reduce spam but stay informed)
export MAINTENANCE_MAX_NOTIFICATIONS_PER_RUN="10" # Maximum individual notifications per maintenance run

# Notification priorities (Pushover priority levels: -2=lowest, -1=low, 0=normal, 1=high, 2=emergency)
export MAINTENANCE_PRIORITY_FIXED="0"    # Normal priority for successful fixes
export MAINTENANCE_PRIORITY_FAILED="1"   # High priority for failed fixes
export MAINTENANCE_PRIORITY_CRITICAL="2" # Emergency priority for critical issues
export MAINTENANCE_PRIORITY_FOUND="0"    # Normal priority for found issues

# =============================================================================
# SYSTEM MAINTENANCE BEHAVIOR CONTROL
# =============================================================================

# Control automatic fix behavior
export MAINTENANCE_AUTO_FIX_ENABLED="true" # Allow maintenance script to fix issues automatically (true/false)

# Control automatic reboot behavior
export MAINTENANCE_AUTO_REBOOT_ENABLED="false" # Allow maintenance script to reboot system for critical issues (true/false)
export MAINTENANCE_REBOOT_THRESHOLD="5"        # Number of consecutive critical maintenance runs before considering reboot

# Service restart control
export MAINTENANCE_SERVICE_RESTART_ENABLED="true" # Allow service restarts during maintenance (true/false)

# Database fix control
export MAINTENANCE_DATABASE_FIX_ENABLED="true" # Allow database reset/recreation during maintenance (true/false)

# Maintenance mode override (empty = use default from command line)
export MAINTENANCE_MODE_OVERRIDE="" # Force specific mode: auto, check, fix, report (empty = use default)

# Safety controls
export MAINTENANCE_MAX_FIXES_PER_RUN="10"     # Maximum number of fixes to attempt in single run
export MAINTENANCE_COOLDOWN_AFTER_FIXES="300" # Cooldown period (seconds) after performing fixes

# --- Auto-Update Configuration ---

# Enable automatic updates via crontab (true/false)
export AUTO_UPDATE_ENABLED="false"

# Update policies for different version types
# Format: Never|<number><unit> where unit is: Minutes|Hours|Days|Weeks|Months
# Examples: "Never", "30Minutes", "2Hours", "5Days", "2Weeks", "1Month"

# Patch version updates (2.1.3 -> 2.1.4) - Usually safe, quick fixes
export UPDATE_PATCH_DELAY="1Hours"

# Minor version updates (2.1.x -> 2.2.0) - New features, moderate risk
export UPDATE_MINOR_DELAY="3Days"

# Major version updates (2.x.x -> 3.0.0) - Breaking changes, highest risk
export UPDATE_MAJOR_DELAY="2Weeks"

# Auto-update schedule (cron format)
# Default: Every 4 hours at minute 15: "15 */4 * * *"
# Examples:
#   "0 2 * * *"     - Daily at 2 AM
#   "15 */6 * * *"  - Every 6 hours at minute 15
#   "0 3 * * 1"     - Weekly on Monday at 3 AM
export AUTO_UPDATE_SCHEDULE="15 */4 * * *"

# Update behavior options
export AUTO_UPDATE_BACKUP_ENABLED="true"      # Create backup before update
export AUTO_UPDATE_ROLLBACK_ON_FAILURE="true" # Auto-rollback if update fails
export AUTO_UPDATE_NOTIFY_ON_SUCCESS="true"   # Send notification on successful update
export AUTO_UPDATE_NOTIFY_ON_FAILURE="true"   # Send notification on failed update

# --- Binary Paths (set by install script) ---

export GRPCURL_CMD="/usr/local/starlink-monitor/grpcurl" # gRPC client for Starlink API
export JQ_CMD="/usr/local/starlink-monitor/jq"           # JSON processor for parsing API responses
