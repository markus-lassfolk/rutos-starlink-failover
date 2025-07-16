#!/bin/sh

# Debug script to check config format issues
CONFIG_FILE="${1:-./config.sh}"

echo "=== CONFIG FILE ANALYSIS ==="
echo "File: $CONFIG_FILE"
echo

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE"
    exit 1
fi

echo "=== EXPORT VARIABLES ==="
grep -n "^export [A-Z_]*=" "$CONFIG_FILE" | head -10

echo
echo "=== NON-EXPORT VARIABLES ==="
grep -n "^[A-Z_]*=" "$CONFIG_FILE" | head -10

echo
echo "=== VARIABLE COUNT ==="
export_count=$(grep -c "^export [A-Z_]*=" "$CONFIG_FILE" 2>/dev/null || echo 0)
nonexport_count=$(grep -c "^[A-Z_]*=" "$CONFIG_FILE" 2>/dev/null || echo 0)
echo "Export format: $export_count"
echo "Non-export format: $nonexport_count"
echo "Total: $((export_count + nonexport_count))"

echo
echo "=== CRITICAL VARIABLES CHECK ==="
for var in STARLINK_IP MWAN_IFACE MWAN_MEMBER CHECK_INTERVAL; do
    # Try both formats
    value=$(grep "^export $var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    if [ -z "$value" ]; then
        value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    
    if [ -n "$value" ]; then
        echo "✓ $var = '$value'"
    else
        echo "✗ $var = NOT FOUND"
    fi
done

echo
echo "=== TEMPLATE COMPARISON ==="
template_file="/root/starlink-monitor/config/config.template.sh"
if [ -f "$template_file" ]; then
    echo "Template file exists: $template_file"
    template_vars=$(grep -E '^export [A-Z_]+=.*' "$template_file" | sed 's/^export //' | cut -d'=' -f1 | sort)
    config_vars=$(grep -E '^[A-Z_]+=.*' "$CONFIG_FILE" | cut -d'=' -f1 | sort)
    
    echo "Template variables:"
    echo "$template_vars"
    echo
    echo "Config variables:"
    echo "$config_vars"
    echo
    echo "Missing from config:"
    echo "$template_vars" | while read -r var; do
        if ! echo "$config_vars" | grep -q "^$var$"; then
            echo "  - $var"
        fi
    done
else
    echo "Template file not found: $template_file"
fi
