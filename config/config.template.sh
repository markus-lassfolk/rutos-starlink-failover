#!/bin/sh

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
export NOTIFY_ON_CRITICAL=1  # Critical errors (recommended: 1)
export NOTIFY_ON_HARD_FAIL=1 # Complete failures (recommended: 1)
export NOTIFY_ON_RECOVERY=1  # System recovery (recommended: 1)
export NOTIFY_ON_SOFT_FAIL=0 # Degraded performance (0=disabled for basic setup)
export NOTIFY_ON_INFO=0      # Status updates (0=disabled for basic setup)

# --- Basic Failover Thresholds ---

# Packet loss threshold (percentage as decimal: 0.05 = 5%)
export PACKET_LOSS_THRESHOLD=0.05

# Obstruction threshold (percentage as decimal: 0.001 = 0.1%)
export OBSTRUCTION_THRESHOLD=0.001

# Latency threshold in milliseconds
export LATENCY_THRESHOLD_MS=150

# --- System Settings ---

# Check interval in seconds (how often to test Starlink)
export CHECK_INTERVAL=30

# API timeout in seconds
export API_TIMEOUT=10

# Directory for log files (persistent across reboots)
export LOG_DIR="/etc/starlink-logs"

# Directory for runtime state files
export STATE_DIR="/tmp/run"

# Log retention in days (how long to keep log files)
export LOG_RETENTION_DAYS=7

# Syslog tag for log messages (shown in system logs)
export LOG_TAG="StarlinkMonitor"

# --- System Maintenance Configuration ---

# Enable Pushover notifications for critical maintenance issues
export MAINTENANCE_PUSHOVER_ENABLED="true"  # Uses PUSHOVER_TOKEN/PUSHOVER_USER if not overridden

# Optional: Override Pushover credentials specifically for maintenance (leave empty to use main settings)
export MAINTENANCE_PUSHOVER_TOKEN=""  # Leave empty to use PUSHOVER_TOKEN
export MAINTENANCE_PUSHOVER_USER=""   # Leave empty to use PUSHOVER_USER

# Number of critical issues before sending notification (default: 3)
export MAINTENANCE_CRITICAL_THRESHOLD=3

# Notification cooldown in seconds - prevents spam (default: 3600 = 1 hour)
export MAINTENANCE_NOTIFICATION_COOLDOWN=3600

# --- Binary Paths (set by install script) ---

export GRPCURL_CMD="/usr/local/starlink-monitor/grpcurl" # gRPC client for Starlink API
export JQ_CMD="/usr/local/starlink-monitor/jq"           # JSON processor for parsing API responses
