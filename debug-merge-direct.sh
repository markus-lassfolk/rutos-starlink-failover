#!/bin/sh
# Debug merge function directly

# Create test files

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
mkdir -p /tmp/debug-test

cat >/tmp/debug-test/test-config.sh <<'EOF'
#!/bin/sh
# Test configuration
export STARLINK_GRPC_HOST="192.168.1.100"
export MONITORING_INTERVAL="30"
export LOG_LEVEL="DEBUG"
export PUSHOVER_TOKEN="user123456"
EOF

echo "=== TESTING MERGE WITH DEBUG ==="
wsl bash scripts/merge-config.sh --debug /tmp/debug-test/test-config.sh config/config.template.sh /tmp/debug-test/merged-config.sh

echo ""
echo "=== RESULT ==="
grep -E "(STARLINK_GRPC_HOST|MONITORING_INTERVAL|LOG_LEVEL)=" /tmp/debug-test/merged-config.sh

echo ""
echo "=== CLEANUP ==="
rm -rf /tmp/debug-test
# Debug version display
if [ "$DEBUG" = "1" ]; then
    printf "Script version: %s\n" "$SCRIPT_VERSION"
fi

echo "Debug test completed!"
