#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC2154

# ==============================================================================
# STARLINK MONITOR UNIFIED CONFIGURATION
# ==============================================================================
# This is the unified configuration template for Starlink monitoring.
# All features are included here, organized by complexity and usage.
#
# SECTIONS:
# 1. MANDATORY BASIC    - Essential settings (everyone needs these)
# 2. OPTIONAL BASIC     - Common optional features
# 3. ADVANCED GPS       - GPS integration and location services
# 4. ADVANCED CELLULAR  - Multi-modem cellular monitoring
# 5. ADVANCED SYSTEM    - Performance, security, and maintenance
# 6. EXPERT/DEBUG       - Developer and troubleshooting settings
#
# Template version: 2.6.0
# Compatible with install.sh: 2.6.0+
# ==============================================================================

# Version information (auto-updated by update-version.sh)
if [ -z "${SCRIPT_VERSION:-}" ]; then
    # Version information (auto-updated by update-version.sh)
    SCRIPT_VERSION="2.7.0"
    readonly SCRIPT_VERSION
fi

# Configuration metadata for troubleshooting
CONFIG_VERSION="2.7.0"
CONFIG_TYPE="unified"

# Version logging for troubleshooting
echo "Starlink Monitor Unified Configuration v$SCRIPT_VERSION loaded" >/dev/null 2>&1 || true

# ==============================================================================
# 1. MANDATORY BASIC CONFIGURATION
# ==============================================================================
# These settings are REQUIRED for the system to function.
# You MUST configure these values for your specific setup.

# --- Starlink Connection Settings ---
# Starlink gRPC endpoint IP and port
# Default: 192.168.100.1:9200 (standard Starlink configuration)
# Change only if your Starlink uses a different IP
export STARLINK_IP="192.168.100.1:9200"

# --- MWAN3 Failover Configuration ---
# Check your MWAN3 config: uci show mwan3 | grep interface
# Check your MWAN3 config: uci show mwan3 | grep member
export MWAN_IFACE="wan"      # MWAN3 interface name for Starlink
export MWAN_MEMBER="member1" # MWAN3 member name for Starlink

# Failover routing metrics (lower = higher priority)
export METRIC_GOOD="1" # Normal Starlink priority
export METRIC_BAD="20" # Failover priority when Starlink is down

# --- Quality Thresholds ---
# Adjust these based on your quality requirements
export LATENCY_THRESHOLD="100"   # Milliseconds - above this triggers failover
export PACKET_LOSS_THRESHOLD="5" # Percentage - above this triggers failover
export JITTER_THRESHOLD="20"     # Milliseconds - network stability

# --- Basic Timing ---
export CHECK_INTERVAL="30"           # How often to test Starlink (seconds)
export API_TIMEOUT="10"              # API call timeout (seconds)
export STABILITY_CHECKS_REQUIRED="5" # Consecutive good tests before recovery

# ==============================================================================
# 2. OPTIONAL BASIC CONFIGURATION
# ==============================================================================
# Common features that many users want, but are not required for basic operation.
# Enable/disable features by changing values from 0 to 1 or "false" to "true"

# --- Pushover Notifications ---
# Get your tokens from: https://pushover.net/
# Set PUSHOVER_ENABLED=1 to enable notifications
export PUSHOVER_ENABLED="0" # 1=enabled, 0=disabled
export PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
export PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

# Notification Control (what events to notify about)
export NOTIFY_ON_CRITICAL="1"     # System failures, API errors (recommended: 1)
export NOTIFY_ON_SOFT_FAIL="1"    # Starlink degraded but usable (recommended: 1)
export NOTIFY_ON_HARD_FAIL="1"    # Complete Starlink failure (recommended: 1)
export NOTIFY_ON_RECOVERY="1"     # Starlink recovered (recommended: 1)
export NOTIFY_ON_SIGNAL_RESET="1" # Cellular modem resets (mobile setups only)

# --- Enhanced Logging ---
export LOG_RETENTION_DAYS="30"  # How long to keep log files
export MAX_SAMPLES_PER_RUN="60" # Prevent processing backlogs that are too large

# Adaptive sampling when falling behind
export ADAPTIVE_SAMPLING_ENABLED="true" # Process every Nth sample when behind
export ADAPTIVE_SAMPLING_INTERVAL="5"   # Skip rate when adaptive mode active
export FALLBEHIND_THRESHOLD="100"       # Queue size that triggers adaptive mode

# --- System Maintenance ---
export MAINTENANCE_PUSHOVER_ENABLED="true"   # Notify about maintenance issues
export MAINTENANCE_NOTIFY_ON_FIXES="true"    # Notify when issues are fixed
export MAINTENANCE_NOTIFY_ON_FAILURES="true" # Notify when fixes fail
export MAINTENANCE_NOTIFY_ON_CRITICAL="true" # Always notify on critical issues

