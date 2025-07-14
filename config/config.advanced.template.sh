#!/bin/bash

# ==============================================================================
# Advanced Configuration Template for Starlink RUTOS Failover
# Based on real-world RUTX50 production configuration analysis
#
# This template includes settings derived from actual deployment configurations
# Copy this file to config.sh and customize the values for your setup.
# ==============================================================================

# --- Network Configuration ---

# Starlink connection settings
# shellcheck disable=SC2034
STARLINK_IP="192.168.100.1:9200" # Standard Starlink gRPC endpoint
# shellcheck disable=SC2034
STARLINK_MANAGEMENT_IP="192.168.100.1" # Starlink management interface

# MWAN3 interface mapping (based on your config)
# shellcheck disable=SC2034
MWAN_IFACE="wan" # Starlink interface (network.wan)
# shellcheck disable=SC2034
MWAN_MEMBER="member1" # Starlink member (metric=1, highest priority)

# Cellular backup interfaces (matching your setup)
# shellcheck disable=SC2034
CELLULAR_PRIMARY_IFACE="mob1s1a1" # Primary SIM (Telia)
# shellcheck disable=SC2034
CELLULAR_PRIMARY_MEMBER="member3" # metric=2
# shellcheck disable=SC2034
CELLULAR_BACKUP_IFACE="mob1s2a1" # Backup SIM (Roaming)
# shellcheck disable=SC2034
CELLULAR_BACKUP_MEMBER="member4" # metric=4

# --- Real-world Thresholds (based on mobile environment) ---

# Packet loss thresholds for mobile environment
# shellcheck disable=SC2034
PACKET_LOSS_THRESHOLD=0.08 # 8% - more tolerant for mobile
# shellcheck disable=SC2034
PACKET_LOSS_CRITICAL=0.15 # 15% - trigger immediate failover

# Obstruction thresholds for moving vehicles
# shellcheck disable=SC2034
OBSTRUCTION_THRESHOLD=0.002 # 0.2% - sensitive for RV/boat
# shellcheck disable=SC2034
OBSTRUCTION_CRITICAL=0.005 # 0.5% - immediate failover

# Latency thresholds for real-time applications
# shellcheck disable=SC2034
LATENCY_THRESHOLD_MS=200 # 200ms - realistic for satellite
# shellcheck disable=SC2034
LATENCY_CRITICAL_MS=500 # 500ms - unusable for most apps

# Signal strength monitoring (from your cellular config)
# shellcheck disable=SC2034
SIGNAL_RESET_THRESHOLD=-90 # Match your simcard config
# shellcheck disable=SC2034
SIGNAL_RESET_TIMEOUT=600 # 10 minutes (your setting)

# --- Notification Settings ---

# Pushover configuration
# shellcheck disable=SC2034
PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
# shellcheck disable=SC2034
PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

# Enhanced notification control
# shellcheck disable=SC2034
NOTIFY_ON_CRITICAL=1 # Always notify on critical errors
# shellcheck disable=SC2034
NOTIFY_ON_SOFT_FAIL=1 # Notify on soft failover events
# shellcheck disable=SC2034
NOTIFY_ON_HARD_FAIL=1 # Notify on hard failover events
# shellcheck disable=SC2034
NOTIFY_ON_RECOVERY=1 # Notify when system recovers
# shellcheck disable=SC2034
NOTIFY_ON_SIGNAL_RESET=1 # Notify on cellular signal resets
# shellcheck disable=SC2034
NOTIFY_ON_SIM_SWITCH=1 # Notify on SIM card switches
# shellcheck disable=SC2034
NOTIFY_ON_GPS_STATUS=0 # GPS status changes (optional)

# Rate limiting (prevent notification spam in mobile environment)
# shellcheck disable=SC2034
NOTIFICATION_COOLDOWN=300 # 5 minutes between similar notifications
# shellcheck disable=SC2034
MAX_NOTIFICATIONS_PER_HOUR=12 # Prevent spam during poor coverage

# --- Failover Behavior ---

# Stability requirements before failback (important for mobile)
# shellcheck disable=SC2034
STABILITY_WAIT_TIME=30 # Wait 30s before failback
# shellcheck disable=SC2034
STABILITY_CHECK_COUNT=6 # Require 6 consecutive good checks
# shellcheck disable=SC2034
STABILITY_CHECK_INTERVAL=10 # Check every 10 seconds

# Recovery behavior
# shellcheck disable=SC2034
RECOVERY_WAIT_TIME=10 # Match your mwan3.wan.recovery_wait
# shellcheck disable=SC2034
ENABLE_SOFT_FAILOVER=1 # Preserve existing connections
# shellcheck disable=SC2034
ENABLE_CONNTRACK_FLUSH=1 # Match your flush_conntrack settings

