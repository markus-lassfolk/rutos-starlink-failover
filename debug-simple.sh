#!/bin/sh
# Debug variable_exists function

# Create test files
mkdir -p /tmp/debug-test
cd /tmp/debug-test

cat >test-config.sh <<'EOF'
#!/bin/sh
# Test configuration
export STARLINK_GRPC_HOST="192.168.1.100"
export MONITORING_INTERVAL="30"
export LOG_LEVEL="DEBUG"
export PUSHOVER_TOKEN="user123456"
EOF

# Run the merge script with debugging
cd /c/GitHub/rutos-starlink-failover
bash scripts/merge-config.sh --debug /tmp/debug-test/test-config.sh config/config.template.sh /tmp/debug-test/merged-config.sh

echo ""
echo "=== RESULT ==="
cat /tmp/debug-test/merged-config.sh | grep -E "(STARLINK_GRPC_HOST|MONITORING_INTERVAL|LOG_LEVEL)="

echo ""
echo "=== CLEANUP ==="
rm -rf /tmp/debug-test
echo "Debug test completed!"
