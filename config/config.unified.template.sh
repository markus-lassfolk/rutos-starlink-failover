#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC2154

# ==============================================================================
# STARLINK MONITOR UNIFIED CONFIGURATION
# ==============================================================================
# This is the comprehensive unified configuration template for Starlink monitoring.
# All features are included here with detailed explanations and best practices.
#
# ORGANIZATION:
# 1. MANDATORY BASIC    - Essential settings (everyone needs these)
# 2. OPTIONAL BASIC     - Common optional features with clear explanations
# 3. ADVANCED GPS       - GPS integration with detailed usage guidance
# 4. ADVANCED CELLULAR  - Multi-modem cellular with intelligent failover
# 5. ADVANCED SYSTEM    - Performance, security, and maintenance optimization
# 6. EXPERT/DEBUG       - Developer tools and troubleshooting settings
#
# Template version: 2.7.1
# Compatible with install.sh: 2.7.1+
# ==============================================================================

# Version information (auto-updated by update-version.sh)
# Note: Only set SCRIPT_VERSION if not already set (prevents conflicts when sourced)
if [ -z "${SCRIPT_VERSION:-}" ]; then
    # Script configuration template for Starlink RUTOS Failover
    # Version information (auto-updated by update-version.sh)
    SCRIPT_VERSION="2.7.1"
    readonly SCRIPT_VERSION
fi

# Configuration metadata for troubleshooting and updates
CONFIG_VERSION="2.7.1"
CONFIG_TYPE="unified"

# Used for troubleshooting: echo "Config version: $SCRIPT_VERSION"

# ==============================================================================
# 1. MANDATORY BASIC CONFIGURATION
# ==============================================================================
# These settings are REQUIRED for the system to function properly.
# You MUST configure these values for your specific router and network setup.

# --- Starlink Connection Settings ---

# Starlink gRPC endpoint IP and port (separate variables for flexibility)
# Default: IP=192.168.100.1, PORT=9200 (standard Starlink configuration)
# What it is: The internal IP address and port where Starlink's API service runs
# When to change: Only if your Starlink uses a different IP (very rare)
# Impact: If wrong, all Starlink monitoring will fail
export STARLINK_IP="192.168.100.1"
export STARLINK_PORT="9200"

# --- MWAN3 Failover Configuration ---

# MWAN3 interface name for Starlink connection
# What it is: The name of the network interface used for Starlink in MWAN3
# Check your MWAN3 config: uci show mwan3 | grep interface
# Common values: "wan", "wan1", "starlink"
# Impact: Must match your MWAN3 configuration exactly or failover won't work
export MWAN_IFACE="wan"

# MWAN3 member name for Starlink connection
# What it is: The MWAN3 member configuration name for Starlink routing
# Check your MWAN3 config: uci show mwan3 | grep member
# Common values: "member1", "starlink_member", "wan_member"
# Impact: Must match your MWAN3 configuration exactly or failover won't work
export MWAN_MEMBER="member1"

# MWAN3 metric values for failover control
# METRIC_GOOD: Normal routing priority (lower numbers = higher priority)
# METRIC_BAD: Failover routing priority (higher numbers = lower priority)
# How it works: When Starlink is healthy, uses METRIC_GOOD for high priority
#               When Starlink fails, uses METRIC_BAD for low priority (cellular takes over)
# Typical setup: GOOD=1 (highest priority), BAD=20 (lower than cellular backup)
# Impact: Controls routing priority - wrong values can prevent proper failover
export METRIC_GOOD="1"
export METRIC_BAD="20"

# --- Basic Failover Thresholds ---
# These settings control when the system triggers failover to cellular backup
# Adjust based on your quality requirements and usage patterns

# Latency threshold in milliseconds (ping response time)
# How it works: High latency indicates poor satellite connection or network congestion
# What affects it: Distance to satellite, weather, network congestion, obstructions
# Typical Starlink: 20-40ms good, 50-80ms acceptable, 100ms+ problematic
# Impact on apps: VoIP, gaming, video calls become unusable above 150ms
# Recommended: 150ms for general use, 100ms for latency-sensitive applications
# Too low: Frequent unnecessary failovers, Too high: Poor user experience
export LATENCY_THRESHOLD="100"

# Packet loss threshold (percentage as decimal: 0.05 = 5%)
# How it works: If packet loss exceeds this percentage, triggers failover
# What causes it: Obstructions, weather, dish movement, satellite handoffs
# Normal Starlink: <1% loss is excellent, 1-3% acceptable, >5% problematic
# Impact on apps: Web browsing tolerates 2-3%, streaming fails above 5%
# Recommended: 5% for balanced reliability vs stability
# Too low: Failover during brief weather events, Too high: Noticeable performance issues
export PACKET_LOSS_THRESHOLD="5"

# Obstruction threshold (percentage as decimal: 0.03 = 3%)
# How it works: Starlink reports obstructions (trees, buildings) blocking satellite view
# What it indicates: Physical objects between dish and satellites
# Realistic levels: 0-1% excellent, 1-3% good, 3-5% acceptable, 5%+ poor
# Field experience: Many users see 0.1-0.5% regularly without outages
# Starlink tolerance: Can handle brief obstructions up to 2-3% without significant impact
# Recommended: 0.03 (3%) - balanced sensitivity that avoids false positives
# Note: Consider dish relocation if this threshold is frequently exceeded
export OBSTRUCTION_THRESHOLD="0.03"

# Enhanced obstruction analysis settings
# Enable intelligent obstruction analysis using historical data
# When true: Uses timeObstructed, avgProlongedObstructionIntervalS, and validS for smarter decisions
# When false: Uses only current fractionObstructed for simple threshold comparison
# Recommended: true for production, false for testing/debugging
export ENABLE_INTELLIGENT_OBSTRUCTION="true"

# Minimum hours of obstruction data required for intelligent analysis
# If less data is available, falls back to simple threshold check
# Purpose: Prevents decisions based on insufficient historical context
# Recommended: 1 hour minimum, 4 hours for very stable analysis
export OBSTRUCTION_MIN_DATA_HOURS="1"

# Historical obstruction time threshold (percentage)
# Triggers failover if time spent obstructed over the data period exceeds this
# This is different from current obstruction - it's about cumulative time impact
# Example: 1% means if dish was obstructed more than 1% of total time in the measurement period
# Realistic values: 0.5-2% depending on your tolerance for service interruption
export OBSTRUCTION_HISTORICAL_THRESHOLD="1.0"

# Prolonged obstruction duration threshold (seconds)
# Triggers failover if average prolonged obstruction duration exceeds this
# What it catches: Situations where obstructions last long enough to disrupt service
# Realistic values: 30-60 seconds (shorter = more sensitive to brief interruptions)
export OBSTRUCTION_PROLONGED_THRESHOLD="30"

# Jitter threshold in milliseconds (variation in latency)
# What is jitter: The variation in ping times - indicates network stability
# How measured: Standard deviation of latency measurements over time
# Quality indicators: 0-5ms excellent, 5-10ms good, 10-20ms acceptable, 20ms+ poor
# Impact on apps: Video streaming, VoIP quality, real-time gaming, video calls
# Recommended: 20ms for general use, 10ms for real-time applications
# High jitter symptoms: Choppy video calls, stuttering streaming, game lag spikes
export JITTER_THRESHOLD="20"

# --- Basic Timing Configuration ---

# Check interval in seconds (how often to test Starlink connection)
# How it works: Script wakes up every X seconds to test Starlink quality
# Balance considerations:
#   Shorter intervals = faster detection of issues, more system load, more battery drain
#   Longer intervals = slower detection, less system load, better battery life
# Impact: Failover detection speed vs system resource usage
# Recommended: 30 seconds for balanced monitoring, 60 seconds for battery conservation
# Mobile use: Consider 60+ seconds to preserve battery life
export CHECK_INTERVAL="30"

