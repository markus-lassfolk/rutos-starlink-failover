#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC2154

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
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
export PUSHOVER_TOKEN="aczm9pre8oowwpxmte92utk5gbyub7"
export PUSHOVER_USER="uXLTS5NjcBSj5v6xi7uB8VH4khD6dK"

# Notification triggers (1=enabled, 0=disabled)
export NOTIFY_ON_CRITICAL=1  # Critical errors (recommended: 1)
export NOTIFY_ON_HARD_FAIL=1 # Complete failures (recommended: 1)
export NOTIFY_ON_RECOVERY=1  # System recovery (recommended: 1)
export NOTIFY_ON_SOFT_FAIL=1 # Degraded performance (your custom setting: enabled)
export NOTIFY_ON_INFO=1      # Status updates (your custom setting: enabled)

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

# --- Binary Paths (set by install script) ---

export GRPCURL_CMD="/usr/local/starlink-monitor/grpcurl" # gRPC client for Starlink API
export JQ_CMD="/usr/local/starlink-monitor/jq"           # JSON processor for parsing API responses
