#!/bin/sh
# Debug variable_exists function

# Create test files
(
    mkdir -p /tmp/debug-test
    cd /tmp/debug-test || exit

    cat >test-config.sh <<'EOF'
#!/bin/sh
# Test configuration
export STARLINK_GRPC_HOST="192.168.1.100"
export MONITORING_INTERVAL="30"
export LOG_LEVEL="DEBUG"
export PUSHOVER_TOKEN="user123456"
EOF

    cat >test-template.sh <<'EOF'
#!/bin/sh
# Configuration Template - Version 2.0
# Core Settings (always required)
export STARLINK_GRPC_HOST="192.168.100.1"
export STARLINK_GRPC_PORT="9200"
export MONITORING_INTERVAL="60"
export LOG_LEVEL="INFO"
# New Settings (added in v2.0)
export ENABLE_HEALTH_CHECK="true"
export HEALTH_CHECK_INTERVAL="300"
export BACKUP_RETENTION_DAYS="7"
EOF

    # Source the merge script functions
    # shellcheck disable=SC1091
    . ../scripts/merge-config.sh

    echo "=== TEST CONFIG ==="
    cat test-config.sh
    echo ""

    echo "=== TEST TEMPLATE ==="
    cat test-template.sh
    echo ""

    echo "=== TESTING VARIABLE_EXISTS ==="
    # Test variables that should exist
    echo "STARLINK_GRPC_HOST exists in config: $(variable_exists test-config.sh STARLINK_GRPC_HOST && echo 'YES' || echo 'NO')"
    echo "MONITORING_INTERVAL exists in config: $(variable_exists test-config.sh MONITORING_INTERVAL && echo 'YES' || echo 'NO')"
    echo "LOG_LEVEL exists in config: $(variable_exists test-config.sh LOG_LEVEL && echo 'YES' || echo 'NO')"
    echo "PUSHOVER_TOKEN exists in config: $(variable_exists test-config.sh PUSHOVER_TOKEN && echo 'YES' || echo 'NO')"

    # Test variables that don't exist
    echo "STARLINK_GRPC_PORT exists in config: $(variable_exists test-config.sh STARLINK_GRPC_PORT && echo 'YES' || echo 'NO')"
    echo "ENABLE_HEALTH_CHECK exists in config: $(variable_exists test-config.sh ENABLE_HEALTH_CHECK && echo 'YES' || echo 'NO')"

    echo ""
    echo "=== TESTING GET_ALL_VARIABLES ==="
    echo "Template variables: $(get_all_variables test-template.sh)"
    echo "Config variables: $(get_all_variables test-config.sh)"
)

echo ""
echo "=== CLEANUP ==="
rm -rf /tmp/debug-test
echo "Debug test completed!"