# --- GPS Integration (based on your GPS config) ---

# GPS monitoring for location-aware failover
# shellcheck disable=SC2034
ENABLE_GPS_MONITORING=1 # Use GPS for location awareness
# shellcheck disable=SC2034
GPS_ACCURACY_THRESHOLD=10 # 10m accuracy (match your avl config)
# shellcheck disable=SC2034
MOVEMENT_DETECTION_DISTANCE=50 # 50m movement threshold (your avl setting)
# shellcheck disable=SC2034
STARLINK_OBSTRUCTION_RESET_DISTANCE=500 # Reset obstruction map after 500m

# --- Advanced Monitoring ---

# Health check configuration (matching your ping_reboot settings)
# shellcheck disable=SC2034
HEALTH_CHECK_INTERVAL=60 # 60s interval (match ping_reboot)
# shellcheck disable=SC2034
HEALTH_CHECK_TIMEOUT=5 # 5s timeout (match your setting)
# shellcheck disable=SC2034
HEALTH_CHECK_FAILURES=60 # 60 failures before action (your retry)

# Performance logging
# shellcheck disable=SC2034
ENABLE_PERFORMANCE_LOGGING=1 # Log performance metrics
# shellcheck disable=SC2034
LOG_RETENTION_DAYS=7 # Keep logs for 7 days
# shellcheck disable=SC2034
LOG_ROTATION_SIZE="10M" # Rotate logs at 10MB

# --- Integration Settings ---

# MQTT integration (based on your MQTT config)
# shellcheck disable=SC2034
ENABLE_MQTT_LOGGING=0 # Set to 1 if using MQTT
# shellcheck disable=SC2034
MQTT_BROKER="192.168.80.242" # Your MQTT broker IP
# shellcheck disable=SC2034
MQTT_PORT=1883 # Standard MQTT port
# shellcheck disable=SC2034
MQTT_TOPIC_PREFIX="starlink" # Topic prefix for Starlink data

# RMS integration (for remote monitoring)
# shellcheck disable=SC2034
ENABLE_RMS_INTEGRATION=0 # Set to 1 if using Teltonika RMS
# shellcheck disable=SC2034
RMS_DEVICE_ID="your_rms_device_id" # Your RMS device identifier

# --- Cellular Optimization ---

# SIM management (based on your sim_switch config)
# shellcheck disable=SC2034
ENABLE_AUTO_SIM_SWITCH=1 # Enable automatic SIM switching
# shellcheck disable=SC2034
SIM_SWITCH_SIGNAL_THRESHOLD=-85 # Switch SIM if signal < -85dBm
# shellcheck disable=SC2034
SIM_SWITCH_COOLDOWN=1800 # 30 minutes before switching back

# Data limit awareness (based on your quota_limit config)
# shellcheck disable=SC2034
ENABLE_DATA_LIMIT_CHECK=0 # Set to 1 if using data limits
# shellcheck disable=SC2034
DATA_LIMIT_WARNING_THRESHOLD=0.8 # Warn at 80% usage
# shellcheck disable=SC2034
DATA_LIMIT_FAILOVER_THRESHOLD=0.95 # Failover at 95% usage

# --- Debugging and Development ---

# Logging levels (match your system.debug config)
# shellcheck disable=SC2034
LOG_LEVEL=7 # Match your system.system.log_level
# shellcheck disable=SC2034
DEBUG_MODE=0 # Set to 1 for verbose debugging
# shellcheck disable=SC2034
ENABLE_API_LOGGING=0 # Log all Starlink API calls

# Test mode settings
# shellcheck disable=SC2034
TEST_MODE=0 # Set to 1 for testing without actions
# shellcheck disable=SC2034
DRY_RUN=0 # Set to 1 to log actions without executing

# ==============================================================================
# Advanced Feature Flags
# ==============================================================================

# Experimental features
# shellcheck disable=SC2034
ENABLE_PREDICTIVE_FAILOVER=0 # AI-based failover prediction
# shellcheck disable=SC2034
ENABLE_LOAD_BALANCING=0 # Intelligent load balancing
# shellcheck disable=SC2034
ENABLE_BANDWIDTH_MONITORING=1 # Monitor bandwidth usage

# Security enhancements
# shellcheck disable=SC2034
ENABLE_API_RATE_LIMITING=1 # Rate limit API calls
# shellcheck disable=SC2034
ENABLE_SECURE_LOGGING=1 # Encrypt sensitive log data
# shellcheck disable=SC2034
ENABLE_INTEGRITY_CHECKS=1 # Verify script integrity

# ==============================================================================
# End of Configuration
# ==============================================================================
