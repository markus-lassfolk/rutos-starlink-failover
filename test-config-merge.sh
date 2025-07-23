#!/bin/sh
# Test script to demonstrate the new configuration merging system

# Create test files

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
# Used for troubleshooting: echo "Configuration version: $SCRIPT_VERSION"
mkdir -p /tmp/config-test

# Create a "current" template (simulating new version)
cat >/tmp/config-test/config.template.sh <<'EOF'
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

# Advanced Settings (optional)
export ENABLE_ADVANCED_LOGGING="false"
export CUSTOM_ALERTS="false"
EOF

# Create an "existing" config (simulating user's current config)
cat >/tmp/config-test/config.sh <<'EOF'
#!/bin/sh
# User's existing configuration

# Core Settings (user has customized these)
export STARLINK_GRPC_HOST="192.168.1.100"
export STARLINK_GRPC_PORT="9200"
export MONITORING_INTERVAL="30"
export LOG_LEVEL="DEBUG"

# Old Settings (no longer in template)
export OLD_TIMEOUT_SETTING="120"
export DEPRECATED_FEATURE="enabled"

# Advanced Settings (user added these)
export PUSHOVER_TOKEN="user123456"
export PUSHOVER_USER="app789012"
EOF

echo "=== BEFORE MERGE ==="
echo "Template (new version):"
cat /tmp/config-test/config.template.sh
echo ""
echo "Existing config (user's current):"
cat /tmp/config-test/config.sh
echo ""

echo "=== RUNNING MERGE ==="
DEBUG=1 ./scripts/merge-config.sh \
    /tmp/config-test/config.template.sh \
    /tmp/config-test/config.sh \
    /tmp/config-test/config.sh

echo ""
echo "=== AFTER MERGE ==="
echo "Merged configuration:"
cat /tmp/config-test/config.sh

echo ""
echo "=== CLEANUP ==="
rm -rf /tmp/config-test
echo "Test completed successfully!"
