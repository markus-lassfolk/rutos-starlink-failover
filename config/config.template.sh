#!/bin/bash

# ==============================================================================
# Configuration Template for Starlink RUTOS Failover
#
# This file contains all user-configurable settings for the Starlink monitoring
# and failover system. Copy this file to config.sh and customize the values.
#
# Template Version: 1.0.0
# Compatible with install.sh: 1.0.0
# ==============================================================================

# --- Network Configuration ---

# Starlink gRPC endpoint IP and port
# Default: 192.168.100.1:9200 (standard Starlink configuration)
STARLINK_IP="192.168.100.1:9200"

# MWAN3 interface name for Starlink connection
# Check your MWAN3 config: uci show mwan3 | grep interface
MWAN_IFACE="wan"

# MWAN3 member name for Starlink connection
# Check your MWAN3 config: uci show mwan3 | grep member
MWAN_MEMBER="member1"

# --- Notification Settings ---

# Pushover API credentials for notifications
# Get your token from: https://pushover.net/apps/build
# Get your user key from: https://pushover.net/
PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

# Notification triggers (1=enabled, 0=disabled)
# 
# CRITICAL: System failures, API errors, connection lost
NOTIFY_ON_CRITICAL=1 # Always notify on critical errors (recommended: 1)
# 
# SOFT_FAIL: Starlink degraded but still usable (high latency, packet loss)
NOTIFY_ON_SOFT_FAIL=1 # Notify on soft failover events (recommended: 1)
# 
# HARD_FAIL: Starlink completely down, switched to cellular backup
NOTIFY_ON_HARD_FAIL=1 # Notify on hard failover events (recommended: 1)
# 
# RECOVERY: Starlink recovered, switched back from cellular
NOTIFY_ON_RECOVERY=1 # Notify when system recovers/failback (recommended: 1)
# 
# INFO: Status updates, monitoring health, debug information
NOTIFY_ON_INFO=0 # Notify on info/status (0=quiet, 1=verbose)

# --- Failover Thresholds ---

# Packet loss threshold (0.0-1.0, where 0.05 = 5%)
# Triggers failover when packet loss exceeds this value
PACKET_LOSS_THRESHOLD=0.05

# Obstruction threshold (0.0-1.0, where 0.001 = 0.1%)
# Triggers failover when obstruction fraction exceeds this value
OBSTRUCTION_THRESHOLD=0.001

# Latency threshold in milliseconds
# Triggers failover when latency exceeds this value
LATENCY_THRESHOLD_MS=150

# --- Recovery Settings ---

# Number of consecutive successful checks required before switching back to Starlink
# Higher values = more conservative (slower to switch back)
# Lower values = more aggressive (faster to switch back)
STABILITY_CHECKS_REQUIRED=5

# --- mwan3 Metrics ---

# MWAN3 metric values for interface prioritization
# Lower values = higher priority (1 = highest priority)
METRIC_GOOD=1  # Metric when Starlink is working well
METRIC_BAD=10  # Metric when Starlink is degraded (forces cellular usage)

# --- File Paths ---

# System directories for persistent storage
# NOTE: /var/log is wiped on reboot in OpenWrt/RUTOS - use /overlay/ for persistence
STATE_DIR="/tmp/run"             # Runtime state files (temporary)
LOG_DIR="/overlay/starlink-logs" # Log files directory (persistent across reboots)
DATA_DIR="/overlay/starlink-data" # Data storage directory (persistent across reboots)

# --- Binary Paths ---

# Installed binary locations (set by install script)
GRPCURL_CMD="/root/grpcurl"  # gRPC client for Starlink API
JQ_CMD="/root/jq"           # JSON processor

# --- RUTOS API Configuration (for GPS) ---

# RUTX50 router management interface
# Default: 192.168.80.1 (standard RUTX50 LAN IP)
RUTOS_IP="192.168.80.1"

# RUTX50 login credentials
# Set these to your router's admin credentials
RUTOS_USERNAME="YOUR_RUTOS_USERNAME"
RUTOS_PASSWORD="YOUR_RUTOS_PASSWORD"

# --- Logging Configuration ---

# System logging settings
LOG_TAG="StarlinkSystem"    # Syslog tag for filtering logs
LOG_RETENTION_DAYS=7        # How long to keep log files

# --- Advanced Settings ---

# Timeout values in seconds
API_TIMEOUT=10         # Starlink API request timeout
HTTP_TIMEOUT=15        # HTTP request timeout (for RUTOS API)
GPS_ACCURACY_THRESHOLD=100   # GPS accuracy threshold in meters
MOVEMENT_THRESHOLD=500       # Movement detection threshold in meters
