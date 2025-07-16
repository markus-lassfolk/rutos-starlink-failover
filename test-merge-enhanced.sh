#!/bin/sh
# Enhanced test to show exactly how the merge works

mkdir -p /tmp/merge-test

# Create a proper template with different values
cat >/tmp/merge-test/config.template.sh <<'EOF'
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

# Create user's existing config with different values
cat >/tmp/merge-test/config.sh <<'EOF'
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
echo "Template has:"
grep "^export" /tmp/merge-test/config.template.sh | head -4
echo ""
echo "User config has:"
grep "^export" /tmp/merge-test/config.sh | head -4
echo ""

echo "=== RUNNING MERGE ==="
./scripts/merge-config.sh \
	/tmp/merge-test/config.template.sh \
	/tmp/merge-test/config.sh \
	/tmp/merge-test/config.sh

echo ""
echo "=== AFTER MERGE ==="
echo "Result has:"
grep "^export" /tmp/merge-test/config.sh | head -4
echo ""
echo "Full result:"
cat /tmp/merge-test/config.sh

echo ""
echo "=== CLEANUP ==="
rm -rf /tmp/merge-test
echo "Enhanced test completed!"
