#!/bin/bash

# Simple fix for the infinite loop by manually replacing the problematic patterns
echo "Fixing infinite loop in install-rutos.sh..."

# Create backup
cp scripts/install-rutos.sh scripts/install-rutos.sh.infinite-loop-backup

# Fix the sed patterns that are missing \1
sed -i 's|sed '\''s/^export \\([^=]*\\)=.*/'\''|sed '\''s/^export \\([^=]*\\)=.*/\\1/'\''|g' scripts/install-rutos.sh
sed -i 's|sed '\''s/^\\([^=]*\\)=.*/'\''|sed '\''s/^\\([^=]*\\)=.*/\\1/'\''|g' scripts/install-rutos.sh

echo "Verifying fix..."
if grep -q 'sed.*\\1' scripts/install-rutos.sh; then
    echo "✓ Fix applied successfully - sed commands now include \\1 replacement"
else
    echo "✗ Fix failed - restoring backup"
    mv scripts/install-rutos.sh.infinite-loop-backup scripts/install-rutos.sh
    exit 1
fi

echo "Adding validation to prevent empty variable names..."

# Add validation after the variable extraction
awk '
/if \[ -n "\$var_name" \]; then/ {
    print "        # Critical fix: Validate variable name to prevent infinite loop"
    print "        if [ -z \"$var_name\" ] || ! echo \"$var_name\" | grep -q \"^[A-Za-z_][A-Za-z0-9_]*$\"; then"
    print "            config_debug \"Skipping invalid/empty variable name in line: $template_line\""
    print "            continue"
    print "        fi"
    print ""
    print
    next
}
{ print }
' scripts/install-rutos.sh > scripts/install-rutos.sh.tmp && mv scripts/install-rutos.sh.tmp scripts/install-rutos.sh

echo "Infinite loop fix complete!"
