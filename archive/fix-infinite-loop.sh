#!/bin/sh

# ==============================================================================
# Fix Infinite Loop in Configuration Processing
#
# This script fixes the infinite loop in install-rutos.sh where empty variable
# names are being processed, causing the "Processing template variable: " loop.
#
# The issue is in the sed commands that extract variable names - they're missing
# the \1 capture group replacement, causing empty variable names.
# ==============================================================================

set -e

SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "fix-infinite-loop.sh" "$SCRIPT_VERSION"

TARGET_FILE="scripts/install-rutos.sh"

log_info "Fixing infinite loop in configuration processing"

if [ ! -f "$TARGET_FILE" ]; then
    log_error "Target file not found: $TARGET_FILE"
    exit 1
fi

# Create backup
log_step "Creating backup of $TARGET_FILE"
safe_execute "cp '$TARGET_FILE' '${TARGET_FILE}.infinite-loop-fix.bak'" "Backup original file"

# Fix the sed commands that are missing \1 capture group
log_step "Fixing sed commands with missing capture groups"

# Fix line around 957 - template variable extraction
safe_execute "sed -i 's|sed '\''s/^export \\([^=]*\\)=.*//'\'')|\sed '\''s/^export \\([^=]*\\)=.*/\\1/'\'')|g' '$TARGET_FILE'" "Fix template variable extraction (export)"

# Fix line around 959 - template variable extraction (non-export)
safe_execute "sed -i 's|sed '\''s/^\\([^=]*\\)=.*//'\'')|\sed '\''s/^\\([^=]*\\)=.*/\\1/'\'')|g' '$TARGET_FILE'" "Fix template variable extraction (standard)"

# Add validation to prevent empty variable names (insert after the sed commands)
log_step "Adding variable name validation to prevent infinite loop"

# Create a temporary file with the fix
temp_fix="/tmp/install_fix_$$.sh"

# Add the validation code after the variable extraction
safe_execute "awk '
/^        if echo \"\$template_line\" \| grep -q \"\^export \"; then$/ {
    print
    getline; print  # Print the var_name assignment
    getline; print  # Print the else
    getline; print  # Print the var_name assignment for non-export
    getline; print  # Print the fi
    print ""
    print "        # Critical fix: Validate variable name to prevent infinite loop"
    print "        if [ -z \"\$var_name\" ] || ! echo \"\$var_name\" | grep -q \"^[A-Za-z_][A-Za-z0-9_]*\$\"; then"
    print "            config_debug \"Skipping invalid/empty variable name in line: \$template_line\""
    print "            continue"
    print "        fi"
    next
}
{ print }
' '$TARGET_FILE' > '$temp_fix'" "Create fixed version with validation"

safe_execute "mv '$temp_fix' '$TARGET_FILE'" "Apply the fix"

# Verify the fix was applied
log_step "Verifying fix was applied correctly"

if grep -q "Skipping invalid/empty variable name" "$TARGET_FILE"; then
    log_success "✓ Infinite loop fix applied successfully"
    log_info "The script now validates variable names to prevent empty processing"
    
    # Show what was fixed
    log_info "Fixed patterns:"
    log_info "  - sed 's/^export \\([^=]*\\)=.*//' → sed 's/^export \\([^=]*\\)=.*/\\1/'"
    log_info "  - sed 's/^\\([^=]*\\)=.*//' → sed 's/^\\([^=]*\\)=.*/\\1/'"
    log_info "  - Added variable name validation to prevent infinite loops"
    
else
    log_error "✗ Fix verification failed - validation code not found"
    log_info "Restoring backup..."
    safe_execute "mv '${TARGET_FILE}.infinite-loop-fix.bak' '$TARGET_FILE'" "Restore backup"
    exit 1
fi

log_success "Infinite loop fix completed successfully!"
log_info "The configuration processing should no longer get stuck on empty variable names"