# API timeout in seconds (maximum wait time for Starlink API responses)
# What it controls: How long to wait for Starlink gRPC API to respond before giving up
# What it includes: Starlink status queries, quality metrics, obstruction data
# Normal behavior: Starlink API is usually very fast (<1 second) or fails completely
# Trade-offs: Too low = false failures during temporary slowness
#            Too high = slow detection of real API failures
# Recommended: 10 seconds (allows for temporary network delays)
# Note: Does NOT affect Pushover API timeout (that's separate)
export API_TIMEOUT="10"

# Stability checks required before failback (consecutive good checks needed)
# How it works: After Starlink recovers, wait for X consecutive good checks before switching back
# Purpose: Prevents rapid back-and-forth switching when connection is marginal
# Calculation: With 30-second intervals, 5 checks = 2.5 minutes of stable connection
# Trade-offs: Higher values = more stable failback but slower recovery
#            Lower values = faster failback but may cause oscillation
# Recommended: 5 checks for balanced stability vs recovery speed
# Flaky connection areas: Consider 8-10 checks for more stability
export STABILITY_CHECKS_REQUIRED="5"

# ==============================================================================
# 2. OPTIONAL BASIC CONFIGURATION
# ==============================================================================
# Common features that enhance the monitoring experience but are not required.
# Enable/disable features by changing values from 0 to 1 or "false" to "true"
# All features include detailed usage guidance and impact explanations.
#
# BOOLEAN VALUE PATTERNS IN THIS CONFIG:
# - Notification enables use "1"/"0" (legacy compatibility)
# - Feature enables use "true"/"false" (modern boolean logic)
# - Priority/level values use numbers (1-3 for priorities, 0-7 for log levels)

# --- Pushover Notification Settings ---

# Enable/disable push notifications entirely
# What it is: Mobile push notifications via Pushover service (https://pushover.net/)
# Benefits: Instant alerts on phone/tablet when issues occur, even when away from router
# Requirements: Pushover account ($5 one-time), API token, user key
# Impact: Real-time awareness of connectivity issues vs no notifications
export PUSHOVER_ENABLED="0" # 1=enabled, 0=disabled

# Legacy compatibility variable for monitoring script
export ENABLE_PUSHOVER="${PUSHOVER_ENABLED}" # Compatibility mapping

# Pushover API credentials for notifications
# Get your token from: https://pushover.net/apps/build
# Get your user key from: https://pushover.net/
# Security note: These are sensitive credentials - keep them private
# Leave as placeholders to disable notifications
export PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
export PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

# Pushover notification timeout in seconds (separate from Starlink API)
# What it does: How long to wait for Pushover notification service to respond
# When it matters: During network outages when internet connection may be poor
# Only affects: Push notification delivery, does not affect monitoring
# Recommended: 30 seconds (internet connection may be poor during failures)
export PUSHOVER_TIMEOUT="30"

# Notification triggers - control what events send push notifications
# Enable each type based on how much detail you want in notifications

# Critical errors and system failures (HIGHLY RECOMMENDED)
# When triggered: API failures, system errors, complete monitoring failure
# Impact: Alerts to serious problems that need immediate attention
# Recommended: 1 (always enable for system health awareness)
export NOTIFY_ON_CRITICAL="1"

# Complete Starlink failures (HIGHLY RECOMMENDED)
# When triggered: Total loss of Starlink connectivity, failover to cellular
# Impact: Know immediately when you're on backup internet
# Recommended: 1 (important for data usage awareness on cellular)
export NOTIFY_ON_HARD_FAIL="1"

# System recovery notifications (RECOMMENDED)
# When triggered: Starlink recovers and becomes primary connection again
# Impact: Know when you're back on unlimited Starlink vs cellular data
# Recommended: 1 (important for mobile users with data limits)
export NOTIFY_ON_RECOVERY="1"

# Degraded performance warnings (OPTIONAL)
# When triggered: Starlink working but below quality thresholds (high latency, packet loss)
# Impact: Early warning of potential issues vs notification noise
# Recommended: 0 for basic setups (can be noisy), 1 for quality-sensitive applications
export NOTIFY_ON_SOFT_FAIL="0"

# Status and informational updates (USUALLY DISABLED)
# When triggered: Routine status updates, configuration changes
# Impact: Detailed system awareness vs notification overload
# Recommended: 0 (creates too many notifications for most users)
export NOTIFY_ON_INFO="0"

# Cellular modem reset notifications (MOBILE ONLY)
# When triggered: Cellular modem restarts or reconnects
# Impact: Awareness of cellular backup health vs notification volume
# Recommended: 1 for mobile/RV setups, 0 for stationary installations
export NOTIFY_ON_SIGNAL_RESET="1"

# --- System Settings ---
# Core timing and operational parameters that affect system behavior

# Directory for log files (persistent across reboots)
# What it stores: All monitoring logs, statistics, historical data
# Size consideration: Logs grow over time - monitor disk usage
# Backup importance: Contains valuable connectivity history
export LOG_DIR="/etc/starlink-logs"

# Installation directory (where scripts are installed)
# What it contains: Monitoring scripts, binary tools (grpcurl, jq)
# Modification: Generally should not be changed unless custom installation
export INSTALL_DIR="/usr/local/starlink-monitor"

# Directory for runtime state files
# What it stores: Temporary files, process IDs, current status
# Memory consideration: Usually stored in RAM (/tmp) - lost on reboot
export STATE_DIR="/tmp/run"

# Log retention in days (how long to keep historical log files)
# Balance: Historical data for analysis vs disk space usage
# Considerations: 7 days = minimal history, 30 days = good analysis, 90+ days = long-term trends
# Impact: Longer retention = better troubleshooting data but more disk usage
# Recommended: 7 days for basic setups, 30 days for analytics
export LOG_RETENTION_DAYS="30"

# Syslog tag for log messages (shown in system logs)
# What it is: Identifier prefix for all log entries from this system
# Usage: Helps filter logs when troubleshooting: logread | grep StarlinkMonitor
# Impact: Organization of system logs for easier troubleshooting
export LOG_TAG="StarlinkMonitor"

# --- Performance Monitoring Configuration ---
# Settings that control how the system monitors its own performance and handles load

# Maximum execution time for logger script (seconds)
# What it monitors: How long starlink_logger_unified-rutos.sh takes to complete
# When to alert: If processing takes longer than expected (indicates system overload)
# Impact: Helps detect system performance issues before they affect monitoring
# Recommended: 30 seconds (allows for temporary system load spikes)
export MAX_EXECUTION_TIME_SECONDS="30"

# Minimum processing rate (samples per second)
# What it monitors: How fast the system can process data samples
# Purpose: Detect when system is falling behind in data processing
# Impact: Prevents infinite loops when catching up with large backlogs
# Recommended: 10 samples/second (adequate for most router hardware)
export MAX_SAMPLES_PER_SECOND="10"

# Performance alert threshold (seconds)
# What it does: Send Pushover alert if script execution exceeds this time
# Purpose: Early warning of system performance degradation
# Balance: Too low = false alerts during system load, too high = miss real issues
# Recommended: 15 seconds (half of MAX_EXECUTION_TIME for early warning)
export PERFORMANCE_ALERT_THRESHOLD="15"

# Maximum samples to process per logger run
# What it prevents: Infinite loops when catching up with large sample backlogs
# When it matters: After system downtime or when falling behind in processing
# Impact: Prevents system overload during catch-up processing
# Recommended: 60 samples (manageable batch size for router hardware)
export MAX_SAMPLES_PER_RUN="60"

# Adaptive sampling configuration
# What it does: When falling behind, process every Nth sample instead of every sample
# Purpose: Maintain real-time monitoring even when system can't keep up
# Trade-off: Reduced data granularity vs continued monitoring capability

# Enable adaptive sampling when falling behind
export ADAPTIVE_SAMPLING_ENABLED="true"

# Adaptive sampling interval (process every Nth sample when behind)
# How it works: When queue is large, process every 5th sample instead of all
# Impact: 5:1 data reduction to catch up quickly while maintaining monitoring
export ADAPTIVE_SAMPLING_INTERVAL="5"

