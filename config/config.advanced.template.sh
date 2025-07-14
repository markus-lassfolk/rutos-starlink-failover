#!/bin/sh
# shellcheck disable=SC2034  # Variables are used when sourced by other scripts

# ==============================================================================
# STARLINK MONITOR ADVANCED CONFIGURATION TEMPLATE
# ==============================================================================
# This is an advanced template file for the Starlink monitoring system.
# Copy this file to config.sh and edit the values below.
#
# Template Version: 1.0.0
# Compatible with install.sh: 1.0.0
# ==============================================================================

# --- Network Configuration ---

# Starlink connection settings
STARLINK_IP="192.168.100.1:9200" # Standard Starlink gRPC endpoint
STARLINK_MANAGEMENT_IP="192.168.100.1" # Starlink management interface

# MWAN3 interface mapping (based on your config)
MWAN_IFACE="wan" # Starlink interface (network.wan)
MWAN_MEMBER="member1" # Starlink member (metric=1, highest priority)

# Cellular backup interfaces (matching your setup)
CELLULAR_PRIMARY_IFACE="mob1s1a1" # Primary SIM (Telia)
CELLULAR_PRIMARY_MEMBER="member3" # metric=2
CELLULAR_BACKUP_IFACE="mob1s2a1" # Backup SIM (Roaming)
CELLULAR_BACKUP_MEMBER="member4" # metric=4

# --- Real-world Thresholds (based on mobile environment) ---

# Packet loss thresholds for mobile environment (0.0-1.0, where 0.08 = 8%)
# Mobile/satellite connections typically have higher acceptable packet loss
PACKET_LOSS_THRESHOLD=0.08 # 8% - more tolerant for mobile (triggers soft failover)
PACKET_LOSS_CRITICAL=0.15 # 15% - trigger immediate hard failover

# Obstruction thresholds for moving vehicles (0.0-1.0, where 0.002 = 0.2%)
# Obstructions are common when moving (bridges, tunnels, trees)
OBSTRUCTION_THRESHOLD=0.002 # 0.2% - sensitive for RV/boat (triggers monitoring)
OBSTRUCTION_CRITICAL=0.005 # 0.5% - immediate failover (unusable)

# Latency thresholds for real-time applications (in milliseconds)
# Satellite connections have inherent latency (~500-600ms to internet)
LATENCY_THRESHOLD_MS=200 # 200ms - realistic for satellite (above normal)
LATENCY_CRITICAL_MS=500 # 500ms - unusable for most apps (immediate failover)

# Signal strength monitoring (matches your cellular config)
# RSSI values: -70 dBm (excellent) to -120 dBm (no signal)
SIGNAL_RESET_THRESHOLD=-90 # dBm - reset modem when signal drops below this
SIGNAL_RESET_TIMEOUT=600 # seconds - wait 10 minutes between resets

# --- Notification Settings ---

# Pushover API credentials for notifications
# Get your token from: https://pushover.net/apps/build
# Get your user key from: https://pushover.net/
PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

# Enhanced notification control (1=enabled, 0=disabled)
# 
# CRITICAL: System failures, API errors, connection completely lost
NOTIFY_ON_CRITICAL=1 # Always notify on critical errors (recommended: 1)
# 
# SOFT_FAIL: Starlink degraded but still usable (high latency, packet loss)
NOTIFY_ON_SOFT_FAIL=1 # Notify on soft failover events (recommended: 1)
# 
# HARD_FAIL: Starlink completely down, switched to cellular backup
NOTIFY_ON_HARD_FAIL=1 # Notify on hard failover events (recommended: 1)
# 
# RECOVERY: Starlink recovered, switched back from cellular
NOTIFY_ON_RECOVERY=1 # Notify when system recovers (recommended: 1)
# 
# SIGNAL_RESET: Cellular modem reset due to poor signal
NOTIFY_ON_SIGNAL_RESET=1 # Notify on cellular signal resets (mobile-specific)
# 
# SIM_SWITCH: Switched between primary and backup SIM cards
NOTIFY_ON_SIM_SWITCH=1 # Notify on SIM card switches (dual-SIM feature)
# 
# GPS_STATUS: GPS lock status changes, movement detection
NOTIFY_ON_GPS_STATUS=0 # GPS status changes (0=quiet, 1=verbose)

# Rate limiting to prevent notification spam in mobile environment
NOTIFICATION_COOLDOWN=300 # Seconds between similar notifications (5 minutes)
MAX_NOTIFICATIONS_PER_HOUR=12 # Maximum notifications per hour

# --- Failover Behavior ---

# Stability requirements before failback (important for mobile)
STABILITY_WAIT_TIME=30 # Wait 30s before failback
STABILITY_CHECK_COUNT=6 # Require 6 consecutive good checks
STABILITY_CHECK_INTERVAL=10 # Check every 10 seconds

