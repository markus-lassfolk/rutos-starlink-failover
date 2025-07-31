#!/bin/sh

# ==============================================================================
# STARLINK MONITOR CONFIGURATION
# ==============================================================================
# This is a test configuration file for validation testing.
# Template version: 1.0.0
# Compatible with install.sh: 1.0.0
# ==============================================================================

# --- Network Configuration ---

# Starlink gRPC endpoint IP and port

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION
echo "Loading test configuration version: $SCRIPT_VERSION"
export STARLINK_IP="192.168.100.1"
export STARLINK_PORT="9200"

# MWAN3 interface name for Starlink connection
export MWAN_IFACE="wan"

# MWAN3 member name for Starlink connection
export MWAN_MEMBER="member1"

# --- Notification Settings ---

# Pushover API credentials for notifications
export PUSHOVER_TOKEN="test_token_123456"
export PUSHOVER_USER="test_user_789012"

# Notification triggers (1=enabled, 0=disabled)
export NOTIFY_ON_CRITICAL=1
export NOTIFY_ON_SOFT_FAIL=1
export NOTIFY_ON_HARD_FAIL=1
export NOTIFY_ON_RECOVERY=1
export NOTIFY_ON_INFO=0

# --- Performance Thresholds ---

# Packet loss threshold (percentage, decimal format)
export PACKET_LOSS_THRESHOLD=5.0

# Obstruction threshold (percentage, decimal format)
export OBSTRUCTION_THRESHOLD=10.0

# Latency threshold (milliseconds)
export LATENCY_THRESHOLD=1000

# --- System Configuration ---

# Check interval in seconds
export CHECK_INTERVAL=30

# API timeout in seconds
export API_TIMEOUT=10

# --- Directory Configuration ---

# Base directory for logs
export LOG_DIR="/var/log/starlink"

# State directory for tracking
export STATE_DIR="/var/lib/starlink"

# Data directory for historical data
export DATA_DIR="/var/lib/starlink/data"

# --- Testing: Some additional variables that might be in an advanced config ---

# GPS device for location tracking
export GPS_DEVICE="/dev/ttyUSB0"

# Azure logging workspace ID
export AZURE_WORKSPACE_ID="12345678-1234-1234-1234-123456789012"

# Enable advanced monitoring features
export ADVANCED_MONITORING=1

# Enable Azure logging
export ENABLE_AZURE_LOGGING=1
