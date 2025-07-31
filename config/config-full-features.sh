#!/bin/sh
# Full-featured test config to enable ALL analytics and logging

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"

# Configuration metadata for troubleshooting
CONFIG_VERSION="2.8.0"
CONFIG_TYPE="full_test"

# Basic required variables
export STARLINK_IP="192.168.100.1"
export STARLINK_PORT="9200"
export CHECK_INTERVAL="30" # How often to test Starlink (seconds)
export API_TIMEOUT="10"    # API call timeout (seconds)
export PUSHOVER_TOKEN="test_token"
export PUSHOVER_USER="test_user"

# Basic system settings
export LOG_DIR="/var/log/starlink"
export STATE_DIR="/tmp/starlink"
export JQ_CMD="jq"
export GRPCURL_CMD="grpcurl"

# MWAN3 settings (required for actual failover testing)
export MWAN_IFACE="wan"
export MWAN_MEMBER="member1"
export METRIC_GOOD="1"
export METRIC_BAD="20"

# Enable ALL analytics and logging features
export ENABLE_GPS_TRACKING="true"
export ENABLE_CELLULAR_TRACKING="true"
export ENABLE_ENHANCED_FAILOVER="true"
export ENABLE_GPS_LOGGING="true"
export ENABLE_CELLULAR_LOGGING="true"
export ENABLE_MULTI_SOURCE_GPS="true"
export ENABLE_ENHANCED_FAILOVER_LOGGING="true"
export ENABLE_INTELLIGENT_OBSTRUCTION="true"

# Enhanced thresholds for testing
export LATENCY_THRESHOLD="100"
export PACKET_LOSS_THRESHOLD="5"
export OBSTRUCTION_THRESHOLD="3"
export OBSTRUCTION_MIN_DATA_HOURS="1"
export OBSTRUCTION_HISTORICAL_THRESHOLD="1.0"
export OBSTRUCTION_PROLONGED_THRESHOLD="30"
export JITTER_THRESHOLD="20"

# Enable maximum debugging
export DEBUG="1"
export RUTOS_TEST_MODE="1"
