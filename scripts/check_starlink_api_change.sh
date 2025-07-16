#!/bin/sh
# Script: check_starlink_api_change.sh
# Version: 1.0.3
# Description: Detects Starlink API schema changes and notifies via Pushover
# Intended for daily cron use

set -eu

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
# shellcheck disable=SC2034
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
	# Colors enabled
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[1;35m'
	CYAN='\033[0;36m'
	NC='\033[0m'
else
	# Colors disabled
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
	CYAN=""
	NC=""
fi

# Standard logging functions
log_info() {
	printf "%s[INFO]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
	printf "%s[WARNING]%s [%s] %s\n" "$YELLOW" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
	printf "%s[ERROR]%s [%s] %s\n" "$RED" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
	if [ "$DEBUG" = "1" ]; then
		printf "%s[DEBUG]%s [%s] %s\n" "$CYAN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
	fi
}

# Debug mode support
DEBUG="${DEBUG:-0}"

# Configuration file loading
CONFIG_FILE="${CONFIG_FILE:-/root/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
	log_debug "Loading configuration from: $CONFIG_FILE"
	# shellcheck source=/dev/null
	. "$CONFIG_FILE"
else
	log_error "Configuration file not found: $CONFIG_FILE"
	exit 1
fi

# File paths for schema comparison
LAST_SCHEMA_FILE="/root/starlink_api_schema_last.json"
CUR_SCHEMA_FILE="/tmp/starlink_api_schema_current.json"
NOTIFIER_SCRIPT="/etc/hotplug.d/iface/99-pushover_notify"

log_info "Starting Starlink API schema change detection"
log_debug "Last schema file: $LAST_SCHEMA_FILE"
log_debug "Current schema file: $CUR_SCHEMA_FILE"

# Dump current API schema (get_device_info is a good proxy for version/fields)
log_debug "Fetching current API schema from $STARLINK_IP"
if ! "$GRPCURL_CMD" -plaintext -max-time 10 -d '{"get_device_info":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | "$JQ_CMD" '.' >"$CUR_SCHEMA_FILE"; then
	log_warning "Could not fetch Starlink API schema"
	exit 0
fi

log_debug "API schema fetched successfully"

# If no previous schema, save and exit
if [ ! -f "$LAST_SCHEMA_FILE" ]; then
	log_info "No previous schema found, saving current schema"
	cp "$CUR_SCHEMA_FILE" "$LAST_SCHEMA_FILE"
	exit 0
fi

# Compare schemas
log_debug "Comparing current schema with previous schema"
if ! diff -q "$CUR_SCHEMA_FILE" "$LAST_SCHEMA_FILE" >/dev/null; then
	log_info "Schema change detected!"
	
	# Schema changed, notify
	if [ -x "$NOTIFIER_SCRIPT" ]; then
		OLD_VERSION=$(jq -r '.apiVersion // "UNKNOWN"' "$LAST_SCHEMA_FILE")
		NEW_VERSION=$(jq -r '.apiVersion // "UNKNOWN"' "$CUR_SCHEMA_FILE")
		log_info "Notifying about API version change: $OLD_VERSION -> $NEW_VERSION"
		"$NOTIFIER_SCRIPT" api_version_change "$OLD_VERSION -> $NEW_VERSION"
	else
		log_warning "Notifier script not found or not executable: $NOTIFIER_SCRIPT"
	fi
	
	# Save the new schema
	cp "$CUR_SCHEMA_FILE" "$LAST_SCHEMA_FILE"
	log_info "Schema updated successfully"
else
	log_debug "No schema changes detected"
fi

log_info "API schema check completed"
exit 0
