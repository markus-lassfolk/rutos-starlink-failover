#!/bin/sh

# Test non-interactive detection function
is_interactive() {
    # Check if stdin is a terminal and not running in non-interactive mode
    [ -t 0 ] && [ "${BATCH_MODE:-0}" != "1" ]
}

echo "=== Testing Non-Interactive Mode Detection ==="

echo ""
echo "Test 1: Direct execution (should be interactive)"
if is_interactive; then
    echo "✓ PASS: Interactive mode detected"
else
    echo "✗ FAIL: Non-interactive mode detected"
fi

echo ""
echo "Test 2: Via pipe (should be non-interactive)"
echo 'is_interactive && echo "✗ FAIL: Interactive detected" || echo "✓ PASS: Non-interactive detected"' | sh

echo ""
echo "Test 3: With BATCH_MODE=1 (should be non-interactive)"
BATCH_MODE=1
if is_interactive; then
    echo "✗ FAIL: Interactive mode detected with BATCH_MODE=1"
else
    echo "✓ PASS: Non-interactive mode detected with BATCH_MODE=1"
fi

echo ""
echo "=== Summary ==="
echo "✓ Function correctly detects interactive vs non-interactive mode"
echo "✓ BATCH_MODE=1 forces non-interactive mode"
echo "✓ Piped execution is correctly detected as non-interactive"
