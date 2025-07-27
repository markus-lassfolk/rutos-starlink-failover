#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC2154

# ==============================================================================
# STARLINK MONITOR UNIFIED CONFIGURATION
# ==============================================================================
# This configuration works with both basic and unified scripts:
# - starlink_monitor_unified-rutos.sh (recommended)
# - starlink_logger_unified-rutos.sh (recommended)
# - Legacy basic scripts (backward compatibility)
#
# UNIFIED SCRIPTS: Enable enhanced features via ENABLE_* flags (see bottom)
# BASIC SCRIPTS: Enhanced features are ignored - maintains original behavior
#
# Template version: 2.7.0
# Compatible with install.sh: 2.7.0+
# ==============================================================================

# Version information (auto-updated by update-version.sh)
# Note: Only set SCRIPT_VERSION if not already set (prevents conflicts when sourced)
if [ -z "${SCRIPT_VERSION:-}" ]; then
    # Script configuration template for Starlink RUTOS Failover
    # Version: 2.5.0
    # Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
    readonly SCRIPT_VERSION
fi
readonly SCRIPT_VERSION
# Used for troubleshooting: echo "Config version: $SCRIPT_VERSION"

# Configuration metadata (for troubleshooting and updates)
CONFIG_VERSION="2.7.1"

# --- Network Configuration ---

# Starlink gRPC endpoint IP and port (separate variables for flexibility)
# Default: IP=192.168.100.1, PORT=9200 (standard Starlink configuration)
export STARLINK_IP="192.168.100.1"
export STARLINK_PORT="9200"

# MWAN3 interface name for Starlink connection
# Check your MWAN3 config: uci show mwan3 | grep interface
export MWAN_IFACE="wan"

# MWAN3 member name for Starlink connection
# Check your MWAN3 config: uci show mwan3 | grep member
export MWAN_MEMBER="member1"

# MWAN3 metric values for failover control
# METRIC_GOOD: Normal routing priority (lower numbers = higher priority)
# METRIC_BAD: Failover routing priority (higher numbers = lower priority)
export METRIC_GOOD="1"
export METRIC_BAD="20"

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
# These settings control when the system triggers failover to cellular backup

# Packet loss threshold (percentage as decimal: 0.05 = 5%)
# How it works: If packet loss exceeds this percentage, triggers failover
# Lower values = more sensitive failover, Higher values = more tolerant of poor conditions
# Recommended: 0.05 (5%) for balanced reliability vs stability
export PACKET_LOSS_THRESHOLD="0.05"

# Obstruction threshold (percentage as decimal: 0.001 = 0.1%)
# How it works: Starlink reports obstructions (trees, buildings) blocking satellite view
# Even small obstructions can cause intermittent connectivity issues
# Recommended: 0.001 (0.1%) - very sensitive since obstructions indicate positioning issues
export OBSTRUCTION_THRESHOLD="0.001"

# Latency threshold in milliseconds (ping response time)
# How it works: High latency indicates poor satellite connection or network congestion
# Affects: Real-time applications (VoIP, gaming, video calls)
# Typical Starlink: 20-40ms good, 50-80ms acceptable, 100ms+ problematic
# Recommended: 150ms for general use, 100ms for latency-sensitive applications
export LATENCY_THRESHOLD_MS="150"

# Jitter threshold in milliseconds (variation in latency)
# What is jitter: The variation in ping times - indicates network stability
# Low jitter (0-10ms) = stable connection, High jitter (20ms+) = unstable connection
# Affects: Video streaming, VoIP quality, real-time applications
# Recommended: 20ms for general use, 10ms for real-time applications
export JITTER_THRESHOLD="20"

# Stability checks required before failback (consecutive good checks needed)
# How it works: After Starlink recovers, wait for X consecutive good checks before switching back
# Prevents: Rapid back-and-forth switching when connection is marginal
# Higher values = more stable failback (but slower recovery)
# Lower values = faster failback (but may cause oscillation)
# Recommended: 5 checks (2.5 minutes with 30-second intervals)
export STABILITY_CHECKS_REQUIRED="5"

# --- System Settings ---
# Core timing and operational parameters

# Check interval in seconds (how often to test Starlink connection)
# How it works: Script wakes up every X seconds to test Starlink quality
# Shorter intervals = faster detection of issues, more system load
# Longer intervals = slower detection, less system load
# Affects: Battery life (mobile), system resources, failover speed
# Recommended: 30 seconds for balanced monitoring, 60 seconds for battery conservation
export CHECK_INTERVAL="30"

# API timeout in seconds (maximum wait time for Starlink API responses)
# What it does: How long to wait for Starlink gRPC API to respond before giving up
# Includes: Starlink status queries, quality metrics, obstruction data
# Note: Does NOT affect Pushover API timeout (that's separate)
# Too low = false failures during temporary slowness
# Too high = slow detection of real API failures
# Recommended: 10 seconds (Starlink API is usually very fast <1s or fails completely)
export API_TIMEOUT="10"