# Queue size threshold that triggers adaptive sampling
# When triggered: When unprocessed sample queue exceeds this size
# Purpose: Early intervention before system becomes completely overwhelmed
# Recommended: 100 samples (represents ~50 minutes of 30-second monitoring)
export FALLBEHIND_THRESHOLD="100"

# --- Enhanced Logging Configuration ---

# Enhanced logging features for better data analysis and troubleshooting

# Enable enhanced metrics collection (SNR, reboot detection, GPS stats)
# What it adds: Signal-to-noise ratio, system reboot tracking, GPS quality metrics
# Benefits: Better troubleshooting data, trend analysis capabilities
# Impact: Slightly more processing overhead for significantly better data
# Recommended: true for most installations
export ENABLE_ENHANCED_METRICS="false"

# Enable statistical data aggregation (60:1 data reduction for long-term analytics)
# What it does: Aggregates multiple raw samples into statistical summaries
# Purpose: Long-term trend analysis without massive log files
# How it works: 60 raw samples → 1 statistical record (min, max, avg, std dev)
# Benefits: Enables months/years of analysis data in manageable file sizes
export ENABLE_STATISTICAL_AGGREGATION="false"

# Aggregation batch size (number of raw samples to aggregate into one record)
# How it works: Combines N raw samples into one statistical summary
# Common values: 60 = hourly aggregation, 30 = 15-minute aggregation
# Impact: Higher values = more compression but less granular data
# Recommended: 60 for long-term storage, 30 for more detailed analysis
export AGGREGATION_BATCH_SIZE="60"

# --- System Maintenance Configuration ---
# Automated system maintenance and optimization settings

# Enable Pushover notifications for critical maintenance issues
# What it does: Sends notifications when maintenance script finds/fixes issues
# Why important: Know when your system is automatically healing itself
# Uses main PUSHOVER_TOKEN/PUSHOVER_USER unless overridden below
export MAINTENANCE_PUSHOVER_ENABLED="true"

# Optional: Override Pushover credentials specifically for maintenance
# Purpose: Separate maintenance alerts from monitoring alerts if desired
# Leave empty to use main PUSHOVER_TOKEN and PUSHOVER_USER settings
export MAINTENANCE_PUSHOVER_TOKEN="" # Leave empty to use PUSHOVER_TOKEN
export MAINTENANCE_PUSHOVER_USER=""  # Leave empty to use PUSHOVER_USER

# =============================================================================
# ENHANCED MAINTENANCE NOTIFICATION CONTROL
# =============================================================================
# Fine-grained control over what maintenance events trigger notifications

# Notification levels - control what gets sent via Pushover
# Each can be enabled/disabled independently based on how much detail you want

# Notify when issues are successfully fixed
# When triggered: Disk cleanup, log rotation, service restart successful
# Benefits: Know your system is self-healing vs no awareness of issues
# Recommended: true (good to know system is maintaining itself)
export MAINTENANCE_NOTIFY_ON_FIXES="true"

# Notify when fix attempts fail
# When triggered: Unable to clean logs, service restart fails, disk full
# Benefits: Immediate awareness of problems requiring manual intervention
# Recommended: true (critical for system health awareness)
export MAINTENANCE_NOTIFY_ON_FAILURES="true"

# Notify about critical issues (always recommended)
# When triggered: Disk nearly full, core services down, system instability
# Benefits: Emergency awareness of system-threatening conditions
# Recommended: true (essential for system reliability)
export MAINTENANCE_NOTIFY_ON_CRITICAL="true"

# Notify about issues found but not automatically fixed
# When triggered: Non-critical issues detected during system check
# Impact: Awareness of minor issues vs notification noise
# Recommended: false (can be noisy, most issues self-resolve)
export MAINTENANCE_NOTIFY_ON_FOUND="false"

# Notification thresholds and timing controls
# Balance between staying informed and avoiding notification spam

# Send critical notification if this many critical issues detected
# Purpose: Avoid spam from minor issues while ensuring serious problems get attention
# Recommended: 1 (lowered from default for better monitoring of router health)
export MAINTENANCE_CRITICAL_THRESHOLD="1"

# Cooldown between notifications (seconds)
# Purpose: Prevent notification spam during system instability
# Balance: Too short = spam, too long = miss ongoing issues
# Recommended: 1800 (30 minutes) - reduces spam but stays informed
export MAINTENANCE_NOTIFICATION_COOLDOWN="1800"

# Maximum individual notifications per maintenance run
# Purpose: Prevent notification flood if many issues found simultaneously
# Impact: Caps notification volume while ensuring most critical issues reported
# Recommended: 10 (enough for comprehensive issue reporting)
export MAINTENANCE_MAX_NOTIFICATIONS_PER_RUN="10"

# Notification priorities (Pushover priority levels)
# -2=lowest, -1=low, 0=normal, 1=high, 2=emergency (emergency requires acknowledgment)

# Priority for successful fixes (informational)
export MAINTENANCE_PRIORITY_FIXED="0" # Normal priority

# Priority for failed fixes (needs attention)
export MAINTENANCE_PRIORITY_FAILED="1" # High priority

# Priority for critical issues (urgent attention needed)
export MAINTENANCE_PRIORITY_CRITICAL="2" # Emergency priority

# Priority for found issues (awareness only)
export MAINTENANCE_PRIORITY_FOUND="0" # Normal priority

# =============================================================================
# SYSTEM MAINTENANCE BEHAVIOR CONTROL
# =============================================================================
# Control what maintenance actions the system can perform automatically

# Control automatic fix behavior
# What it enables: Automatic resolution of common issues (disk cleanup, log rotation)
# Safety: Only performs safe, well-tested fixes
# Recommended: true (enables self-healing system behavior)
export MAINTENANCE_AUTO_FIX_ENABLED="true"

# Control automatic reboot behavior (USE WITH CAUTION)
# What it enables: System reboot as last resort for critical issues
# When triggered: Only after multiple consecutive critical maintenance runs
# Safety consideration: Will interrupt connectivity - use carefully in production
# Recommended: false (manual intervention preferred for reboots)
export MAINTENANCE_AUTO_REBOOT_ENABLED="false"

# Number of consecutive critical maintenance runs before considering reboot
# Purpose: Ensure persistent problems before taking drastic action
# Safety: Multiple checks prevent accidental reboots from temporary issues
# Recommended: 5 (represents sustained system instability)
export MAINTENANCE_REBOOT_THRESHOLD="5"

# Service restart control
# What it enables: Automatic restart of failed services (networking, monitoring)
# Safety: Generally safe operation for service recovery
# Benefits: Self-healing of service failures without manual intervention
# Recommended: true (important for system reliability)
export MAINTENANCE_SERVICE_RESTART_ENABLED="true"

# Database fix control
# What it enables: Automatic repair/recreation of corrupted log databases
# When needed: Log file corruption, database lock issues
# Impact: May lose recent log data but restores functionality
# Recommended: true (prevents monitoring failures from database issues)
export MAINTENANCE_DATABASE_FIX_ENABLED="true"

# WiFi hostapd logging control
# What it optimizes: Reduces excessive WiFi access point logging
# Purpose: Prevents log spam from routine WiFi operations
# Impact: Cleaner logs, reduced disk usage, better performance
export MAINTENANCE_HOSTAPD_LOGGING_ENABLED="true"

# hostapd logging module control
# Module 2 = IEEE80211 (main WiFi logic), 127 = all modules
# Recommended: 2 (essential WiFi events only)
export HOSTAPD_LOGGER_SYSLOG="2"

# hostapd logging level control
# 1=error only, 2=error+warning, 3=error+warning+info, 4+=debug
# Recommended: 1 (errors only to reduce log noise)
export HOSTAPD_LOGGER_SYSLOG_LEVEL="1"
export HOSTAPD_LOGGER_STDOUT="2"
export HOSTAPD_LOGGER_STDOUT_LEVEL="1"