# --- Auto-Update Configuration ---
# Control how the system updates itself
export UPDATE_PATCH_DELAY="1 day"  # Patch updates (2.1.0 -> 2.1.1)
export UPDATE_MINOR_DELAY="1 week" # Minor updates (2.1.x -> 2.2.0)
export UPDATE_MAJOR_DELAY="Never"  # Major updates (2.x.x -> 3.0.0)

export AUTO_UPDATE_SCHEDULE="15 */4 * * *"    # Cron format: every 4 hours
export AUTO_UPDATE_BACKUP_ENABLED="true"      # Backup before updates
export AUTO_UPDATE_ROLLBACK_ON_FAILURE="true" # Auto-rollback on failure
export AUTO_UPDATE_NOTIFY_ON_SUCCESS="true"   # Notify on successful update
export AUTO_UPDATE_NOTIFY_ON_FAILURE="true"   # Notify on failed update

# ==============================================================================
# 3. ADVANCED GPS CONFIGURATION
# ==============================================================================
# GPS integration for location tracking, movement detection, and analytics.
# Enable GPS_ENABLED=1 to activate GPS features.

# --- GPS Basic Settings ---
export GPS_ENABLED="0" # 1=enabled, 0=disabled

# --- GPS Source Management ---
# Available sources: "starlink", "rutos", "combined"
# Modes: "auto" (intelligent selection), "primary" (prefer primary),
#        "secondary" (prefer secondary), "combined" (merge data)
export GPS_PRIMARY_SOURCE="starlink"  # Primary GPS data source
export GPS_SECONDARY_SOURCE="rutos"   # Fallback when primary unavailable
export GPS_TERTIARY_SOURCE="combined" # Third option for maximum reliability
export GPS_SOURCE_MODE="auto"         # How to select sources

# --- GPS Data Collection ---
export GPS_COLLECTION_INTERVAL="60"        # Collect GPS data every N seconds
export GPS_STALENESS_THRESHOLD="300"       # Consider data stale after N seconds
export GPS_BACKUP_COLLECTION_INTERVAL="60" # Fallback collection timing

# --- GPS Data Quality ---
export GPS_REQUIRE_VALID_FIX="true"   # Only use GPS with valid position fix
export GPS_MIN_SATELLITES="4"         # Minimum satellites for valid position
export GPS_MAX_HDOP="10.0"            # Maximum horizontal dilution of precision
export GPS_MIN_SIGNAL_STRENGTH="-140" # Minimum GPS signal strength (dBm)

# --- Movement Detection & Parking Validation ---
export GPS_MOVEMENT_THRESHOLD="50" # Minimum movement to consider "moved" (meters)
export GPS_STATIONARY_TIME="1800"  # Time to consider "parked" (seconds, 30 min)
export GPS_TRACK_SPEED_CHANGES="0" # Track speed variations (1=enabled)
export GPS_GEOFENCE_ENABLED="0"    # Enable geofence-based analytics

# --- GPS Analytics ---
export GPS_ANALYTICS_ENABLED="true"     # Enable GPS analytics and reporting
export GPS_LOG_DETAILED="false"         # Log detailed GPS data (can be verbose)
export GPS_GENERATE_REPORTS="0"         # Generate periodic analytics reports
export GPS_REPORT_INTERVAL="3600"       # Report generation interval (seconds)
export GPS_LOCATION_HISTORY_SIZE="1000" # Number of location points to retain

# ==============================================================================
# 4. ADVANCED CELLULAR CONFIGURATION
# ==============================================================================
# Multi-modem cellular monitoring and intelligent failover management.
# Enable CELLULAR_ENABLED=1 to activate cellular features.

# --- Cellular Basic Settings ---
export CELLULAR_ENABLED="0" # 1=enabled, 0=disabled

# --- Multi-Modem Configuration ---
export CELLULAR_AUTO_DETECT="true"             # Automatically detect available modems
export CELLULAR_INTERFACES="mob1s1a1 mob1s2a1" # Manual list if auto-detect disabled
export CELLULAR_MONITOR_ALL_SIMS="1"           # Monitor all SIM slots, not just active
export CELLULAR_DUAL_SIM_AWARE="1"             # Advanced dual-SIM management

# --- Cellular Data Collection ---
export CELLULAR_COLLECTION_INTERVAL="60" # Collect cellular data every N seconds
export CELLULAR_SIGNAL_THRESHOLD="-100"  # Minimum acceptable signal strength (dBm)
export CELLULAR_QUALITY_METRICS="1"      # Collect advanced quality metrics (RSRQ, SINR)
export CELLULAR_NETWORK_SCAN_ENABLED="0" # Periodic network scanning for optimization

# --- Smart Failover Configuration ---
export CELLULAR_SMART_FAILOVER="true"                     # Enable intelligent failover decisions
export CELLULAR_ROAMING_AWARE="true"                      # Consider roaming costs in decisions
export CELLULAR_COST_PRIORITY="medium"                    # Priority: high/medium/low (high=avoid roaming)
export CELLULAR_LOAD_BALANCING="0"                        # Enable load balancing across modems
export CELLULAR_CARRIER_PREFERENCES="operator1 operator2" # Preferred carriers in order

