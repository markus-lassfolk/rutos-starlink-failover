# Test file for quote validation patterns

# These lines should be VALID (not flagged):
export STARLINK_IP="192.168.100.1:9200"
export MWAN_IFACE="wan"
export NOTIFY_ON_CRITICAL="1" # Critical errors (recommended: 1)
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
export -invalid="value"