# DHCP dnsmasq logging control
# What it optimizes: Reduces excessive DHCP and DNS logging
# Purpose: Suppresses routine lease renewals and DNS query spam
# Impact: Much cleaner system logs, reduced disk I/O
export MAINTENANCE_DNSMASQ_LOGGING_ENABLED="true"

# DHCP logging control (0=disabled recommended)
# What it suppresses: "DHCPACK to device-name" messages every few minutes
# Impact: Eliminates most common log spam source
export DNSMASQ_LOG_DHCP="0"

# DNS query logging control (0=disabled recommended)
# What it suppresses: Every DNS lookup request
# Impact: Eliminates massive log volume from DNS queries
export DNSMASQ_LOG_QUERIES="0"

# System-wide log level control
# What it affects: Overall system logging verbosity
# 7=debug, 6=info, 5=notice, 4=warning, 3=error, 2=critical, 1=alert, 0=emergency
# Recommended: 4 (warning) - reduces noise while keeping important messages
export MAINTENANCE_SYSTEM_LOGLEVEL_ENABLED="true"
export SYSTEM_LOG_LEVEL="4"

# Maintenance mode override
# What it does: Force specific maintenance mode regardless of command line
# Options: "auto" (fix issues), "check" (report only), "fix" (force fixes), "report" (summary)
# Usage: Leave empty to use default behavior, set to override for testing
# Recommended: "" (empty - use default command line behavior)
export MAINTENANCE_MODE_OVERRIDE=""

# Safety controls for maintenance operations
# Prevent runaway maintenance operations that could impact system stability

# Maximum number of fixes to attempt in single maintenance run
# Purpose: Prevent system overload from attempting too many fixes simultaneously
# Balance: Enough to handle multiple issues but not overwhelm the system
# Recommended: 10 (handles typical issue counts without system stress)
export MAINTENANCE_MAX_FIXES_PER_RUN="10"

# Cooldown period after performing fixes (seconds)
# Purpose: Allow system to stabilize after fixes before next maintenance run
# Prevents: Rapid-fire maintenance cycles that could destabilize system
# Recommended: 300 (5 minutes) - allows system stabilization
export MAINTENANCE_COOLDOWN_AFTER_FIXES="300"

# --- Auto-Update Configuration ---
# Control how the system updates itself automatically

# Enable automatic updates via crontab (true/false)
# What it does: Automatically downloads and installs updates from GitHub
# Benefits: Latest features and bug fixes without manual intervention
# Risks: Potential instability from new releases (mitigated by delay settings below)
# Recommended: true with appropriate delays for your risk tolerance
export AUTO_UPDATE_ENABLED="true"

# Enable update notifications (true/false)
# What it does: Notifies about available updates even if auto-update is disabled
# Purpose: Awareness of available updates for manual installation decision
# Recommended: true (stay informed about available improvements)
export AUTO_UPDATE_NOTIFICATIONS_ENABLED="true"

# Auto-update policies for different version types
# Control how quickly different types of updates are applied
# Format: "Never" or "<number><unit>" where unit is: Minutes|Hours|Days|Weeks|Months
# Examples: "Never", "30Minutes", "2Hours", "5Days", "2Weeks", "1Month"

# Patch version updates (2.1.3 -> 2.1.4)
# What they contain: Bug fixes, security patches, minor improvements
# Risk level: Usually safe - typically fix existing issues
# Testing: Well-tested changes that don't alter core functionality
# Recommended: "Never" for critical systems, "1Days" for normal use, "30Minutes" for testing
export UPDATE_PATCH_DELAY="Never"

# Minor version updates (2.1.x -> 2.2.0)
# What they contain: New features, enhancements, configuration changes
# Risk level: Moderate - may change behavior or require configuration updates
# Testing: Extensively tested but may introduce new interactions
# Recommended: "Never" for critical systems, "1Weeks" for normal use, "1Days" for testing
export UPDATE_MINOR_DELAY="Never"

# Major version updates (2.x.x -> 3.0.0)
# What they contain: Breaking changes, major architecture updates
# Risk level: Highest - may require manual configuration migration
# Testing: Comprehensive testing but fundamental changes possible
# Recommended: "Never" (manual upgrade preferred), "1Months" for development systems
export UPDATE_MAJOR_DELAY="Never"

# Auto-update schedule (cron format)
# When updates are checked and applied (if enabled and delay criteria met)
# Default: Every 4 hours at minute 15: "15 */4 * * *"
# Considerations: Balance between timely updates and system stability
# Examples:
#   "0 2 * * *"     - Daily at 2 AM (minimal bandwidth impact)
#   "15 */6 * * *"  - Every 6 hours at minute 15 (faster response)
#   "0 3 * * 1"     - Weekly on Monday at 3 AM (conservative)
export AUTO_UPDATE_SCHEDULE="15 */4 * * *"

# Update behavior options
# Control safety features and notification behavior for updates

# Create backup before update
# What it does: Saves current configuration and scripts before updating
# Purpose: Enable rollback if update causes issues
# Impact: Requires additional disk space but provides safety net
# Recommended: true (essential safety feature)
export AUTO_UPDATE_BACKUP_ENABLED="true"

# Auto-rollback if update fails
# What it does: Automatically restores backup if update installation fails
# Purpose: Minimize downtime from failed updates
# Benefits: Self-healing behavior reduces manual intervention needed
# Recommended: true (automatic recovery from update failures)
export AUTO_UPDATE_ROLLBACK_ON_FAILURE="true"

# Send notification on successful update
# What it does: Pushover notification when update completes successfully
# Purpose: Awareness of system changes and version tracking
# Benefits: Know when features/fixes are available vs notification volume
# Recommended: true (important to know when system changes)
export AUTO_UPDATE_NOTIFY_ON_SUCCESS="true"

# Send notification on failed update
# What it does: Pushover notification when update fails
# Purpose: Immediate awareness of update problems requiring attention
# Benefits: Quick response to update issues before they accumulate
# Recommended: true (critical for system maintenance awareness)
export AUTO_UPDATE_NOTIFY_ON_FAILURE="true"

# ==============================================================================
# 3. ADVANCED GPS CONFIGURATION
# ==============================================================================
# GPS integration for location tracking, movement detection, and analytics.
# Essential for mobile installations (RVs, boats, vehicles) and useful for
# stationary installations to track Starlink performance by location.
# Enable GPS_ENABLED=1 to activate GPS features.

# --- GPS Basic Settings ---

# Enable GPS data collection (1=enabled, 0=disabled)
# What it enables: Location tracking, movement detection, location-based analytics
# When useful: Mobile installations, performance analysis by location, parking detection
# Resource impact: Minimal CPU/memory usage, small increase in log file size
# Recommended: 1 for mobile setups, 0 for basic stationary installations
export GPS_ENABLED="0"

# --- GPS Source Management ---
# Multiple GPS sources provide redundancy and improved accuracy

# GPS source priority configuration
# Available sources:
#   "starlink" - GPS data from Starlink terminal (most accurate when available)
#   "rutos" - GPS data from router's GPS module (if equipped)
#   "combined" - Merge data from multiple sources for best accuracy

# Primary GPS data source
# What to use: "starlink" for best accuracy, "rutos" if Starlink GPS unavailable
# Impact: Primary source used when available, fallback when not
# Recommended: "starlink" (most accurate and reliable)
export GPS_PRIMARY_SOURCE="starlink"

# Fallback when primary unavailable
# Purpose: Maintain GPS functionality when primary source fails
# Common scenario: Starlink GPS offline but router GPS still working
# Recommended: "rutos" (provides backup GPS capability)
export GPS_SECONDARY_SOURCE="rutos"

# Third option for maximum reliability
# Purpose: Additional fallback for mission-critical applications
# Usage: Rarely needed unless extremely high GPS reliability required
# Options: "combined" (merge all sources), specific source name
export GPS_TERTIARY_SOURCE="combined"

