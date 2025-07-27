#!/bin/sh
# Quick debug script to check config.sh contents
# Version: 2.7.0

# Version information (auto-updated by update-version.sh)
# shellcheck disable=SC2034  # SCRIPT_VERSION used for validation compliance
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION

# Colors for output (compatible with busybox)
# shellcheck disable=SC2034  # Used in some conditional contexts
RED='\033[0;31m'
GREEN='\033[0;32m'
# shellcheck disable=SC2034  # Used in some conditional contexts
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034  # Used in some conditional contexts
CYAN='\033[0;36m'
NC='\033[0m'

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    # Colors disabled
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    RED=""
    GREEN=""
    # shellcheck disable=SC2034  # YELLOW not used in this debug script
    YELLOW=""
    BLUE=""
    # shellcheck disable=SC2034  # CYAN not used in this debug script
    CYAN=""
    NC=""
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

CONFIG_FILE="${CONFIG_FILE:-/etc/starlink-config/config.sh}"

log_info "Debugging config.sh file contents (v$SCRIPT_VERSION)"
log_step "File exists check:"
if [ -f "$CONFIG_FILE" ]; then
    printf "  ✅ File exists: %s\n" "$CONFIG_FILE"
    printf "  📏 File size: %s bytes\n" "$(wc -c <"$CONFIG_FILE")"
else
    printf "  ❌ File not found: %s\n" "$CONFIG_FILE"
    exit 1
fi

log_step "Looking for required settings:"
printf "  STARLINK_IP: "
if grep -q "STARLINK_IP=" "$CONFIG_FILE"; then
    value=$(grep "STARLINK_IP=" "$CONFIG_FILE" | tail -1 | cut -d'=' -f2- | tr -d '"')
    printf "✅ Found: %s\n" "$value"
else
    printf "❌ Not found\n"
fi

printf "  MWAN_IFACE: "
if grep -q "MWAN_IFACE=" "$CONFIG_FILE"; then
    value=$(grep "MWAN_IFACE=" "$CONFIG_FILE" | tail -1 | cut -d'=' -f2- | tr -d '"')
    printf "✅ Found: %s\n" "$value"
else
    printf "❌ Not found\n"
fi

printf "  MWAN_MEMBER: "
if grep -q "MWAN_MEMBER=" "$CONFIG_FILE"; then
    value=$(grep "MWAN_MEMBER=" "$CONFIG_FILE" | tail -1 | cut -d'=' -f2- | tr -d '"')
    printf "✅ Found: %s\n" "$value"
else
    printf "❌ Not found\n"
fi

log_step "First 20 lines of config file:"
head -20 "$CONFIG_FILE"

log_step "Last 20 lines of config file:"
tail -20 "$CONFIG_FILE"

log_step "All STARLINK_IP lines:"
grep -n "STARLINK_IP" "$CONFIG_FILE" || echo "  No STARLINK_IP lines found"

log_step "All export lines (first 10):"
grep "^export " "$CONFIG_FILE" | head -10

log_info "Debug complete"
