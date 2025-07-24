#!/bin/sh
# Script: test-method5-final.sh
# Purpose: Final test of Method 5 color format for RUTOS compatibility
# Version: Tests the finalized Method 5 implementation

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    printf "[INFO] RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution\n" >&2
    exit 0
fi

# RUTOS-compatible color detection (Method 5 format)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;35m"
    CYAN="\033[0;36m"
    NC="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Method 5 demonstration
printf "Method 5 Color Test v%s - RUTOS Compatible Format\n" "$SCRIPT_VERSION"
printf "============================================\n"
# shellcheck disable=SC2059
printf "${RED}RED: Error messages${NC}\n"
# shellcheck disable=SC2059
printf "${GREEN}GREEN: Success messages${NC}\n"
# shellcheck disable=SC2059
printf "${YELLOW}YELLOW: Warning messages${NC}\n"
# shellcheck disable=SC2059
printf "${BLUE}BLUE: Step messages${NC}\n"
# shellcheck disable=SC2059
printf "${CYAN}CYAN: Debug messages${NC}\n"
printf "Method 5 test completed successfully\n"