# GPS source selection mode
# How sources are prioritized and selected:
#   "auto" - Intelligent selection based on quality and availability
#   "primary" - Prefer primary source, fallback only when unavailable
#   "secondary" - Prefer secondary source (unusual but possible)
#   "combined" - Always merge data from multiple sources
# Recommended: "auto" (best balance of accuracy and reliability)
export GPS_SOURCE_MODE="auto"

# --- GPS Data Collection Timing ---

# Collect GPS data every N seconds
# Balance: More frequent = better tracking but higher resource usage
# Considerations: Battery life (mobile), processing load, log file size
# Typical values: 60s normal, 30s detailed tracking, 120s battery conservation
# Recommended: 60 seconds for balanced tracking
export GPS_COLLECTION_INTERVAL="60"

# Consider GPS data stale after N seconds
# Purpose: Ignore outdated GPS data that may be inaccurate
# When it matters: Poor GPS reception areas, GPS source interruptions
# Balance: Too short = lose valid data, too long = use outdated positions
# Recommended: 300 seconds (5 minutes) - allows for temporary GPS gaps
export GPS_STALENESS_THRESHOLD="300"

# Fallback collection timing when primary source unavailable
# Purpose: Different timing for backup GPS sources that may be less reliable
# Usage: Can be more frequent to compensate for lower accuracy
# Recommended: Same as primary unless backup source needs different timing
export GPS_BACKUP_COLLECTION_INTERVAL="60"

# --- GPS Data Quality Control ---
# Settings that ensure GPS data accuracy and reliability

# Only use GPS data with valid position fix
# What it means: GPS has calculated an accurate position (not just searching)
# Impact: Prevents using inaccurate data during GPS acquisition
# When to disable: Never - always want valid position data
# Recommended: true (essential for accurate location data)
export GPS_REQUIRE_VALID_FIX="true"

# Minimum satellites for valid position
# What it affects: Position accuracy and reliability
# GPS science: 4+ satellites needed for 3D position, more = better accuracy
# Quality levels: 4=basic, 6=good, 8+=excellent accuracy
# Recommended: 4 (minimum for reliable positioning)
export GPS_MIN_SATELLITES="4"

# Maximum horizontal dilution of precision (HDOP)
# What it measures: GPS geometry quality (lower = better)
# Quality scale: <2=excellent, 2-5=good, 5-10=moderate, >10=poor
# Impact: Higher HDOP = less accurate position data
# Recommended: 10.0 (accepts moderate quality, rejects poor geometry)
export GPS_MAX_HDOP="10.0"

# Minimum GPS signal strength (dBm)
# What it measures: Strength of GPS satellite signals
# Signal quality: >-130=excellent, -130 to -140=good, -140 to -150=moderate, <-150=poor
# Impact: Weaker signals = less reliable position data
# Recommended: -140 (good quality threshold)
export GPS_MIN_SIGNAL_STRENGTH="-140"

# --- Movement Detection & Parking Validation ---
# Features for mobile installations to detect travel vs stationary periods

# Minimum movement to consider "moved" (meters)
# Purpose: Distinguish between GPS noise and actual movement
# GPS accuracy: Typical accuracy ±3-5 meters, so movement threshold should be higher
# Usage: Parking detection, travel logging, location-based analytics
# Recommended: 50 meters (clearly distinguishes movement from GPS variance)
export GPS_MOVEMENT_THRESHOLD="50"

# Time to consider "parked" (seconds)
# Purpose: How long stationary before considering vehicle parked
# Usage: Distinguishes temporary stops from actual parking
# Calculation: 1800 seconds = 30 minutes
# Recommended: 1800 (30 minutes) - reasonable for distinguishing stops vs parking
export GPS_STATIONARY_TIME="1800"

# Track speed variations (1=enabled, 0=disabled)
# What it does: Monitor speed changes for driving pattern analysis
# Benefits: Detect driving vs highway vs city patterns affecting Starlink performance
# Impact: Additional processing and log data for speed analytics
# Recommended: 0 for basic use, 1 for detailed mobile analytics
export GPS_TRACK_SPEED_CHANGES="0"

# Enable geofence-based analytics (1=enabled, 0=disabled)
# What it does: Define geographic areas for location-based monitoring
# Benefits: Performance analysis by location (home, work, travel routes)
# Complexity: Requires defining geographic boundaries
# Recommended: 0 for basic use, 1 for advanced location analytics
export GPS_GEOFENCE_ENABLED="0"

# --- GPS Analytics and Reporting ---
# Features for analyzing GPS data and generating insights

# Enable GPS analytics and reporting
# What it provides: Location-based performance analysis, travel summaries
# Benefits: Understand Starlink performance patterns by location
# Impact: Additional processing for analytics generation
# Recommended: true for mobile installations
export GPS_ANALYTICS_ENABLED="true"

# Log detailed GPS data (can be verbose)
# What it includes: Full GPS technical data (satellites, signal strength, accuracy)
# Benefits: Detailed troubleshooting and analysis capabilities
# Impact: Significantly larger log files
# Recommended: false for normal use, true for GPS troubleshooting
export GPS_LOG_DETAILED="false"

# Generate periodic analytics reports (1=enabled, 0=disabled)
# What it creates: Summary reports of GPS and performance data
# Benefits: Regular insights into location-based performance patterns
# Impact: Additional processing for report generation
# Recommended: 0 for basic use, 1 for regular analytics review
export GPS_GENERATE_REPORTS="0"

# Report generation interval (seconds)
# How often analytics reports are generated
# Balance: Frequent reports = current insights, less frequent = lower overhead
# Calculation: 3600 seconds = 1 hour
# Recommended: 3600 (hourly) for active monitoring, 86400 (daily) for summaries
export GPS_REPORT_INTERVAL="3600"

# Number of location points to retain in memory
# Purpose: Rolling buffer for real-time analytics and movement detection
# Balance: More points = better analytics but higher memory usage
# Impact: Router memory usage (1000 points ≈ 100KB memory)
# Recommended: 1000 points (reasonable balance for router hardware)
export GPS_LOCATION_HISTORY_SIZE="1000"

# ==============================================================================
# 4. ADVANCED CELLULAR CONFIGURATION
# ==============================================================================
# Multi-modem cellular monitoring and intelligent failover management.
# Essential for mobile installations and backup internet reliability.
# Provides intelligent failover decisions based on signal quality, costs, and performance.
# Enable CELLULAR_ENABLED=1 to activate cellular features.

# --- Cellular Basic Settings ---

# Enable cellular data collection (1=enabled, 0=disabled)
# What it enables: Cellular signal monitoring, intelligent failover, multi-modem management
# When useful: Any setup with cellular backup, mobile installations, cost-conscious users
# Benefits: Smarter failover decisions, cost optimization, signal quality awareness
# Recommended: 1 for setups with cellular backup, 0 for Starlink-only installations
export CELLULAR_ENABLED="0"

# --- Multi-Modem Configuration ---
# Settings for managing multiple cellular modems and SIM cards

# Automatically detect available modems
# What it does: Scans system for cellular modems instead of using manual list
# Benefits: Automatically adapts to different router configurations
# When to disable: When you want precise control over which modems to monitor
# Recommended: true (automatic detection works for most setups)
export CELLULAR_AUTO_DETECT="true"

# Manual list if auto-detect disabled
# Purpose: Specify exact modem interfaces when auto-detection is disabled
# Format: Space-separated list of interface names
# Common RUTOS interfaces: "mob1s1a1" (modem 1, SIM 1), "mob1s2a1" (modem 1, SIM 2)
# Usage: Only needed when CELLULAR_AUTO_DETECT="false"
export CELLULAR_INTERFACES="mob1s1a1 mob1s2a1"

# Monitor all SIM slots, not just active (1=enabled, 0=disabled)
# What it does: Tracks signal quality on inactive SIM slots for comparison
# Benefits: Better failover decisions, SIM performance comparison
# Impact: Additional monitoring overhead for comprehensive coverage
# Recommended: 1 for dual-SIM setups, 0 for single-SIM to reduce overhead
export CELLULAR_MONITOR_ALL_SIMS="1"

