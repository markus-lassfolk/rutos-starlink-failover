#!/bin/bash

# ==============================================================================
# Configuration Template for Starlink RUTOS Failover
#
# This file contains all user-configurable settings for the Starlink monitoring
# and failover system. Copy this file to config.sh and customize the values.
#
# ==============================================================================

# --- Network Configuration ---

# Starlink gRPC API endpoint (standard configuration)
STARLINK_IP="192.168.100.1:9200"

# OpenWrt/RUTOS interface name for Starlink
MWAN_IFACE="wan"

# mwan3 member name for Starlink interface
MWAN_MEMBER="member1"


# --- Notification Settings ---

# Pushover API credentials (get from https://pushover.net)
PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

# Notification controls (1=enabled, 0=disabled)
NOTIFY_ON_CRITICAL=1      # Always notify on critical errors
NOTIFY_ON_SOFT_FAIL=1     # Notify on soft failover events
NOTIFY_ON_HARD_FAIL=1     # Notify on hard failover events
NOTIFY_ON_RECOVERY=1      # Notify when system recovers/failback
NOTIFY_ON_INFO=0          # Notify on info/status (set to 1 for verbose)

# --- Failover Thresholds ---

# Packet loss threshold (0.0-1.0, e.g., 0.05 = 5%)
PACKET_LOSS_THRESHOLD=0.05

# Obstruction threshold (0.0-1.0, e.g., 0.001 = 0.1%)
OBSTRUCTION_THRESHOLD=0.001

# Latency threshold in milliseconds
LATENCY_THRESHOLD_MS=150

# --- Recovery Settings ---

# Number of consecutive good checks before failback
STABILITY_CHECKS_REQUIRED=5

# --- mwan3 Metrics ---

# Metric when connection is good (lower = higher priority)
METRIC_GOOD=1

# Metric when connection is bad (higher = lower priority)
METRIC_BAD=10

# --- File Paths ---

# Directory for state files (tmpfs recommended)
STATE_DIR="/tmp/run"

# Directory for log files
LOG_DIR="/var/log"

# Directory for persistent data
DATA_DIR="/root"

# --- Binary Paths ---

# Location of grpcurl binary
GRPCURL_CMD="/root/grpcurl"

# Location of jq binary
JQ_CMD="/root/jq"

# --- RUTOS API Configuration (for GPS) ---

# RUTOS router IP address
RUTOS_IP="192.168.80.1"

# RUTOS API credentials
RUTOS_USERNAME="YOUR_RUTOS_USERNAME"
RUTOS_PASSWORD="YOUR_RUTOS_PASSWORD"

# --- Logging Configuration ---

# Log tag for system logs
LOG_TAG="StarlinkSystem"

# Log retention days
LOG_RETENTION_DAYS=7

# --- Advanced Settings ---

# API timeout in seconds
API_TIMEOUT=10

# HTTP timeout for notifications
HTTP_TIMEOUT=15

# GPS accuracy threshold for failover (meters)
GPS_ACCURACY_THRESHOLD=100

# Movement threshold for Starlink obstruction reset (meters)
MOVEMENT_THRESHOLD=500
