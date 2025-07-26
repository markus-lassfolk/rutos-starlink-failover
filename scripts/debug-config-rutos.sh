#!/bin/sh

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"

# Debug configuration checker
echo "=== CONFIG FILE DEBUG ==="
echo "CONFIG_FILE: ${CONFIG_FILE:-/etc/starlink-config/config.sh}"
echo ""

if [ -f "${CONFIG_FILE:-/etc/starlink-config/config.sh}" ]; then
    echo "=== CONFIG FILE CONTENTS ==="
    cat "${CONFIG_FILE:-/etc/starlink-config/config.sh}"
    echo ""
    echo "=== STARLINK VARIABLES IN CONFIG ==="
    grep "STARLINK" "${CONFIG_FILE:-/etc/starlink-config/config.sh}" || echo "No STARLINK variables found"
    echo ""
else
    echo "Config file not found!"
fi

echo "=== CURRENT ENVIRONMENT VARIABLES ==="
echo "STARLINK_IP: ${STARLINK_IP:-NOT_SET}"
echo "STARLINK_PORT: ${STARLINK_PORT:-NOT_SET}"
echo "GRPCURL_CMD: ${GRPCURL_CMD:-NOT_SET}"
echo ""

if [ -n "${CONFIG_FILE:-}" ] && [ -f "${CONFIG_FILE:-}" ]; then
    echo "=== LOADING CONFIG AND CHECKING VARIABLES ==="
    # shellcheck source=/dev/null
    . "${CONFIG_FILE:-/etc/starlink-config/config.sh}"
    echo "After loading config:"
    echo "STARLINK_IP: ${STARLINK_IP:-NOT_SET}"
    echo "STARLINK_PORT: ${STARLINK_PORT:-NOT_SET}"
    echo "GRPCURL_CMD: ${GRPCURL_CMD:-NOT_SET}"
    echo ""

    if echo "${STARLINK_IP:-}" | grep -q ":"; then
        echo "🚨 CRITICAL ISSUE FOUND!"
        echo "STARLINK_IP contains port: $STARLINK_IP"
        echo "This should be: STARLINK_IP=192.168.100.1 and STARLINK_PORT=9200"
        echo ""
        echo "=== SUGGESTED FIX ==="
        echo "Edit /etc/starlink-config/config.sh and change:"
        echo "FROM: export STARLINK_IP=\"192.168.100.1\""
        echo "FROM: export STARLINK_PORT=\"9200\""
        echo "TO:   export STARLINK_IP=\"192.168.100.1\""
        echo "      export STARLINK_PORT=\"9200\""
    else
        echo "✅ STARLINK_IP format looks correct"
    fi
fi

echo ""
echo "=== GRPCURL CONNECTION TEST ==="
if [ -n "${GRPCURL_CMD:-}" ] && [ -x "${GRPCURL_CMD:-}" ]; then
    echo "Testing: $GRPCURL_CMD -plaintext -d '{}' $STARLINK_IP:$STARLINK_PORT SpaceX.API.Device.Device/Handle"
    if timeout 5 "$GRPCURL_CMD" -plaintext -d '{}' "$STARLINK_IP:$STARLINK_PORT" SpaceX.API.Device.Device/Handle >/dev/null 2>&1; then
        echo "✅ Connection successful!"
    else
        echo "❌ Connection failed!"
        echo "Check:"
        echo "1. Starlink dish is powered and connected"
        echo "2. IP address is correct ($STARLINK_IP)"
        echo "3. Port is correct ($STARLINK_PORT)"
        echo "4. Network connectivity to Starlink"
    fi
else
    echo "❌ GRPCURL_CMD not found or not executable: ${GRPCURL_CMD:-NOT_SET}"
fi
