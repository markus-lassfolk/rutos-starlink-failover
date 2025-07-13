#!/bin/bash

# ==============================================================================
# Configuration Template for Starlink RUTOS Failover
#
# This file contains all user-configurable settings for the Starlink monitoring
# and failover system. Copy this file to config.sh and customize the values.
#
# ==============================================================================

# --- Network Configuration ---


# shellcheck disable=SC2034
STARLINK_IP="192.168.100.1:9200"


# shellcheck disable=SC2034
MWAN_IFACE="wan"


# shellcheck disable=SC2034
MWAN_MEMBER="member1"


# --- Notification Settings ---


# shellcheck disable=SC2034
PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
# shellcheck disable=SC2034
PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"


# shellcheck disable=SC2034
NOTIFY_ON_CRITICAL=1      # Always notify on critical errors
# shellcheck disable=SC2034
NOTIFY_ON_SOFT_FAIL=1     # Notify on soft failover events
# shellcheck disable=SC2034
NOTIFY_ON_HARD_FAIL=1     # Notify on hard failover events
# shellcheck disable=SC2034
NOTIFY_ON_RECOVERY=1      # Notify when system recovers/failback
# shellcheck disable=SC2034
NOTIFY_ON_INFO=0          # Notify on info/status (set to 1 for verbose)

# --- Failover Thresholds ---


# shellcheck disable=SC2034
PACKET_LOSS_THRESHOLD=0.05


# shellcheck disable=SC2034
OBSTRUCTION_THRESHOLD=0.001


# shellcheck disable=SC2034
LATENCY_THRESHOLD_MS=150

# --- Recovery Settings ---


# shellcheck disable=SC2034
STABILITY_CHECKS_REQUIRED=5

# --- mwan3 Metrics ---


# shellcheck disable=SC2034
METRIC_GOOD=1


# shellcheck disable=SC2034
METRIC_BAD=10

# --- File Paths ---


# shellcheck disable=SC2034
STATE_DIR="/tmp/run"


# shellcheck disable=SC2034
LOG_DIR="/var/log"


# shellcheck disable=SC2034
DATA_DIR="/root"

# --- Binary Paths ---


# shellcheck disable=SC2034
GRPCURL_CMD="/root/grpcurl"


# shellcheck disable=SC2034
JQ_CMD="/root/jq"

# --- RUTOS API Configuration (for GPS) ---


# shellcheck disable=SC2034
RUTOS_IP="192.168.80.1"


# shellcheck disable=SC2034
RUTOS_USERNAME="YOUR_RUTOS_USERNAME"
# shellcheck disable=SC2034
RUTOS_PASSWORD="YOUR_RUTOS_PASSWORD"

# --- Logging Configuration ---


# shellcheck disable=SC2034
LOG_TAG="StarlinkSystem"


# shellcheck disable=SC2034
LOG_RETENTION_DAYS=7

# --- Advanced Settings ---


# shellcheck disable=SC2034
API_TIMEOUT=10
# shellcheck disable=SC2034
HTTP_TIMEOUT=15
# shellcheck disable=SC2034
GPS_ACCURACY_THRESHOLD=100
# shellcheck disable=SC2034
MOVEMENT_THRESHOLD=500
