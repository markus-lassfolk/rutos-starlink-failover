#!/bin/sh
# Minimal debug script

# Let's manually test the functions

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
variable_exists() {
    file="$1"
    var_name="$2"

    if [ -f "$file" ]; then
        grep -q "^[[:space:]]*export[[:space:]]*${var_name}=" "$file"
    else
        return 1
    fi
}

extract_variable() {
    file="$1"
    var_name="$2"

    if [ -f "$file" ]; then
        grep "^[[:space:]]*export[[:space:]]*${var_name}=" "$file" | head -1 | sed 's/^[[:space:]]*export[[:space:]]*[^=]*="\([^"]*\)".*/\1/'
    else
        return 1
    fi
}

# Create test files
mkdir -p /tmp/minimal-debug

cat >/tmp/minimal-debug/test-config.sh <<'EOF'
#!/bin/sh
export STARLINK_GRPC_HOST="192.168.1.100"
export MONITORING_INTERVAL="30"
export LOG_LEVEL="DEBUG"
EOF

echo "=== TESTING FUNCTIONS ==="
echo "File content:"
cat /tmp/minimal-debug/test-config.sh
echo ""

echo "Testing variable_exists:"
if variable_exists "/tmp/minimal-debug/test-config.sh" "STARLINK_GRPC_HOST"; then
    echo "STARLINK_GRPC_HOST exists: YES"
else
    echo "STARLINK_GRPC_HOST exists: NO"
fi

if variable_exists "/tmp/minimal-debug/test-config.sh" "MONITORING_INTERVAL"; then
    echo "MONITORING_INTERVAL exists: YES"
else
    echo "MONITORING_INTERVAL exists: NO"
fi

if variable_exists "/tmp/minimal-debug/test-config.sh" "LOG_LEVEL"; then
    echo "LOG_LEVEL exists: YES"
else
    echo "LOG_LEVEL exists: NO"
fi

echo ""
echo "Testing extract_variable:"
echo "STARLINK_GRPC_HOST = '$(extract_variable "/tmp/minimal-debug/test-config.sh" "STARLINK_GRPC_HOST")'"
echo "MONITORING_INTERVAL = '$(extract_variable "/tmp/minimal-debug/test-config.sh" "MONITORING_INTERVAL")'"
echo "LOG_LEVEL = '$(extract_variable "/tmp/minimal-debug/test-config.sh" "LOG_LEVEL")'"

echo ""
echo "=== CLEANUP ==="
rm -rf /tmp/minimal-debug
# Debug version display
if [ "$DEBUG" = "1" ]; then
    printf "Script version: %s\n" "$SCRIPT_VERSION"
fi

echo "Minimal debug completed!"
