#!/bin/sh
# Test config for health check testing

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"

# Configuration metadata for troubleshooting
CONFIG_VERSION="2.7.1"
CONFIG_TYPE="test"

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

# Enable debug for testing
export DEBUG="1"
