#!/bin/sh
# Test configuration file with stray quotes in comments

export MAINTENANCE_NOTIFY_ON_FIXES="true"    # Send notification for each successful fix (recommended)"
export MAINTENANCE_NOTIFY_ON_FAILURES="true" # Send notification for each failed fix attempt (recommended)"
export MAINTENANCE_NOTIFY_ON_CRITICAL="true" # Send notification for critical issues (always recommended)"
export MAINTENANCE_NOTIFY_ON_FOUND="false"   # Send notification for issues found but not fixed (can be noisy)"

# This one is correct (no stray quote)
export TEST_VARIABLE="value" # This is a correct comment

# This one has trailing spaces within quotes
export TEST_SPACES="value   " # Comment without stray quote

# This one has both trailing spaces and stray quote
export TEST_BOTH="value   " # Comment with stray quote"
