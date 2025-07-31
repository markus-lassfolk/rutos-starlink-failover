#!/bin/sh

# Test function availability after sourcing rutos-lib.sh
# This script will help diagnose the exact issue

printf "=== Testing Function Availability ===\n"

# Set up paths like the install script does
SCRIPT_DIR="$(dirname "$0")"
LIBRARY_PATH="$SCRIPT_DIR/scripts/lib"

printf "Script directory: %s\n" "$SCRIPT_DIR"
printf "Library path: %s\n" "$LIBRARY_PATH"

# Check if library exists
if [ ! -f "$LIBRARY_PATH/rutos-lib.sh" ]; then
    printf "ERROR: Library not found at %s\n" "$LIBRARY_PATH/rutos-lib.sh"
    exit 1
fi

printf "Library file exists: %s\n" "$LIBRARY_PATH/rutos-lib.sh"

# Test 1: Check function availability before sourcing
printf "\n=== BEFORE sourcing library ===\n"
for test_func in rutos_init_portable rutos_init log_info log_debug; do
    if command -v "$test_func" >/dev/null 2>&1; then
        printf "✓ Function available before sourcing: %s\n" "$test_func"
    else
        printf "✗ Function NOT available before sourcing: %s\n" "$test_func"
    fi
done

# Test 2: Source the library and capture any output
printf "\n=== SOURCING library ===\n"
printf "Sourcing library with debug output...\n"

# Capture sourcing output
if . "$LIBRARY_PATH/rutos-lib.sh" 2>/tmp/debug_source.$$; then
    printf "✓ Library sourcing completed successfully\n"
else
    source_exit_code=$?
    printf "✗ Library sourcing FAILED with exit code: %d\n" "$source_exit_code"
fi

# Show debug output
if [ -f "/tmp/debug_source.$$" ]; then
    printf "\nDEBUG OUTPUT FROM SOURCING:\n"
    cat "/tmp/debug_source.$$"
    rm -f "/tmp/debug_source.$$"
fi

# Test 3: Check function availability after sourcing
printf "\n=== AFTER sourcing library ===\n"
for test_func in rutos_init_portable rutos_init log_info log_debug; do
    if command -v "$test_func" >/dev/null 2>&1; then
        printf "✓ Function available after sourcing: %s\n" "$test_func"
    else
        printf "✗ Function NOT available after sourcing: %s\n" "$test_func"
    fi
done

# Test 4: Try to call a function if available
printf "\n=== TESTING function call ===\n"
if command -v rutos_init_portable >/dev/null 2>&1; then
    printf "Attempting to call rutos_init_portable...\n"
    if rutos_init_portable "test-script" "1.0.0"; then
        printf "✓ rutos_init_portable call successful\n"
    else
        printf "✗ rutos_init_portable call failed\n"
    fi
else
    printf "Cannot test function call - rutos_init_portable not available\n"
fi

printf "\n=== Test Complete ===\n"
