#!/bin/sh

# ==============================================================================
# Unified Starlink Proactive Quality Monitor for OpenWrt/RUTOS
#
# Version: 2.8.0
# Source: https://github.com/markus-lassfolk/rutos-starlink-failover/
# shellcheck disable=SC1091  # False positive: "Source" in URL comment, not shell command
#
# This script proactively monitors the quality of a Starlink internet connection
# using its unofficial gRPC API. Supports both basic monitoring and enhanced
# features (GPS, cellular) based on configuration settings.
#
# Features (configuration-controlled):
# - Basic Starlink quality monitoring with failover logic
# - GPS location tracking from multiple sources (RUTOS, Starlink)
# shellcheck disable=SC1091  # False positive: "sources" in comment, not shell command
# - 4G/5G cellular data collection (signal, operator, roaming)
# - Intelligent multi-factor failover decisions
# - Centralized configuration management
# - Comprehensive error handling and logging
# - Health checks and diagnostics
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
if ! . "$(dirname "$0")/../scripts/lib/rutos-lib.sh" 2>/dev/null &&
    ! . "/usr/local/starlink-monitor/scripts/lib/rutos-lib.sh" 2>/dev/null &&
    ! . "$(dirname "$0")/lib/rutos-lib.sh" 2>/dev/null; then
    # CRITICAL ERROR: RUTOS library not found - this script requires the library system
    printf "CRITICAL ERROR: RUTOS library system not found!\n" >&2
    printf "Expected locations:\n" >&2
    printf "  - $(dirname "$0")/../scripts/lib/rutos-lib.sh\n" >&2
    printf "  - /usr/local/starlink-monitor/scripts/lib/rutos-lib.sh\n" >&2
    printf "  - $(dirname "$0")/lib/rutos-lib.sh\n" >&2
    printf "\nThis script requires the RUTOS library for proper operation.\n"
" >&2
    exit 1
fi

# CRITICAL: Initialize script with RUTOS library features (REQUIRED)
rutos_init "starlink_monitor_unified-rutos.sh" "$SCRIPT_VERSION"
