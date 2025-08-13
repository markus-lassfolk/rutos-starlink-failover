#!/bin/sh
# Test the fixes for the multi-interface configuration

echo "Testing MWAN3 interface parsing fix..."

# Simulate the mwan3 interfaces output
cat << 'EOF' > /tmp/test_mwan3_output
Interface status:
 interface wan is online 00h:00m:40s, uptime 19h:02m:51s and tracking is active
 interface mob1s1a1 is online 00h:09m:06s, uptime 58h:50m:23s and tracking is active
 interface mob1s2a1 is offline and tracking is not enabled
 interface wan6 is offline and tracking is not enabled
 interface wg_klara is disabled and tracking is not enabled
EOF

echo "Raw mwan3 interfaces output:"
cat /tmp/test_mwan3_output
echo

echo "Testing FIXED parsing logic:"
# Extract only the interface lines (those starting with space + "interface")
grep "^ interface " /tmp/test_mwan3_output | sed 's/^ //' | while IFS= read -r interface_line; do
    interface_name=$(printf "%s" "$interface_line" | awk '{print $2}')
    echo "Parsed interface: '$interface_name'"
done

echo
echo "Expected interfaces: wan, mob1s1a1, mob1s2a1, wan6, wg_klara"

# Clean up
rm -f /tmp/test_mwan3_output

echo "Test completed. The parsing should now work correctly."
