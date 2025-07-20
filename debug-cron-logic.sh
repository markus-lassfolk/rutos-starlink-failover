#!/bin/sh

# Quick debug script to test the cron check logic

CRON_FILE="/etc/crontabs/root"

echo "Testing cron entry checking logic"
echo "================================"

# Check current crontab content
echo "Current crontab content:"
cat "$CRON_FILE"
echo ""

# Test the exact same logic as install script
existing_monitor=$(grep -c "starlink_monitor-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")
existing_logger=$(grep -c "starlink_logger-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0") 
existing_api_check=$(grep -c "check_starlink_api" "$CRON_FILE" 2>/dev/null || echo "0")
existing_maintenance=$(grep -c "system-maintenance-rutos.sh" "$CRON_FILE" 2>/dev/null || echo "0")

# Clean any whitespace/newlines from the counts (fix for RUTOS busybox)
existing_monitor=$(echo "$existing_monitor" | tr -d '\n\r' | sed 's/[^0-9]//g')
existing_logger=$(echo "$existing_logger" | tr -d '\n\r' | sed 's/[^0-9]//g')
existing_api_check=$(echo "$existing_api_check" | tr -d '\n\r' | sed 's/[^0-9]//g')
existing_maintenance=$(echo "$existing_maintenance" | tr -d '\n\r' | sed 's/[^0-9]//g')

# Ensure we have valid numbers (default to 0 if empty)
existing_monitor=${existing_monitor:-0}
existing_logger=${existing_logger:-0}
existing_api_check=${existing_api_check:-0}
existing_maintenance=${existing_maintenance:-0}

echo "Counts:"
echo "  existing_monitor='$existing_monitor'"
echo "  existing_logger='$existing_logger'"
echo "  existing_api_check='$existing_api_check'"
echo "  existing_maintenance='$existing_maintenance'"
echo ""

echo "Testing conditions:"
echo "  [ \$existing_monitor -eq 0 ] = $([ "$existing_monitor" -eq 0 ] && echo "true" || echo "false")"
echo "  [ \$existing_logger -eq 0 ] = $([ "$existing_logger" -eq 0 ] && echo "true" || echo "false")"
echo "  [ \$existing_api_check -eq 0 ] = $([ "$existing_api_check" -eq 0 ] && echo "true" || echo "false")"
echo "  [ \$existing_maintenance -eq 0 ] = $([ "$existing_maintenance" -eq 0 ] && echo "true" || echo "false")"
echo ""

echo "What should happen:"
if [ "$existing_maintenance" -eq 0 ]; then
    echo "  ✓ Should ADD system-maintenance cron entry (existing_maintenance=$existing_maintenance)"
else
    echo "  ⚠ Should SKIP system-maintenance cron entry (existing_maintenance=$existing_maintenance)"
fi
