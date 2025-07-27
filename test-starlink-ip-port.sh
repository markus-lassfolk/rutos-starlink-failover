#!/bin/sh
# Test script to verify STARLINK_IP and STARLINK_PORT are properly combined
# Version: 1.0.0

set -e

# Version information
SCRIPT_VERSION="1.0.0"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;35m'
NC='\033[0m'

printf "%s=== Starlink IP:PORT Configuration Test ===%s\n" "$GREEN" "$NC"
printf "Testing all scripts to verify proper STARLINK_IP:STARLINK_PORT usage\n\n"

# Create a test config file with both IP and PORT
TEST_CONFIG="/tmp/test-starlink-ip-port-config.sh"
printf "%sCreating test configuration with separate IP and PORT: %s%s\n" "$YELLOW" "$TEST_CONFIG" "$NC"

cat > "$TEST_CONFIG" << 'EOF'
# Test configuration for STARLINK_IP and STARLINK_PORT
STARLINK_IP="192.168.100.1"
STARLINK_PORT="9200"
MWAN_IFACE="starlink"
MWAN_MEMBER="starlink_m1_w1"
ENABLE_GPS_TRACKING="true"
ENABLE_CELLULAR_TRACKING="false"
LOG_DIR="/tmp/starlink-test-logs"
LOG_TAG="StarlinkTest"
EOF

printf "Test config created with STARLINK_IP=192.168.100.1 and STARLINK_PORT=9200\n\n"

# Function to check for proper IP:PORT usage
check_script_grpc_calls() {
    script_path="$1"
    script_name="$(basename "$script_path")"
    
    printf "%sTesting: %s%s\n" "$BLUE" "$script_name" "$NC"
    
    if [ ! -f "$script_path" ]; then
        printf "%s✗ Script not found: %s%s\n" "$RED" "$script_path" "$NC"
        return 1
    fi
    
    # Check if script defines both STARLINK_IP and STARLINK_PORT
    has_ip_default=$(grep -c 'STARLINK_IP.*:-.*192\.168\.100\.1' "$script_path" 2>/dev/null || echo "0")
    has_port_default=$(grep -c 'STARLINK_PORT.*:-.*9200' "$script_path" 2>/dev/null || echo "0")
    
    # Check if script uses IP:PORT in grpc calls
    grpc_with_port=$(grep -c '\$STARLINK_IP:\$STARLINK_PORT' "$script_path" 2>/dev/null || echo "0")
    grpc_without_port=$(grep -c '\$STARLINK_IP[^:].*SpaceX\.API' "$script_path" 2>/dev/null || echo "0")
    
    printf "  STARLINK_IP default: %s, STARLINK_PORT default: %s\n" "$has_ip_default" "$has_port_default"
    printf "  gRPC with port: %s, gRPC without port: %s\n" "$grpc_with_port" "$grpc_without_port"
    
    # Validate results
    if [ "$has_ip_default" -gt 0 ] && [ "$has_port_default" -gt 0 ]; then
        printf "%s✓ Both STARLINK_IP and STARLINK_PORT defaults found%s\n" "$GREEN" "$NC"
    else
        printf "%s⚠ Missing default definitions%s\n" "$YELLOW" "$NC"
    fi
    
    if [ "$grpc_with_port" -gt 0 ] && [ "$grpc_without_port" -eq 0 ]; then
        printf "%s✓ All gRPC calls use IP:PORT format%s\n" "$GREEN" "$NC"
    elif [ "$grpc_without_port" -gt 0 ]; then
        printf "%s✗ Found %s gRPC calls missing port%s\n" "$RED" "$grpc_without_port" "$NC"
        # Show the problematic lines
        grep -n '\$STARLINK_IP[^:].*SpaceX\.API' "$script_path" 2>/dev/null | head -3 || true
    else
        printf "%s- No gRPC calls found in this script%s\n" "$YELLOW" "$NC"
    fi
    
    # Test debug output with our config
    printf "  Testing debug output with separate IP and PORT...\n"
    DEBUG=1 RUTOS_TEST_MODE=1 CONFIG_FILE="$TEST_CONFIG" timeout 8s sh "$script_path" 2>&1 | \
        grep -E "STARLINK_IP|STARLINK_PORT" | head -5 || {
        printf "%s⚠ No debug output for STARLINK variables (may use library early exit)%s\n" "$YELLOW" "$NC"
    }
    
    printf "\n"
}

# Test all the main scripts
printf "%sTesting main monitoring scripts:%s\n" "$BLUE" "$NC"
check_script_grpc_calls "Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh"
check_script_grpc_calls "Starlink-RUTOS-Failover/starlink_logger_unified-rutos.sh"
check_script_grpc_calls "Starlink-RUTOS-Failover/check_starlink_api-rutos.sh"

printf "%sTesting legacy scripts:%s\n" "$BLUE" "$NC"
check_script_grpc_calls "Starlink-RUTOS-Failover/starlink_logger-rutos.sh"

printf "%sTesting utility scripts:%s\n" "$BLUE" "$NC"
check_script_grpc_calls "Starlink-RUTOS-Failover/generate_api_docs.sh"

# Check the configuration template for proper format
printf "%sTesting configuration template:%s\n" "$BLUE" "$NC"
if [ -f "config/config.unified.template.sh" ]; then
    printf "Checking config template for separate IP and PORT variables...\n"
    
    template_has_separate=$(grep -c 'STARLINK_IP=.*STARLINK_PORT=' "config/config.unified.template.sh" 2>/dev/null || echo "0")
    template_has_combined=$(grep -c 'STARLINK_.*192\.168\.100\.1:9200' "config/config.unified.template.sh" 2>/dev/null || echo "0")
    
    if [ "$template_has_separate" -gt 0 ] || (grep -q 'STARLINK_IP=' "config/config.unified.template.sh" 2>/dev/null && grep -q 'STARLINK_PORT=' "config/config.unified.template.sh" 2>/dev/null); then
        printf "%s✓ Template uses separate STARLINK_IP and STARLINK_PORT variables%s\n" "$GREEN" "$NC"
    elif [ "$template_has_combined" -gt 0 ]; then
        printf "%s⚠ Template may still use combined IP:PORT format%s\n" "$YELLOW" "$NC"
    else
        printf "%s? Could not determine template format%s\n" "$YELLOW" "$NC"
    fi
    
    # Show the relevant lines
    printf "Template Starlink configuration:\n"
    grep -A 2 -B 2 "STARLINK" "config/config.unified.template.sh" 2>/dev/null | head -10 || true
else
    printf "%s⚠ Configuration template not found%s\n" "$YELLOW" "$NC"
fi

# Cleanup
printf "\n%sCleaning up test files%s\n" "$YELLOW" "$NC"
rm -f "$TEST_CONFIG"

printf "\n%s=== Test Summary ===%s\n" "$GREEN" "$NC"
printf "Expected results:\n"
printf "✓ All scripts should define both STARLINK_IP and STARLINK_PORT with defaults\n"
printf "✓ All gRPC calls should use \$STARLINK_IP:\$STARLINK_PORT format\n"
printf "✓ Configuration debug output should show both IP and PORT separately\n"
printf "✓ No gRPC calls should use only \$STARLINK_IP without port\n"