# --- Cellular Analytics ---
export CELLULAR_ANALYTICS_ENABLED="true"  # Enable comprehensive analytics
export CELLULAR_LOG_SIGNAL_DETAILS="true" # Log detailed signal information
export CELLULAR_TRACK_HANDOFFS="0"        # Track cell tower handoffs
export CELLULAR_PERFORMANCE_SCORING="0"   # Score performance for intelligent switching
export CELLULAR_GENERATE_REPORTS="0"      # Generate periodic analytics reports

# --- Cellular Decision Engine ---
export CELLULAR_DECISION_ALGORITHM="simple" # Algorithm: simple/weighted/multi_factor
export CELLULAR_SIGNAL_WEIGHT="40"          # Signal strength weight in decisions (%)
export CELLULAR_COST_WEIGHT="30"            # Cost consideration weight (%)
export CELLULAR_PERFORMANCE_WEIGHT="30"     # Historical performance weight (%)

# ==============================================================================
# 5. ADVANCED SYSTEM CONFIGURATION
# ==============================================================================
# Performance optimization, security, and advanced system management.
# These settings are for users who want to fine-tune system behavior.

# --- Performance Settings ---
export MAX_EXECUTION_TIME_SECONDS="30"  # Alert if any script takes longer than this
export MAX_SAMPLES_PER_SECOND="10"      # Rate limiting for high-load scenarios
export PERFORMANCE_ALERT_THRESHOLD="15" # Alert threshold for execution time

# --- Security Settings ---
export ENABLE_API_RATE_LIMITING="1" # Rate limit API calls to prevent abuse
export ENABLE_SECURE_LOGGING="0"    # Encrypt sensitive log data
export ENABLE_INTEGRITY_CHECKS="0"  # Verify script integrity

# --- Advanced Data Management ---
export ENABLE_PERFORMANCE_LOGGING="0"     # Log detailed performance metrics
export ENABLE_DATABASE_OPTIMIZATION="1"   # Optimize log files automatically
export BACKUP_DIR="/etc/starlink-backups" # Location for configuration backups

# --- Data Limits and Thresholds ---
export DATA_LIMIT_WARNING_THRESHOLD="80"  # Warn when approaching data limits (%)
export DATA_LIMIT_CRITICAL_THRESHOLD="95" # Critical alert threshold (%)

# --- Advanced Notification Settings ---
export MAINTENANCE_CRITICAL_THRESHOLD="1"       # Critical notification threshold
export MAINTENANCE_BATCH_NOTIFICATIONS="false"  # Batch multiple notifications
export MAINTENANCE_NOTIFICATION_COOLDOWN="3600" # Cooldown between notifications (seconds)

# ==============================================================================
# 6. EXPERT/DEBUG CONFIGURATION
# ==============================================================================
# Developer settings, debugging options, and experimental features.
# Only modify these if you know what you're doing.

# --- Debug Settings ---
export DEBUG_MODE="0"      # 1=enabled, 0=disabled
export DRY_RUN="0"         # 1=simulate actions, 0=perform actions
export CONFIG_DEBUG="0"    # Debug configuration loading
export RUTOS_TEST_MODE="0" # Test mode for validation

# --- Logging Verbosity ---
export LOG_LEVEL="INFO"            # ERROR, WARN, INFO, DEBUG, TRACE
export ENABLE_TRACE_LOGGING="0"    # Extremely verbose logging
export DEBUG_CELLULAR_COMMANDS="0" # Debug cellular command execution
export DEBUG_GPS_COLLECTION="0"    # Debug GPS data collection

# --- Experimental Features ---
export ENABLE_EXPERIMENTAL_FEATURES="0" # Enable experimental functionality
export EXPERIMENTAL_FEATURE_LIST=""     # Comma-separated list of features to enable

# --- Development Settings ---
export DEV_MODE="0"                # Development mode with relaxed validation
export TEST_API_ENDPOINTS="0"      # Test API endpoints before using
export MOCK_HARDWARE_RESPONSES="0" # Use mock responses for testing

# ==============================================================================
# SYSTEM PATHS AND DIRECTORIES
# ==============================================================================
# These paths are set by the installation script and generally should not be changed.

# Core system paths
export LOG_DIR="/etc/starlink-logs"
export INSTALL_DIR="/usr/local/starlink-monitor"
export STATE_DIR="/tmp/run"

# Binary paths (set by install script)
export GRPCURL_CMD="/usr/local/starlink-monitor/grpcurl"
export JQ_CMD="/usr/local/starlink-monitor/jq"

# ==============================================================================
# END OF CONFIGURATION
# ==============================================================================
# Do not modify anything below this line unless you know what you're doing.
