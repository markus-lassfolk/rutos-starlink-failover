#!/bin/sh
# Script: complete-setup.sh
# Version: 1.0.3
# Description: Legacy setup script for Azure logging integration (compatibility wrapper)

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.3"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
# shellcheck disable=SC2034  # CYAN may be used for debugging
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
	# shellcheck disable=SC2034  # CYAN may be used for debugging
	CYAN=""
	NC=""
fi

# Standard logging functions with consistent colors
log_info() {
	printf "%s[INFO]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
	printf "%s[WARNING]%s [%s] %s\n" "$YELLOW" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
	printf "%s[ERROR]%s [%s] %s\n" "$RED" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_success() {
	printf "%s[SUCCESS]%s [%s] %s\n" "$GREEN" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
	printf "%s[STEP]%s [%s] %s\n" "$BLUE" "$NC" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
	log_info "Debug mode enabled for complete-setup.sh v$SCRIPT_VERSION"
fi

# Main function
main() {
	log_info "Starting complete-setup.sh v$SCRIPT_VERSION (Legacy wrapper)"

	# Get script directory
	SCRIPT_DIR="$(dirname "$0")"
	RUTOS_SCRIPT="$SCRIPT_DIR/complete-setup-rutos.sh"

	# Check if RUTOS version exists
	if [ ! -f "$RUTOS_SCRIPT" ]; then
		log_error "RUTOS-specific script not found: $RUTOS_SCRIPT"
		log_error "Please ensure complete-setup-rutos.sh is in the same directory"
		exit 1
	fi

	# Display migration notice
	printf "\n"
	log_warning "=== LEGACY COMPATIBILITY NOTICE ==="
	log_warning "This script (complete-setup.sh) is a legacy compatibility wrapper."
	log_warning "For RUTOS devices, use: complete-setup-rutos.sh"
	log_warning "For standard systems, this wrapper will redirect to the RUTOS version."
	printf "\n"

	# Check if running on RUTOS
	if [ -f "/etc/config/system" ]; then
		log_info "RUTOS system detected - redirecting to RUTOS-specific script"
		log_step "Executing: $RUTOS_SCRIPT"

		# Make sure the RUTOS script is executable
		chmod +x "$RUTOS_SCRIPT"

		# Execute the RUTOS script with all arguments
		exec "$RUTOS_SCRIPT" "$@"
	else
		log_warning "Non-RUTOS system detected"
		log_warning "This Azure logging solution is designed for RUTOS devices"
		log_warning "For standard Linux systems, consider using native syslog forwarding"
		printf "\n"

		log_info "To proceed anyway, run the RUTOS version directly:"
		log_info "  $RUTOS_SCRIPT"
		printf "\n"

		printf "Continue with RUTOS script on non-RUTOS system? [y/N]: "
		read -r REPLY
		if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
			log_step "Executing RUTOS script on non-RUTOS system"
			chmod +x "$RUTOS_SCRIPT"
			exec "$RUTOS_SCRIPT" "$@"
		else
			log_info "Setup cancelled by user"
			exit 0
		fi
	fi
}

# Execute main function
main "$@"
