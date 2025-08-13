#!/bin/sh

# Simplified test for function availability after sourcing rutos-lib.sh

printf "=== Simple Function Availability Test ===\n"

# Just download the library system directly
printf "Downloading RUTOS library system...\n"
mkdir -p scripts/lib

# Download each library file
for lib_file in rutos-lib.sh rutos-colors.sh rutos-logging.sh rutos-common.sh rutos-compatibility.sh rutos-data-collection.sh; do
    printf "Downloading %s...\n" "$lib_file"
    if ! curl -fsSL "https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/lib/$lib_file" -o "scripts/lib/$lib_file"; then
        printf "WARNING: Failed to download %s\n" "$lib_file"
    fi
done

# Test function availability
LIBRARY_PATH="./scripts/lib"

printf "\nLibrary path: %s\n" "$LIBRARY_PATH"

# Check if main library exists
if [ ! -f "$LIBRARY_PATH/rutos-lib.sh" ]; then
    printf "ERROR: Library not found at %s\n" "$LIBRARY_PATH/rutos-lib.sh"
    exit 1
fi

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

# Test 4: Show all available functions that start with 'rutos' or 'log'
printf "\n=== AVAILABLE FUNCTIONS ===\n"
printf "Functions starting with 'rutos':\n"
compgen -A function | grep "^rutos" || printf "No functions found starting with 'rutos'\n"

printf "\nFunctions starting with 'log':\n"
compgen -A function | grep "^log" || printf "No functions found starting with 'log'\n"

# Test 5: Try to call a function if available
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