# Pushover notification timeout in seconds (separate from Starlink API)
# What it does: How long to wait for Pushover notification service to respond
# Only affects: Push notification delivery, does not affect monitoring
# Recommended: 30 seconds (internet connection may be poor during failures)
export PUSHOVER_TIMEOUT="30"

# Directory for log files (persistent across reboots)
export LOG_DIR="/etc/starlink-logs"

# Installation directory (where scripts are installed)
export INSTALL_DIR="/usr/local/starlink-monitor"

# Directory for runtime state files
export STATE_DIR="/tmp/run"

# Log retention in days (how long to keep log files)
export LOG_RETENTION_DAYS="7"

# Syslog tag for log messages (shown in system logs)
export LOG_TAG="StarlinkMonitor"

# --- Performance Monitoring Configuration ---

# Maximum execution time for logger script (seconds)
# Alert if starlink_logger_unified-rutos.sh takes longer than this
export MAX_EXECUTION_TIME_SECONDS="30"

# Minimum processing rate (samples per second)
# Alert if processing rate drops below this threshold
export MAX_SAMPLES_PER_SECOND="10"

# Performance alert threshold (seconds)
# Send Pushover alert if script execution exceeds this time
export PERFORMANCE_ALERT_THRESHOLD="15"

# Maximum samples to process per logger run
# Prevents infinite loops when catching up with large sample backlogs
export MAX_SAMPLES_PER_RUN="60"

# Adaptive sampling configuration
# When falling behind, process every Nth sample instead of every sample
export ADAPTIVE_SAMPLING_ENABLED="true"
export ADAPTIVE_SAMPLING_INTERVAL="5" # Process every 5th sample when falling behind
export FALLBEHIND_THRESHOLD="100"     # Start adaptive sampling when queue > 100 samples

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
export AUTO_UPDATE_ENABLED="true"

# Enable update notifications (true/false) - Notifies about available updates even if auto-update is disabled
export AUTO_UPDATE_NOTIFICATIONS_ENABLED="true"

# Auto-update policies for different version types
# Format: Never|<number><unit> where unit is: Minutes|Hours|Days|Weeks|Months
# Examples: "Never", "30Minutes", "2Hours", "5Days", "2Weeks", "1Month"

# Patch version updates (2.1.3 -> 2.1.4) - Usually safe, quick fixes
export UPDATE_PATCH_DELAY="Never"

# Minor version updates (2.1.x -> 2.2.0) - New features, moderate risk
export UPDATE_MINOR_DELAY="Never"

# Major version updates (2.x.x -> 3.0.0) - Breaking changes, highest risk
export UPDATE_MAJOR_DELAY="Never" # Auto-update schedule (cron format)
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

# --- GPS Integration Configuration ---

# GPS data collection and source management
# Controls how GPS location data is collected and prioritized from multiple sources

# Enable GPS data collection (1=enabled, 0=disabled)
export GPS_ENABLED="1"

# GPS source priority configuration
# Sources: "starlink", "rutos", "combined"
# Priority: "primary", "secondary", "auto", "combined"
export GPS_PRIMARY_SOURCE="starlink" # Primary GPS data source
export GPS_SECONDARY_SOURCE="rutos"  # Fallback when primary unavailable
export GPS_SOURCE_MODE="auto"        # How to select: auto/primary/secondary/combined

# GPS data collection intervals
export GPS_COLLECTION_INTERVAL="60"  # Collect GPS data every N seconds
export GPS_STALENESS_THRESHOLD="300" # Consider GPS data stale after N seconds

# GPS data validation settings
export GPS_REQUIRE_VALID_FIX="true" # Only use GPS data with valid fix
export GPS_MIN_SATELLITES="4"       # Minimum satellites for valid position
export GPS_MAX_HDOP="10.0"          # Maximum horizontal dilution of precision

# GPS location change detection (for parking validation)
export GPS_MOVEMENT_THRESHOLD="50" # Minimum movement in meters to consider "moved"
export GPS_STATIONARY_TIME="1800"  # Time in seconds to consider "parked" (30 minutes)

# Enhanced GPS logging for analytics
export GPS_ANALYTICS_ENABLED="true" # Enable GPS analytics and trend tracking
export GPS_LOG_DETAILED="false"     # Log detailed GPS data (can be verbose)

# --- Cellular Integration Configuration ---

# Cellular data monitoring and smart failover management
# Controls how cellular modem data is collected and used for intelligent failover decisions

# Enable cellular data collection (1=enabled, 0=disabled)
export CELLULAR_ENABLED="1"

# Multi-modem configuration
export CELLULAR_AUTO_DETECT="true"             # Automatically detect available modems
export CELLULAR_INTERFACES="mob1s1a1 mob1s2a1" # Manual list if auto-detect disabled

# Cellular data collection
export CELLULAR_COLLECTION_INTERVAL="60" # Collect cellular data every N seconds
export CELLULAR_SIGNAL_THRESHOLD="-100"  # Minimum signal strength (dBm)

# Smart failover configuration
export CELLULAR_SMART_FAILOVER="true"  # Enable intelligent failover decisions
export CELLULAR_ROAMING_AWARE="true"   # Consider roaming costs in failover decisions
export CELLULAR_COST_PRIORITY="medium" # Priority: high/medium/low (high=avoid roaming)