# Advanced dual-SIM management (1=enabled, 0=disabled)
# What it enables: Intelligent switching between SIM cards based on performance
# Benefits: Automatic selection of best performing SIM card
# Complexity: Requires understanding of carrier differences and costs
# Recommended: 1 for dual-SIM mobile setups, 0 for single-SIM or stationary
export CELLULAR_DUAL_SIM_AWARE="1"

# --- Cellular Data Collection Timing ---

# Collect cellular data every N seconds
# Balance: More frequent = better failover decisions but higher processing overhead
# Considerations: Battery life (mobile), processing load, carrier query limits
# Typical values: 60s balanced, 30s responsive, 120s conservative
# Recommended: 60 seconds for good balance of responsiveness and efficiency
export CELLULAR_COLLECTION_INTERVAL="60"

# Minimum acceptable signal strength (dBm)
# Signal quality scale: -50 to -80=excellent, -80 to -90=good, -90 to -100=fair, -100 to -110=poor, <-110=unusable
# Purpose: Threshold below which cellular is considered unreliable
# Impact: Lower values = more tolerant of weak signals, higher = more selective
# Recommended: -100 dBm (fair signal threshold - usable but not great)
export CELLULAR_SIGNAL_THRESHOLD="-100"

# Collect advanced quality metrics (RSRQ, SINR) (1=enabled, 0=disabled)
# What it adds: Reference Signal Received Quality, Signal-to-Interference-plus-Noise Ratio
# Benefits: More sophisticated signal quality assessment beyond basic signal strength
# Impact: Additional processing overhead for more accurate quality metrics
# Recommended: 1 for detailed analysis, 0 for basic signal monitoring
export CELLULAR_QUALITY_METRICS="1"

# Periodic network scanning for optimization (1=enabled, 0=disabled)
# What it does: Scans for available cell towers and carriers for better connections
# Benefits: Can find better cell towers, detect new carriers
# Impact: Significant processing overhead, temporary connection interruptions
# Recommended: 0 for most users (can cause connection disruptions)
export CELLULAR_NETWORK_SCAN_ENABLED="0"

# --- Smart Failover Configuration ---
# Intelligent decision-making for when and how to use cellular backup

# Enable intelligent failover decisions
# What it adds: Cost-aware, performance-based failover instead of simple signal threshold
# Benefits: Avoids expensive roaming, considers data limits, optimizes for performance
# Complexity: More sophisticated decision logic than basic failover
# Recommended: true for mobile setups and cost-conscious users
export CELLULAR_SMART_FAILOVER="true"

# Consider roaming costs in failover decisions
# What it does: Avoids or delays cellular failover when roaming charges apply
# Benefits: Prevents unexpected roaming charges from automatic failover
# When important: International travel, border areas, costly roaming plans
# Recommended: true for mobile users, false for stationary with local SIMs only
export CELLULAR_ROAMING_AWARE="true"

# Cost consideration priority in failover decisions
# How cost factors into failover decisions:
#   "high" - Strongly avoid costly connections (delay failover when roaming)
#   "medium" - Balance cost vs connectivity (brief roaming acceptable)
#   "low" - Prioritize connectivity over cost (failover regardless of roaming)
# Recommended: "medium" for balanced cost/connectivity, "high" for cost-sensitive users
export CELLULAR_COST_PRIORITY="medium"

# Enable load balancing across modems (1=enabled, 0=disabled)
# What it does: Distributes traffic across multiple cellular modems simultaneously
# Benefits: Higher combined bandwidth, redundancy if one modem fails
# Complexity: Requires advanced router configuration, may increase costs
# Recommended: 0 for most users (complex and can increase data usage)
export CELLULAR_LOAD_BALANCING="0"

# Preferred carriers in order
# Purpose: Specify carrier preference when multiple options available
# Format: Space-separated list of carrier names or IDs
# Usage: "Verizon AT&T" or operator IDs like "310410 310260"
# Benefits: Optimize for known good carriers in your area
# Recommended: Leave as example unless you have specific carrier preferences
export CELLULAR_CARRIER_PREFERENCES="operator1 operator2"

# --- Cellular Analytics and Logging ---
# Data collection and analysis features for cellular performance

# Enable comprehensive analytics
# What it provides: Detailed cellular performance analysis, trend tracking
# Benefits: Understanding cellular backup reliability and performance patterns
# Impact: Additional processing and log storage for analytics
# Recommended: true for mobile installations and performance analysis
export CELLULAR_ANALYTICS_ENABLED="true"

# Log detailed signal information
# What it includes: Full signal metrics (RSSI, RSRQ, SINR, cell tower IDs)
# Benefits: Detailed troubleshooting and coverage analysis
# Impact: Significantly larger log files with technical cellular data
# Recommended: true for performance analysis, false for basic monitoring
export CELLULAR_LOG_SIGNAL_DETAILS="true"

# Track cell tower handoffs (1=enabled, 0=disabled)
# What it monitors: When device switches between cell towers
# Benefits: Understanding coverage patterns, detecting connectivity issues
# Impact: Additional processing to track tower changes
# Recommended: 0 for basic use, 1 for detailed mobile coverage analysis
export CELLULAR_TRACK_HANDOFFS="0"

# Score performance for intelligent switching (1=enabled, 0=disabled)
# What it does: Maintains performance scores for each cellular connection
# Benefits: Historical performance data improves future failover decisions
# Impact: Additional processing and memory for performance tracking
# Recommended: 0 for simple setups, 1 for advanced multi-carrier optimization
export CELLULAR_PERFORMANCE_SCORING="0"

# Generate periodic analytics reports (1=enabled, 0=disabled)
# What it creates: Regular summary reports of cellular performance and usage
# Benefits: Regular insights into cellular backup performance and costs
# Impact: Additional processing for report generation
# Recommended: 0 for basic monitoring, 1 for regular performance review
export CELLULAR_GENERATE_REPORTS="0"

# --- Cellular Decision Engine ---
# Advanced algorithms for intelligent cellular failover decisions

# Decision algorithm type
# Available algorithms:
#   "simple" - Basic signal strength and availability
#   "weighted" - Signal strength, cost, and performance weighted
#   "multi_factor" - Comprehensive analysis including location, time, usage patterns
# Complexity: simple < weighted < multi_factor
# Recommended: "simple" for basic setups, "weighted" for cost-conscious users
export CELLULAR_DECISION_ALGORITHM="simple"

# Algorithm weighting (only used with "weighted" and "multi_factor" algorithms)
# Total should add up to 100% for balanced decision making

# Signal strength weight in decisions (percentage)
# How much signal quality affects failover decisions
# Higher values = prioritize signal quality over other factors
# Recommended: 40% (important but balanced with other factors)
export CELLULAR_SIGNAL_WEIGHT="40"

# Cost consideration weight (percentage)
# How much cost factors into failover decisions
# Higher values = more cost-conscious (avoid expensive connections)
# Recommended: 30% (significant but not overwhelming factor)
export CELLULAR_COST_WEIGHT="30"

# Historical performance weight (percentage)
# How much past performance affects current decisions
# Higher values = more influenced by historical data
# Recommended: 30% (balanced consideration of past performance)
export CELLULAR_PERFORMANCE_WEIGHT="30"

# ==============================================================================
# 5. ADVANCED SYSTEM CONFIGURATION
# ==============================================================================
# Performance optimization, security, and advanced system management.
# These settings are for users who want to fine-tune system behavior and
# implement advanced features like security hardening and performance monitoring.

# --- Performance Settings ---
# Control system resource usage and performance monitoring

# Alert if any script takes longer than this (seconds)
# What it monitors: Execution time of monitoring and logging scripts
# Purpose: Detect system performance degradation or script hanging
# Balance: Too low = false alerts during system load, too high = miss real issues
# Recommended: 30 seconds (allows for temporary system load but catches real issues)
export MAX_EXECUTION_TIME_SECONDS="30"

