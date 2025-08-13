#!/bin/sh
# Test deployment script to fix the interface parsing bug only

# Test the fixed multi-interface discovery and config generation

echo "Testing MWAN3 multi-interface discovery fixes..."

# Backup current config
cp /usr/local/starlink/config/config.sh /usr/local/starlink/config/config.sh.test-backup

echo "Running fixed interface discovery..."

# Discover interfaces using the FIXED logic
ALL_MWAN_INTERFACES=""
ALL_MWAN_MEMBERS=""
ALL_INTERFACE_TYPES=""
INTERFACE_COUNT=0

echo "Getting mwan3 interfaces..."
if mwan3_all_interfaces=$(mwan3 interfaces 2>/dev/null | grep "^ interface " | sed 's/^ //' || true); then
    echo "Raw interface output:"
    echo "$mwan3_all_interfaces"
    echo
    
    while IFS= read -r interface_line; do
        # Extract interface name - it's the 2nd word after "interface"
        interface_name=$(printf "%s" "$interface_line" | awk '{print $2}')
        
        if [ -n "$interface_name" ] && [ "$interface_name" != "status:" ]; then
            echo "Processing interface: '$interface_name'"
            
            # Find the member for this interface
            member_name=""
            if member_line=$(uci show mwan3 2>/dev/null | grep "interface='${interface_name}'" | head -1 2>/dev/null); then
                member_name=$(echo "$member_line" | cut -d'.' -f2)
                echo "  Found member: '$member_name'"
            else
                echo "  WARNING: No member found for interface '$interface_name', skipping"
                continue
            fi
            
            # Determine connection type
            connection_type="unlimited"  # Default
            case "$interface_name" in
                *mob* | *cellular* | *lte* | *gsm* | *wwan*)
                    connection_type="limited"
                    ;;
                *wifi* | *wlan*)
                    connection_type="unlimited"
                    ;;
                *)
                    # For other interfaces, assume unlimited (Starlink, ethernet, etc.)
                    connection_type="unlimited"
                    ;;
            esac
            
            echo "  Connection type: '$connection_type'"
            
            # Build comprehensive interface lists
            if [ -z "$ALL_MWAN_INTERFACES" ]; then
                ALL_MWAN_INTERFACES="$interface_name"
                ALL_MWAN_MEMBERS="$member_name"
                ALL_INTERFACE_TYPES="$interface_name:$connection_type"
            else
                ALL_MWAN_INTERFACES="$ALL_MWAN_INTERFACES,$interface_name"
                ALL_MWAN_MEMBERS="$ALL_MWAN_MEMBERS,$member_name"
                ALL_INTERFACE_TYPES="$ALL_INTERFACE_TYPES,$interface_name:$connection_type"
            fi
            
            INTERFACE_COUNT=$((INTERFACE_COUNT + 1))
            echo "  Added to lists (count now: $INTERFACE_COUNT)"
        fi
    done <<EOF
$mwan3_all_interfaces
EOF
fi

echo
echo "=== RESULTS ==="
echo "ALL_MWAN_INTERFACES='$ALL_MWAN_INTERFACES'"
echo "ALL_MWAN_MEMBERS='$ALL_MWAN_MEMBERS'"
echo "ALL_INTERFACE_TYPES='$ALL_INTERFACE_TYPES'"  
echo "INTERFACE_COUNT='$INTERFACE_COUNT'"
echo

# Now update the config file with the CORRECT values
if [ -n "$ALL_MWAN_INTERFACES" ] && [ "$INTERFACE_COUNT" -gt 0 ]; then
    echo "Updating config file with discovered interfaces..."
    
    # Replace the broken placeholders with real values
    sed -i "s|export MWAN_ALL_INTERFACES=\".*\"|export MWAN_ALL_INTERFACES=\"$ALL_MWAN_INTERFACES\"|" /usr/local/starlink/config/config.sh
    sed -i "s|export MWAN_ALL_MEMBERS=\".*\"|export MWAN_ALL_MEMBERS=\"$ALL_MWAN_MEMBERS\"|" /usr/local/starlink/config/config.sh
    sed -i "s|export MWAN_INTERFACE_TYPES=\".*\"|export MWAN_INTERFACE_TYPES=\"$ALL_INTERFACE_TYPES\"|" /usr/local/starlink/config/config.sh
    sed -i "s|export MWAN_INTERFACE_COUNT=\".*\"|export MWAN_INTERFACE_COUNT=\"$INTERFACE_COUNT\"|" /usr/local/starlink/config/config.sh
    
    echo "Config updated successfully!"
    echo
    echo "=== VERIFICATION ==="
    echo "New config values:"
    grep "MWAN_ALL_" /usr/local/starlink/config/config.sh
    grep "MWAN_INTERFACE_COUNT" /usr/local/starlink/config/config.sh
    grep "MWAN_INTERFACE_TYPES" /usr/local/starlink/config/config.sh
else
    echo "ERROR: Interface discovery failed or no interfaces found"
fi

echo
echo "Test completed!"