# Recovery behavior
RECOVERY_WAIT_TIME=10 # Match your mwan3.wan.recovery_wait
ENABLE_SOFT_FAILOVER=1 # Preserve existing connections
ENABLE_CONNTRACK_FLUSH=1 # Match your flush_conntrack settings

# --- GPS Integration (based on your GPS config) ---

# GPS monitoring for location-aware failover
ENABLE_GPS_MONITORING=1 # Use GPS for location awareness
GPS_ACCURACY_THRESHOLD=10 # 10m accuracy (match your avl config)
MOVEMENT_DETECTION_DISTANCE=50 # 50m movement threshold (your avl setting)
STARLINK_OBSTRUCTION_RESET_DISTANCE=500 # Reset obstruction map after 500m

# --- Advanced Monitoring ---

# Health check configuration (matching your ping_reboot settings)
HEALTH_CHECK_INTERVAL=60 # 60s interval (match ping_reboot)
HEALTH_CHECK_TIMEOUT=5 # 5s timeout (match your setting)
HEALTH_CHECK_FAILURES=60 # 60 failures before action (your retry)

# Performance logging
ENABLE_PERFORMANCE_LOGGING=1 # Log performance metrics
LOG_RETENTION_DAYS=7 # Keep logs for 7 days
LOG_ROTATION_SIZE="10M" # Rotate logs at 10MB

# --- Integration Settings ---

# MQTT integration (based on your MQTT config)
ENABLE_MQTT_LOGGING=0 # Set to 1 if using MQTT
MQTT_BROKER="192.168.80.242" # Your MQTT broker IP
MQTT_PORT=1883 # Standard MQTT port
MQTT_TOPIC_PREFIX="starlink" # Topic prefix for Starlink data

# RMS integration (for remote monitoring)
ENABLE_RMS_INTEGRATION=0 # Set to 1 if using Teltonika RMS
RMS_DEVICE_ID="your_rms_device_id" # Your RMS device identifier

# --- Cellular Optimization ---

# SIM management (based on your sim_switch config)
ENABLE_AUTO_SIM_SWITCH=1 # Enable automatic SIM switching
SIM_SWITCH_SIGNAL_THRESHOLD=-85 # Switch SIM if signal < -85dBm
SIM_SWITCH_COOLDOWN=1800 # 30 minutes before switching back

# Data limit awareness (based on your quota_limit config)
ENABLE_DATA_LIMIT_CHECK=0 # Set to 1 if using data limits
DATA_LIMIT_WARNING_THRESHOLD=0.8 # Warn at 80% usage
DATA_LIMIT_FAILOVER_THRESHOLD=0.95 # Failover at 95% usage

# --- Debugging and Development ---

# Logging levels (match your system.debug config)
LOG_LEVEL=7 # Match your system.system.log_level
DEBUG_MODE=0 # Set to 1 for verbose debugging
ENABLE_API_LOGGING=0 # Log all Starlink API calls

# Test mode settings
TEST_MODE=0 # Set to 1 for testing without actions
DRY_RUN=0 # Set to 1 to log actions without executing

# --- File Paths and Storage ---

# System directories for persistent storage
# NOTE: /var/log is wiped on reboot in OpenWrt/RUTOS - use /overlay/ for persistence
STATE_DIR="/tmp/run"                    # Runtime state files (temporary)
LOG_DIR="/overlay/starlink-logs"        # Log files directory (persistent across reboots)
DATA_DIR="/overlay/starlink-data"       # Data storage directory (persistent across reboots)
BACKUP_DIR="/overlay/starlink-backups"  # Configuration backups (persistent)

# Binary paths (set by install script)
GRPCURL_CMD="/root/grpcurl"             # gRPC client for Starlink API
JQ_CMD="/root/jq"                       # JSON processor

# --- RUTOS API Configuration ---

# RUTX50 router management interface
RUTOS_IP="192.168.80.1"                # Router LAN IP (standard RUTX50)
RUTOS_USERNAME="YOUR_RUTOS_USERNAME"    # Router admin username
RUTOS_PASSWORD="YOUR_RUTOS_PASSWORD"    # Router admin password

# ==============================================================================
# Advanced Feature Flags
# ==============================================================================

# Experimental features
ENABLE_PREDICTIVE_FAILOVER=0 # AI-based failover prediction
ENABLE_LOAD_BALANCING=0 # Intelligent load balancing
ENABLE_BANDWIDTH_MONITORING=1 # Monitor bandwidth usage

# Security enhancements
ENABLE_API_RATE_LIMITING=1 # Rate limit API calls
ENABLE_SECURE_LOGGING=1 # Encrypt sensitive log data
ENABLE_INTEGRITY_CHECKS=1 # Verify script integrity

# ==============================================================================
# End of Configuration
# ==============================================================================
