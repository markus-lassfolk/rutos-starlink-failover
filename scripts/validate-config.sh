#!/bin/sh

# ==============================================================================
# Configuration Validation Script
#
# This script validates the configuration and checks system prerequisites
# before deploying the Starlink monitoring system.
#
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default config file location
CONFIG_FILE="${1:-./config.sh}"

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Check if config file exists
check_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
        echo -e "${YELLOW}Please copy config.template.sh to config.sh and customize it${NC}"
        exit 1
    fi
}

# Load configuration
load_config() {
    echo -e "${GREEN}Loading configuration from: $CONFIG_FILE${NC}"
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
}

# Check required binaries
check_binaries() {
    echo -e "${GREEN}Checking required binaries...${NC}"
    
    local missing_binaries=""
    
    # Check grpcurl
    if [ ! -f "$GRPCURL_CMD" ] && ! command -v grpcurl >/dev/null 2>&1; then
        missing_binaries="$missing_binaries grpcurl"
    fi
    
    # Check jq
    if [ ! -f "$JQ_CMD" ] && ! command -v jq >/dev/null 2>&1; then
        missing_binaries="$missing_binaries jq"
    fi
    
    # Check system commands
    for cmd in uci logger curl awk; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_binaries="$missing_binaries $cmd"
        fi
    done
    
    if [ -n "$missing_binaries" ]; then
        echo -e "${RED}Error: Missing required binaries:$missing_binaries${NC}"
        echo -e "${YELLOW}Please install the missing binaries before continuing${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All required binaries found${NC}"
}

# Check network connectivity
check_network() {
    echo -e "${GREEN}Checking network connectivity...${NC}"
    
    # Check Starlink API
    if ! timeout 5 nc -z "$(echo "$STARLINK_IP" | cut -d: -f1)" "$(echo "$STARLINK_IP" | cut -d: -f2)" 2>/dev/null; then
        echo -e "${YELLOW}Warning: Cannot reach Starlink API at $STARLINK_IP${NC}"
        echo -e "${YELLOW}This may be normal if Starlink is not currently active${NC}"
    else
        echo -e "${GREEN}✓ Starlink API reachable${NC}"
    fi
    
    # Check RUTOS API if configured
    if [ -n "${RUTOS_IP:-}" ]; then
        if ! timeout 5 nc -z "$RUTOS_IP" 80 2>/dev/null; then
            echo -e "${YELLOW}Warning: Cannot reach RUTOS API at $RUTOS_IP${NC}"
        else
            echo -e "${GREEN}✓ RUTOS API reachable${NC}"
        fi
    fi
}

# Check UCI configuration
check_uci() {
    echo -e "${GREEN}Checking UCI configuration...${NC}"
    
    # Check mwan3 interface
    if ! uci -q get mwan3."$MWAN_MEMBER" >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: mwan3 member '$MWAN_MEMBER' not found${NC}"
        echo -e "${YELLOW}Please configure mwan3 according to the documentation${NC}"
    else
        echo -e "${GREEN}✓ mwan3 member '$MWAN_MEMBER' found${NC}"
    fi
    
    # Check interface
    if ! uci -q get network."$MWAN_IFACE" >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Network interface '$MWAN_IFACE' not found${NC}"
    else
        echo -e "${GREEN}✓ Network interface '$MWAN_IFACE' found${NC}"
    fi
}

# Check directories
check_directories() {
    echo -e "${GREEN}Checking directories...${NC}"
    
    # Create directories if they don't exist
    for dir in "$STATE_DIR" "$LOG_DIR" "$DATA_DIR"; do
        if [ ! -d "$dir" ]; then
            echo -e "${YELLOW}Creating directory: $dir${NC}"
            mkdir -p "$dir"
        fi
        
        if [ ! -w "$dir" ]; then
            echo -e "${RED}Error: Directory not writable: $dir${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}✓ All directories accessible${NC}"
}

# Check configuration values
check_config_values() {
    echo -e "${GREEN}Checking configuration values...${NC}"
    
    # Check for placeholder values
    if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ]; then
        echo -e "${YELLOW}Warning: Pushover token not configured${NC}"
    fi
    
    if [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ]; then
        echo -e "${YELLOW}Warning: Pushover user key not configured${NC}"
    fi
    
    # Check threshold values
    if [ "$PACKET_LOSS_THRESHOLD" = "0" ] || [ "$OBSTRUCTION_THRESHOLD" = "0" ]; then
        echo -e "${YELLOW}Warning: Zero thresholds may cause issues${NC}"
    fi
    
    echo -e "${GREEN}✓ Configuration values checked${NC}"
}

# Test Starlink API
test_starlink_api() {
    echo -e "${GREEN}Testing Starlink API...${NC}"
    
    if timeout "$API_TIMEOUT" "$GRPCURL_CMD" -plaintext -max-time "$API_TIMEOUT" -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Starlink API test successful${NC}"
    else
        echo -e "${YELLOW}Warning: Starlink API test failed${NC}"
        echo -e "${YELLOW}This may be normal if Starlink is not currently active${NC}"
    fi
}

# Main function
main() {
    echo -e "${GREEN}=== Starlink System Configuration Validator ===${NC}"
    echo ""
    
    check_root
    check_config_file
    load_config
    check_binaries
    check_network
    check_uci
    check_directories
    check_config_values
    test_starlink_api
    
    echo ""
    echo -e "${GREEN}=== Validation Complete ===${NC}"
    echo -e "${GREEN}System appears ready for deployment${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "${YELLOW}1. Review any warnings above${NC}"
    echo -e "${YELLOW}2. Configure cron jobs as described in the documentation${NC}"
    echo -e "${YELLOW}3. Test the system manually before relying on it${NC}"
}

# Run main function
main