# Cellular analytics and logging
export CELLULAR_ANALYTICS_ENABLED="true"  # Enable cellular analytics
export CELLULAR_LOG_SIGNAL_DETAILS="true" # Log detailed signal information

# =============================================================================
# UNIFIED SCRIPTS ENHANCED FEATURES CONFIGURATION
# =============================================================================
# These settings control enhanced features in the unified monitor and logger scripts
# All features default to 'false' to maintain backward compatibility with basic scripts

# --- MONITORING ENHANCEMENTS ---
# Enable GPS tracking for location-aware monitoring decisions
export ENABLE_GPS_TRACKING="${ENABLE_GPS_TRACKING:-false}"

# Enable cellular data collection for backup intelligence
export ENABLE_CELLULAR_TRACKING="${ENABLE_CELLULAR_TRACKING:-false}"

# Enable multi-source GPS (RUTOS + Starlink + cellular estimation)
export ENABLE_MULTI_SOURCE_GPS="${ENABLE_MULTI_SOURCE_GPS:-false}"

# Enable enhanced failover logic (considers GPS + cellular + multiple factors)
export ENABLE_ENHANCED_FAILOVER="${ENABLE_ENHANCED_FAILOVER:-false}"

# --- LOGGING ENHANCEMENTS ---
# Enable GPS data logging in CSV files
export ENABLE_GPS_LOGGING="${ENABLE_GPS_LOGGING:-false}"

# Enable cellular data logging (signal strength, operator, network type)
export ENABLE_CELLULAR_LOGGING="${ENABLE_CELLULAR_LOGGING:-false}"

# Enable enhanced metrics (SNR, reboot detection, GPS stats)
export ENABLE_ENHANCED_METRICS="${ENABLE_ENHANCED_METRICS:-false}"

# Enable statistical data aggregation (60:1 data reduction for long-term analytics)
export ENABLE_STATISTICAL_AGGREGATION="${ENABLE_STATISTICAL_AGGREGATION:-false}"

# Aggregation batch size (number of raw samples to aggregate into one record)
export AGGREGATION_BATCH_SIZE="${AGGREGATION_BATCH_SIZE:-60}"

# =============================================================================
# UNIFIED SCRIPTS CONFIGURATION EXAMPLES
# =============================================================================
# Uncomment and modify one of these example configurations to enable features:

# Example 1: Basic Installation (DEFAULT - all enhanced features disabled)
# Uses original script behavior - no changes needed
# ENABLE_GPS_TRACKING="false"
# ENABLE_CELLULAR_TRACKING="false"
# ENABLE_MULTI_SOURCE_GPS="false"
# ENABLE_ENHANCED_FAILOVER="false"
# ENABLE_GPS_LOGGING="false"
# ENABLE_CELLULAR_LOGGING="false"
# ENABLE_ENHANCED_METRICS="false"
# ENABLE_STATISTICAL_AGGREGATION="false"

# Example 2: Enhanced Stationary Installation
# Better metrics and GPS tracking without cellular complexity
# ENABLE_GPS_TRACKING="true"
# ENABLE_CELLULAR_TRACKING="false"
# ENABLE_MULTI_SOURCE_GPS="false"
# ENABLE_ENHANCED_FAILOVER="false"
# ENABLE_GPS_LOGGING="true"
# ENABLE_CELLULAR_LOGGING="false"
# ENABLE_ENHANCED_METRICS="true"
# ENABLE_STATISTICAL_AGGREGATION="true"

# Example 3: Mobile/RV Installation (full features)
# All enhanced features for mobile use cases
# ENABLE_GPS_TRACKING="true"
# ENABLE_CELLULAR_TRACKING="true"
# ENABLE_MULTI_SOURCE_GPS="true"
# ENABLE_ENHANCED_FAILOVER="true"
# ENABLE_GPS_LOGGING="true"
# ENABLE_CELLULAR_LOGGING="true"
# ENABLE_ENHANCED_METRICS="true"
# ENABLE_STATISTICAL_AGGREGATION="true"
# AGGREGATION_BATCH_SIZE="60"

# Example 4: Analytics Focus Installation
# Emphasis on data collection and aggregation
# ENABLE_GPS_TRACKING="true"
# ENABLE_CELLULAR_TRACKING="true"
# ENABLE_MULTI_SOURCE_GPS="true"
# ENABLE_ENHANCED_FAILOVER="false"
# ENABLE_GPS_LOGGING="true"
# ENABLE_CELLULAR_LOGGING="true"
# ENABLE_ENHANCED_METRICS="true"
# ENABLE_STATISTICAL_AGGREGATION="true"
# AGGREGATION_BATCH_SIZE="30"  # More frequent aggregation

# --- Binary Paths (set by install script) ---

export GRPCURL_CMD="/usr/local/starlink-monitor/grpcurl" # gRPC client for Starlink API
export JQ_CMD="/usr/local/starlink-monitor/jq"           # JSON processor for parsing API responses
