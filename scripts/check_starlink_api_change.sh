#!/bin/sh
# Script: check_starlink_api_change.sh
# Description: Detects Starlink API schema changes and notifies via Pushover
# Intended for daily cron use

set -eu

# Standard colors for consistent output (compatible with busybox)
# CRITICAL: Use RUTOS-compatible color detection
# shellcheck disable=SC2034

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION

# Use version for logging
echo "check_starlink_api_change.sh v$SCRIPT_VERSION started" >/dev/null 2>&1 || true
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    RED='\033[0;31m'
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    GREEN='\033[0;32m'
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    YELLOW='\033[1;33m'
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    BLUE='\033[1;35m'
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    CYAN='\033[0;36m'
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    NC='\033[0m'
else
    # Colors disabled
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    RED=""
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    GREEN=""
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    YELLOW=""
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    BLUE=""
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    CYAN=""
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    NC=""
fi

CONFIG_FILE="${CONFIG_FILE:-/root/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
else
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

LAST_SCHEMA_FILE="/root/starlink_api_schema_last.json"
CUR_SCHEMA_FILE="/tmp/starlink_api_schema_current.json"
NOTIFIER_SCRIPT="/etc/hotplug.d/iface/99-pushover_notify"

# Dump current API schema (get_device_info is a good proxy for version/fields)
if ! "$GRPCURL_CMD" -plaintext -max-time 10 -d '{"get_device_info":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle 2>/dev/null | "$JQ_CMD" '.' >"$CUR_SCHEMA_FILE"; then
    echo "Warning: Could not fetch Starlink API schema."
    exit 0
fi

# If no previous schema, save and exit
if [ ! -f "$LAST_SCHEMA_FILE" ]; then
    cp "$CUR_SCHEMA_FILE" "$LAST_SCHEMA_FILE"
    exit 0
fi

# Compare schemas
if ! diff -q "$CUR_SCHEMA_FILE" "$LAST_SCHEMA_FILE" >/dev/null; then
    # Schema changed, notify
    if [ -x "$NOTIFIER_SCRIPT" ]; then
        "$NOTIFIER_SCRIPT" api_version_change "$("$JQ_CMD" -r '.apiVersion // "UNKNOWN"' "$LAST_SCHEMA_FILE") -> $("$JQ_CMD" -r '.apiVersion // "UNKNOWN"' "$CUR_SCHEMA_FILE")"
    fi
    cp "$CUR_SCHEMA_FILE" "$LAST_SCHEMA_FILE"
fi

exit 0
