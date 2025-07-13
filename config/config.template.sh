#!/bin/bash

# ==============================================================================
# Configuration Template for Starlink RUTOS Failover
#
# This file contains all user-configurable settings for the Starlink monitoring
# and failover system. Copy this file to config.sh and customize the values.
#
# ==============================================================================

# --- Network Configuration ---

STARLINK_IP="192.168.100.1:9200"

MWAN_IFACE="wan"

MWAN_MEMBER="member1"


# --- Notification Settings ---

PUSHOVER_TOKEN="YOUR_PUSHOVER_API_TOKEN"
PUSHOVER_USER="YOUR_PUSHOVER_USER_KEY"

NOTIFY_ON_CRITICAL=1      # Always notify on critical errors
NOTIFY_ON_SOFT_FAIL=1     # Notify on soft failover events
NOTIFY_ON_HARD_FAIL=1     # Notify on hard failover events
NOTIFY_ON_RECOVERY=1      # Notify when system recovers/failback
NOTIFY_ON_INFO=0          # Notify on info/status (set to 1 for verbose)

# --- Failover Thresholds ---

PACKET_LOSS_THRESHOLD=0.05

OBSTRUCTION_THRESHOLD=0.001

LATENCY_THRESHOLD_MS=150

# --- Recovery Settings ---

STABILITY_CHECKS_REQUIRED=5

# --- mwan3 Metrics ---

METRIC_GOOD=1

METRIC_BAD=10

# --- File Paths ---

STATE_DIR="/tmp/run"

LOG_DIR="/var/log"

DATA_DIR="/root"

# --- Binary Paths ---

GRPCURL_CMD="/root/grpcurl"

JQ_CMD="/root/jq"

# --- RUTOS API Configuration (for GPS) ---

RUTOS_IP="192.168.80.1"

RUTOS_USERNAME="YOUR_RUTOS_USERNAME"
RUTOS_PASSWORD="YOUR_RUTOS_PASSWORD"

# --- Logging Configuration ---

LOG_TAG="StarlinkSystem"

LOG_RETENTION_DAYS=7

# --- Advanced Settings ---

API_TIMEOUT=10

HTTP_TIMEOUT=15

GPS_ACCURACY_THRESHOLD=100

MOVEMENT_THRESHOLD=500
