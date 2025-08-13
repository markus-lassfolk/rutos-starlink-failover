#!/bin/sh
# Test script to simulate the exact bootstrap environment

set -e

echo "=== Simulating Bootstrap Environment ==="

# Create temp directory like bootstrap does
temp_dir="/tmp/test-bootstrap-env-$$"
mkdir -p "$temp_dir/lib"

echo "1. Downloading library files to temp directory..."

# Download the library files
curl -fsSL "https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/lib/rutos-lib.sh" \
    -o "$temp_dir/lib/rutos-lib.sh"
curl -fsSL "https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/lib/rutos-colors.sh" \
    -o "$temp_dir/lib/rutos-colors.sh"
curl -fsSL "https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/lib/rutos-logging.sh" \
    -o "$temp_dir/lib/rutos-logging.sh"
curl -fsSL "https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/lib/rutos-common.sh" \
    -o "$temp_dir/lib/rutos-common.sh"
curl -fsSL "https://raw.githubusercontent.com/markus-lassfolk/rutos-starlink-failover/main/scripts/lib/rutos-compatibility.sh" \
    -o "$temp_dir/lib/rutos-compatibility.sh"

echo "2. Testing library loading in exact bootstrap environment..."

# Create a test script that mimics install-rutos.sh library loading
cat >"$temp_dir/test-install.sh" <<'EOF'
#!/bin/sh
set -eu

# Mimic install-rutos.sh exactly
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION

echo "Testing library loading..."
echo "Script location: $0"
echo "Library path: $(dirname "$0")/lib/rutos-lib.sh"
echo "Library exists: $([ -f "$(dirname "$0")/lib/rutos-lib.sh" ] && echo 'yes' || echo 'no')"

echo "About to source library..."
if . "$(dirname "$0")/lib/rutos-lib.sh"; then
    echo "✅ Library loaded successfully!"
    echo "Testing log function..."
    log_info "Library test successful"
else
    lib_error=$?
    echo "❌ Library loading failed with exit code: $lib_error"
    echo "Trying to source with error output..."
    . "$(dirname "$0")/lib/rutos-lib.sh" || true
    exit $lib_error
fi
EOF

chmod +x "$temp_dir/test-install.sh"

echo "3. Running test in bootstrap environment..."
cd "$temp_dir"
sh test-install.sh

echo "4. Cleaning up..."
cd /
rm -rf "$temp_dir"

echo "=== Test Complete ==="
