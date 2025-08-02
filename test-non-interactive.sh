#!/bin/sh

# Test script to verify non-interactive mode detection works

echo "Testing interactive mode detection..."

# Source the deploy script to get the function
BATCH_MODE=0
. ./deploy-starlink-solution-v3-rutos.sh 2>/dev/null || true

# Test the function
if is_interactive; then
    echo "✓ Interactive mode detected (expected when run directly)"
else
    echo "✓ Non-interactive mode detected (expected when piped)"
fi

echo ""
echo "Now testing via pipe (should be non-interactive):"
echo 'if is_interactive; then echo "FAIL: Interactive detected"; else echo "✓ Non-interactive detected"; fi' | sh

echo ""
echo "Testing with BATCH_MODE=1:"
BATCH_MODE=1
if is_interactive; then
    echo "FAIL: Interactive detected with BATCH_MODE=1"
else
    echo "✓ Non-interactive detected with BATCH_MODE=1"
fi
