#!/bin/sh
# shellcheck disable=SC1091 # Dynamic source files
# Test the extract_variable function directly

mkdir -p /tmp/debug-test

# Create test config
cat >/tmp/debug-test/test-config.sh <<'EOF'
#!/bin/sh
# Test configuration
export STARLINK_GRPC_HOST="192.168.1.100"
export MONITORING_INTERVAL="30"
export LOG_LEVEL="DEBUG"
export PUSHOVER_TOKEN="user123456"
EOF

echo "=== TEST CONFIG ==="
cat /tmp/debug-test/test-config.sh

echo ""
echo "=== TESTING EXTRACT_VARIABLE ==="

# Test the extract_variable extract_variable() {
	file="$1"
	var_name="$2"

	if [ -f "$file" ]; then
		# Extract exported variable value (handle both formats)
		grep "^[[:space:]]*export[[:space:]]*${var_name}=" "$file" |
			sed "s/^[[:space:]]*export[[:space:]]*${var_name}=[\"']\?//" |
			sed "s/[\"']\?[[:space:]]*$//" |
			head -n 1
	fi
}

echo "STARLINK_GRPC_HOST = '$(extract_variable /tmp/debug-test/test-config.sh STARLINK_GRPC_HOST)'"
echo "MONITORING_INTERVAL = '$(extract_variable /tmp/debug-test/test-config.sh MONITORING_INTERVAL)'"
echo "LOG_LEVEL = '$(extract_variable /tmp/debug-test/test-config.sh LOG_LEVEL)'"
echo "PUSHOVER_TOKEN = '$(extract_variable /tmp/debug-test/test-config.sh PUSHOVER_TOKEN)'"

echo ""
echo "=== CLEANUP ==="
rm -rf /tmp/debug-test
echo "Debug test completed!"