# Rate limiting for high-load scenarios (samples per second)
# What it controls: Maximum data processing rate to prevent system overload
# Purpose: Prevents system overwhelm during data catch-up or high-frequency monitoring
# Impact: Higher values = faster processing but more system load
# Recommended: 10 samples/second (adequate for router hardware capabilities)
export MAX_SAMPLES_PER_SECOND="10"

# Alert threshold for execution time (seconds)
# What it does: Send notifications when script execution exceeds this threshold
# Purpose: Early warning of performance issues before they become critical
# Balance: Should be less than MAX_EXECUTION_TIME_SECONDS for early warning
# Recommended: 15 seconds (half of max execution time for advance notice)
export PERFORMANCE_ALERT_THRESHOLD="15"

# --- Security Settings ---
# Enhanced security features for protecting the monitoring system

# Rate limit API calls to prevent abuse (1=enabled, 0=disabled)
# What it does: Limits frequency of Starlink API calls to prevent overwhelming service
# Benefits: Protects against accidental API abuse, ensures service availability
# Impact: May slightly delay some monitoring functions during high activity
# Recommended: 1 (good practice for API interaction)
export ENABLE_API_RATE_LIMITING="1"

# Encrypt sensitive log data (1=enabled, 0=disabled)
# What it protects: Encrypts logs containing sensitive information (if any)
# Benefits: Protects against data exposure if logs are compromised
# Impact: Additional processing overhead for encryption/decryption
# Recommended: 0 for normal use (minimal sensitive data), 1 for high-security environments
export ENABLE_SECURE_LOGGING="0"

# Verify script integrity (1=enabled, 0=disabled)
# What it does: Checks that monitoring scripts haven't been tampered with
# Benefits: Protects against unauthorized script modification
# Impact: Additional processing overhead for integrity verification
# Recommended: 0 for trusted environments, 1 for high-security installations
export ENABLE_INTEGRITY_CHECKS="0"

# --- Advanced Data Management ---
# Features for managing monitoring data and system optimization

# Log detailed performance metrics (1=enabled, 0=disabled)
# What it adds: Detailed timing, resource usage, and performance data to logs
# Benefits: Comprehensive performance analysis and troubleshooting data
# Impact: Significantly larger log files with detailed metrics
# Recommended: 0 for normal use, 1 for performance analysis and troubleshooting
export ENABLE_PERFORMANCE_LOGGING="0"

# Optimize log files automatically (1=enabled, 0=disabled)
# What it does: Automatic compression, cleanup, and optimization of log files
# Benefits: Prevents log files from consuming excessive disk space
# Impact: Periodic processing overhead for optimization tasks
# Recommended: 1 (essential for long-term operation on routers with limited storage)
export ENABLE_DATABASE_OPTIMIZATION="1"

# Location for configuration backups
# What it stores: Automatic backups of configuration files before updates
# Purpose: Enable rollback if configuration updates cause issues
# Storage consideration: Requires disk space for backup retention
# Recommended: Default location unless specific backup strategy required
export BACKUP_DIR="/etc/starlink-backups"

# --- Data Limits and Thresholds ---
# Monitoring and alerting for data usage limits (important for cellular backup)

# Warn when approaching data limits (percentage)
# What it monitors: Data usage approaching plan limits on cellular connections
# Purpose: Early warning before hitting expensive overage charges
# When important: Metered cellular plans, international roaming
# Recommended: 80% (provides advance warning with time to adjust usage)
export DATA_LIMIT_WARNING_THRESHOLD="80"

# Critical alert threshold (percentage)
# What it triggers: Urgent notification when very close to data limits
# Purpose: Final warning before potential service cutoff or expensive overages
# Action: May trigger automatic traffic reduction or failover changes
# Recommended: 95% (last chance warning before limit reached)
export DATA_LIMIT_CRITICAL_THRESHOLD="95"

# --- Advanced Notification Settings ---
# Fine-tuned control over notification behavior (separate from main notification settings)

# Critical notification threshold (number of issues)
# What it controls: How many critical issues before sending emergency notification
# Purpose: Avoid emergency notifications for single issues
# Balance: Too high = miss urgent problems, too low = false emergency alerts
# Recommended: 1 (immediate notification of any critical issue)
export MAINTENANCE_CRITICAL_THRESHOLD="1"

# Batch multiple notifications (true/false)
# What it does: Combines multiple related notifications into single message
# Benefits: Reduces notification spam while maintaining information
# Impact: May delay individual notifications to batch them together
# Recommended: false (immediate notifications for real-time awareness)
export MAINTENANCE_BATCH_NOTIFICATIONS="false"

# Cooldown between notifications (seconds)
# What it prevents: Notification spam from repeated issues
# Purpose: Balance between staying informed and avoiding notification overload
# Calculation: 3600 seconds = 1 hour
# Recommended: 3600 (hourly updates for ongoing issues)

# ==============================================================================
# 6. EXPERT/DEBUG CONFIGURATION
# ==============================================================================
# Developer settings, debugging options, and experimental features.
# Only modify these settings if you understand their implications.
# These are primarily for troubleshooting, development, and advanced system analysis.

# --- Debug Settings ---
# Control debugging features and diagnostic output

# Debug mode (1=enabled, 0=disabled)
# What it enables: Extensive debug output from all monitoring scripts
# Impact: Significantly more verbose logging, larger log files
# When to use: Troubleshooting connectivity issues, script problems
# Recommended: 0 for normal operation, 1 only when troubleshooting
export DEBUG_MODE="0"

# Dry run mode (1=simulate actions, 0=perform actions)
# What it does: Simulates all actions without making actual changes
# Purpose: Test configuration changes without affecting system
# When useful: Testing new configurations, troubleshooting logic issues
# Recommended: 0 for normal operation, 1 for testing changes safely
export DRY_RUN="0"

# Debug configuration loading (1=enabled, 0=disabled)
# What it shows: Detailed information about configuration file processing
# Purpose: Troubleshoot configuration loading issues and variable inheritance
# When needed: Configuration not taking effect, variable conflicts
# Recommended: 0 normally, 1 when debugging configuration issues
export CONFIG_DEBUG="0"

# RUTOS test mode (1=enabled, 0=disabled)
# What it does: Enhanced validation and test mode for RUTOS compatibility
# Purpose: Comprehensive testing of script functionality in RUTOS environment
# When used: Development, validation, compatibility testing
# Recommended: 0 for production, 1 for development and testing
export RUTOS_TEST_MODE="0"

# --- Logging Verbosity Control ---
# Fine-grained control over logging detail and output

# Overall log level
# Controls the minimum severity level for log messages
# Levels: ERROR (only errors), WARN (warnings+errors), INFO (general info+above),
#         DEBUG (detailed debug+above), TRACE (everything)
# Impact: Higher levels = much more verbose logging
# Recommended: INFO for normal operation, DEBUG for troubleshooting
export LOG_LEVEL="INFO"

# Enable trace logging (1=enabled, 0=disabled)
# What it adds: Extremely detailed trace information including function entry/exit
# Purpose: Deep debugging of script execution flow
# Impact: Massive log files with very detailed execution traces
# Recommended: 0 normally (extremely verbose), 1 only for deep debugging
export ENABLE_TRACE_LOGGING="0"

# Debug cellular command execution (1=enabled, 0=disabled)
# What it shows: Detailed logging of all cellular modem commands and responses
# Purpose: Troubleshoot cellular modem communication issues
# Impact: Large amount of technical cellular debug data in logs
# Recommended: 0 normally, 1 when debugging cellular connectivity issues
export DEBUG_CELLULAR_COMMANDS="0"

# Debug GPS data collection (1=enabled, 0=disabled)
# What it shows: Detailed GPS data collection process and raw GPS data
# Purpose: Troubleshoot GPS functionality and data quality issues
# Impact: Additional GPS technical data in logs
# Recommended: 0 normally, 1 when debugging GPS functionality
export DEBUG_GPS_COLLECTION="0"

