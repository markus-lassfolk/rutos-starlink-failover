#!/bin/sh
# Test configuration file with stray quotes in comments

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
export MAINTENANCE_NOTIFY_ON_FIXES="true"    # Send notification for each successful fix (recommended)"
export MAINTENANCE_NOTIFY_ON_FAILURES="true" # Send notification for each failed fix attempt (recommended)"
export MAINTENANCE_NOTIFY_ON_CRITICAL="true" # Send notification for critical issues (always recommended)"
export MAINTENANCE_NOTIFY_ON_FOUND="false"   # Send notification for issues found but not fixed (can be noisy)"

# This one is correct (no stray quote)
export TEST_VARIABLE="value" # This is a correct comment

# This one has trailing spaces within quotes
export TEST_SPACES="value   " # Comment without stray quote

# This one has both trailing spaces and stray quote
# Debug version display
if [ "$DEBUG" = "1" ]; then
    printf "Script version: %s\n" "$SCRIPT_VERSION"
fi

export TEST_BOTH="value   " # Comment with stray quote"
