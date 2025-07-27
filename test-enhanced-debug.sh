#!/bin/sh
# Test script to see enhanced debug logging for install_enhanced_monitoring

# Load the library
if [ -f "scripts/lib/rutos-lib.sh" ]; then
    . scripts/lib/rutos-lib.sh
    rutos_init_portable "test-enhanced-debug" "1.0.0"
else
    echo "Error: Cannot find RUTOS library"
    exit 1
fi

# Set up variables needed by the function
INSTALL_DIR="/usr/local/starlink-monitor"
BASE_URL="https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main"
mkdir -p "$INSTALL_DIR/scripts" 2>/dev/null || true

# Source the install script to get the function
. scripts/install-rutos.sh

# Test the install_enhanced_monitoring function
echo "=== Testing install_enhanced_monitoring function with enhanced debug logging ==="
DEBUG=1 install_enhanced_monitoring
echo "=== Test complete ==="
