#!/bin/sh

# Script to add missing CHECK_INTERVAL to user's config
CONFIG_FILE="${1:-./config.sh}"

echo "=== Adding missing CHECK_INTERVAL to config ==="
echo "File: $CONFIG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Check if CHECK_INTERVAL already exists
if grep -q "^CHECK_INTERVAL=" "$CONFIG_FILE" || grep -q "^export CHECK_INTERVAL=" "$CONFIG_FILE"; then
    echo "CHECK_INTERVAL already exists in config"
    exit 0
fi

# Find a good place to add it - after API_TIMEOUT if it exists, or after LATENCY_THRESHOLD_MS
insert_after=""
if grep -q "^API_TIMEOUT=" "$CONFIG_FILE" || grep -q "^export API_TIMEOUT=" "$CONFIG_FILE"; then
    insert_after="API_TIMEOUT"
elif grep -q "^LATENCY_THRESHOLD_MS=" "$CONFIG_FILE" || grep -q "^export LATENCY_THRESHOLD_MS=" "$CONFIG_FILE"; then
    insert_after="LATENCY_THRESHOLD_MS"
fi

if [ -n "$insert_after" ]; then
    echo "Adding CHECK_INTERVAL after $insert_after..."
    
    # Create backup
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
    
    # Add CHECK_INTERVAL after the found variable
    awk -v insert_after="$insert_after" '
    /^(export )?'"$insert_after"'=/ { 
        print $0; 
        print ""; 
        print "# Check interval in seconds (how often to test Starlink)"; 
        print "CHECK_INTERVAL=30"; 
        next 
    } 
    { print }' "$CONFIG_FILE.backup" > "$CONFIG_FILE"
    
    echo "✓ CHECK_INTERVAL added successfully"
    echo "✓ Backup created: $CONFIG_FILE.backup"
else
    echo "Could not find suitable location to add CHECK_INTERVAL"
    echo "Please add this line manually:"
    echo "CHECK_INTERVAL=30"
    exit 1
fi
