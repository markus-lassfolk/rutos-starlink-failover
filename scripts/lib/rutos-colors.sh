#!/bin/sh
# ==============================================================================
# RUTOS Colors Library
#
# Version: 2.7.1
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
#
# Provides standardized color definitions for all RUTOS scripts.
# RUTOS-compatible (busybox sh) with Method 5 printf format support.
# ==============================================================================

# Prevent multiple sourcing

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION
if [ "${_RUTOS_COLORS_LOADED:-}" = "1" ]; then
    return 0
fi
_RUTOS_COLORS_LOADED=1

# Standard RUTOS color scheme (busybox compatible)
RED='\033[0;31m'    # Errors, critical issues
GREEN='\033[0;32m'  # Success, info, completed actions
YELLOW='\033[1;33m' # Warnings, important notices
BLUE='\033[1;35m'   # Steps, progress indicators (bright magenta for better readability)
PURPLE='\033[0;35m' # Special status, headers
CYAN='\033[0;36m'   # Debug messages, technical info
NC='\033[0m'        # No Color (reset)

# Initialize colors based on terminal capabilities
init_colors() {
    # Auto-set TERM if not defined (helps with WSL and minimal environments)
    if [ -z "${TERM:-}" ] && [ -t 1 ]; then
        export TERM=xterm
    fi

    # Enhanced RUTOS-compatible color detection
    # Enable colors if:
    # 1. We have a terminal AND proper TERM, OR
    # 2. We have a good TERM setting (even if tty test fails in some environments)
    if { [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; } ||
        { [ "${TERM:-}" = "xterm" ] || [ "${TERM:-}" = "xterm-256color" ] || [ "${TERM:-}" = "screen" ]; } && [ "${NO_COLOR:-}" != "1" ]; then
        # Colors enabled - keep the definitions above
        return 0
    else
        # Colors disabled - clear all color codes
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        PURPLE=""
        CYAN=""
        NC=""
    fi
}

# Disable colors (useful for log files)
disable_colors() {
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
}

# Enable colors (re-initialize)
enable_colors() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
}

# Auto-initialize colors when module is loaded
init_colors
