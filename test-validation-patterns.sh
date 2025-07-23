#!/bin/sh
# Test file for quote validation patterns
# Description: Contains both valid and intentionally invalid patterns for testing validation logic
# RUTOS Compatible: Uses POSIX sh
# shellcheck disable=SC1078,SC1079,SC3045  # Intentional test patterns with malformed syntax

# These lines should be VALID (not flagged):

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
export STARLINK_IP="192.168.100.1:9200"
export MWAN_IFACE="wan"
export NOTIFY_ON_CRITICAL="1"              # Critical errors (recommended: 1)
export MAINTENANCE_PUSHOVER_ENABLED="true" # Uses PUSHOVER_TOKEN/PUSHOVER_USER if not overridden

# These lines should be INVALID (should be flagged):
export BAD_QUOTE="missing closing quote
export ANOTHER_BAD="value # comment inside quotes"
export TRAILING_SPACES="value   "
export STRAY_QUOTE="value" # comment with extra quote"

# These should NOT be flagged as malformed exports:
export VALID_VAR="value"
export _UNDERSCORE_VAR="value"
export VAR123="value"

# This SHOULD be flagged as malformed export:
export 123invalid="value"
# Debug version display
if [ "$DEBUG" = "1" ]; then
    printf "Script version: %s\n" "$SCRIPT_VERSION"
fi

export -invalid="value"