# --- Experimental Features ---
# Cutting-edge features that may not be fully stable

# Enable experimental functionality (1=enabled, 0=disabled)
# What it unlocks: Access to experimental features not yet in stable release
# Risks: Potential instability, unexpected behavior, possible data issues
# Benefits: Early access to new features and capabilities
# Recommended: 0 for production systems, 1 for development/testing environments
export ENABLE_EXPERIMENTAL_FEATURES="0"

# Comma-separated list of experimental features to enable
# Purpose: Selectively enable specific experimental features
# Format: "feature1,feature2,feature3" (no spaces)
# Available features: Depends on current development - check documentation
# Usage: Only used when ENABLE_EXPERIMENTAL_FEATURES="1"
export EXPERIMENTAL_FEATURE_LIST=""

# --- Development Settings ---
# Settings specifically for development and testing environments

# Development mode (1=enabled, 0=disabled)
# What it changes: Relaxed validation, additional development tools
# Purpose: Easier development and testing of new features
# Impact: May bypass some safety checks for development convenience
# Recommended: 0 for production, 1 for development environments only
export DEV_MODE="0"

# Test API endpoints before using (1=enabled, 0=disabled)
# What it does: Validates API endpoints are reachable before making actual calls
# Benefits: Early detection of API connectivity issues
# Impact: Additional network requests for validation
# Recommended: 0 for normal operation, 1 for unreliable network environments
export TEST_API_ENDPOINTS="0"

# Use mock responses for testing (1=enabled, 0=disabled)
# What it does: Uses simulated responses instead of real Starlink/cellular data
# Purpose: Testing script logic without requiring actual hardware
# When useful: Development, unit testing, demonstration environments
# Recommended: 0 for production (requires real data), 1 for testing only
export MOCK_HARDWARE_RESPONSES="0"

# ==============================================================================
# UNIFIED SCRIPTS ENHANCED FEATURES CONFIGURATION
# ==============================================================================
# These settings control enhanced features in the unified monitor and logger scripts.
# All features default to 'false' to maintain backward compatibility with basic scripts.
# Enable features selectively based on your installation requirements.

# --- MONITORING ENHANCEMENTS ---

# Enable GPS tracking for location-aware monitoring decisions
# What it adds: Location context to monitoring decisions and analytics
# Benefits: Better mobile setup support, location-based performance analysis
# Requirements: GPS_ENABLED=1 must also be set for this to function
# Recommended: false for stationary, true for mobile installations
export ENABLE_GPS_TRACKING="false"

# Enable cellular data collection for backup intelligence
# What it adds: Cellular signal monitoring integrated with Starlink monitoring
# Benefits: Smarter failover decisions based on cellular backup quality
# Requirements: CELLULAR_ENABLED=1 must also be set for this to function
# Recommended: false for Starlink-only, true for cellular backup setups
export ENABLE_CELLULAR_TRACKING="false"

# Enable multi-source GPS (RUTOS + Starlink + cellular estimation)
# What it adds: GPS data fusion from multiple sources for improved accuracy
# Benefits: Better location accuracy, redundancy if one GPS source fails
# Requirements: Multiple GPS sources available on the system
# Recommended: false for single GPS source, true for systems with multiple GPS sources
export ENABLE_MULTI_SOURCE_GPS="false"

# Enable enhanced failover logic (considers GPS + cellular + multiple factors)
# What it adds: Sophisticated failover decisions beyond basic quality thresholds
# Benefits: Smarter failover for mobile setups, cost-aware decisions
# Requirements: GPS and/or cellular tracking enabled for full functionality
# Recommended: false for basic setups, true for advanced mobile installations
export ENABLE_ENHANCED_FAILOVER="false"

# --- LOGGING ENHANCEMENTS ---

# Enable GPS data logging in CSV files
# What it adds: GPS coordinates, movement data, and location analytics in logs
# Benefits: Location-based performance analysis, travel tracking
# Impact: Additional log file storage for GPS data
# Recommended: false for stationary, true for mobile setups needing location data
export ENABLE_GPS_LOGGING="false"

# Enable cellular data logging (signal strength, operator, network type)
# What it adds: Detailed cellular backup performance data in logs
# Benefits: Cellular backup analysis, signal quality tracking
# Impact: Additional log file storage for cellular metrics
# Recommended: false for Starlink-only, true for cellular backup analysis
export ENABLE_CELLULAR_LOGGING="false"

# Enable enhanced metrics (SNR, reboot detection, GPS stats)
# What it adds: Signal-to-noise ratio, system reboot tracking, GPS quality metrics
# Benefits: Better troubleshooting data, system health monitoring
# Impact: Slightly larger log files with additional technical metrics
# Recommended: false for basic logging, true for comprehensive system monitoring
export ENABLE_ENHANCED_METRICS="false"

# Enable statistical data aggregation (60:1 data reduction for long-term analytics)
# What it does: Aggregates raw data into statistical summaries for long-term storage
# Benefits: Enables long-term trend analysis without massive log files
# How it works: 60 raw samples → 1 statistical record (min, max, avg, std dev)
# Recommended: false for short-term monitoring, true for long-term analytics
export ENABLE_STATISTICAL_AGGREGATION="false"

# Aggregation batch size (number of raw samples to aggregate into one record)
# Controls granularity of statistical aggregation
# Common values: 60 = hourly summaries, 30 = 15-minute summaries, 120 = 2-hour summaries
# Impact: Higher values = more compression but less granular historical data
# Recommended: 60 (1-hour aggregation for good balance of detail vs storage)
export AGGREGATION_BATCH_SIZE="60"

# =============================================================================
# UNIFIED SCRIPTS CONFIGURATION EXAMPLES
# =============================================================================
# Uncomment and modify one of these example configurations to quickly enable
# feature sets appropriate for different installation types:

# Example 1: Basic Installation (DEFAULT - all enhanced features disabled)
# Best for: Simple stationary installations, minimal resource usage
# Uses original script behavior - no changes needed, all defaults work
# ENABLE_GPS_TRACKING="false"
# ENABLE_CELLULAR_TRACKING="false"
# ENABLE_MULTI_SOURCE_GPS="false"
# ENABLE_ENHANCED_FAILOVER="false"
# ENABLE_GPS_LOGGING="false"
# ENABLE_CELLULAR_LOGGING="false"
# ENABLE_ENHANCED_METRICS="false"
# ENABLE_STATISTICAL_AGGREGATION="false"

# Example 2: Enhanced Stationary Installation
# Best for: Fixed installations wanting better metrics and some GPS tracking
# Features: Better metrics and GPS tracking without cellular complexity
# ENABLE_GPS_TRACKING="true"
# ENABLE_CELLULAR_TRACKING="false"
# ENABLE_MULTI_SOURCE_GPS="false"
# ENABLE_ENHANCED_FAILOVER="false"
# ENABLE_GPS_LOGGING="true"
# ENABLE_CELLULAR_LOGGING="false"
# ENABLE_ENHANCED_METRICS="true"
# ENABLE_STATISTICAL_AGGREGATION="true"

# Example 3: Mobile/RV Installation (full features)
# Best for: RVs, boats, vehicles - mobile installations needing all features
# Features: All enhanced features for comprehensive mobile monitoring
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
# Best for: Users prioritizing data collection and analysis over real-time features
# Features: Emphasis on comprehensive data collection and aggregation
# ENABLE_GPS_TRACKING="true"
# ENABLE_CELLULAR_TRACKING="true"
# ENABLE_MULTI_SOURCE_GPS="true"
# ENABLE_ENHANCED_FAILOVER="false"  # Focus on data collection over smart failover
# ENABLE_GPS_LOGGING="true"
# ENABLE_CELLULAR_LOGGING="true"
# ENABLE_ENHANCED_METRICS="true"
# ENABLE_STATISTICAL_AGGREGATION="true"
# AGGREGATION_BATCH_SIZE="30"  # More frequent aggregation for detailed trends

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
