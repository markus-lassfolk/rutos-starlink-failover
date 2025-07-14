#!/bin/sh

# ==============================================================================
# Configuration Validation Script
#
# This script validates the configuration and checks system prerequisites
# before deploying the Starlink monitoring system.
#
# ==============================================================================

set -eu

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
        printf "%b\n" "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Check if config file exists
check_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        printf "%b\n" "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
        printf "%b\n" "${YELLOW}Please copy config.template.sh to config.sh and customize it${NC}"
        exit 1
    fi
}

# Load configuration
load_config() {
    printf "%b\n" "${GREEN}Loading configuration from: $CONFIG_FILE${NC}"
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
}

# Check required binaries
check_binaries() {
    printf "%b\n" "${GREEN}Checking required binaries...${NC}"

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
        printf "%b\n" "${RED}Error: Missing required binaries:$missing_binaries${NC}"
        printf "%b\n" "${YELLOW}Please install the missing binaries before continuing${NC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}✓ All required binaries found${NC}"
}

# Check network connectivity
check_network() {
    printf "%b\n" "${GREEN}Checking network connectivity...${NC}"

    # Check Starlink API
    if ! timeout 5 nc -z "$(echo "$STARLINK_IP" | cut -d: -f1)" "$(echo "$STARLINK_IP" | cut -d: -f2)" 2>/dev/null; then
        printf "%b\n" "${YELLOW}Warning: Cannot reach Starlink API at $STARLINK_IP${NC}"
        printf "%b\n" "${YELLOW}This may be normal if Starlink is not currently active${NC}"
    else
        printf "%b\n" "${GREEN}✓ Starlink API reachable${NC}"
    fi

    # Check RUTOS API if configured
    if [ -n "${RUTOS_IP:-}" ]; then
        if ! timeout 5 nc -z "$RUTOS_IP" 80 2>/dev/null; then
            printf "%b\n" "${YELLOW}Warning: Cannot reach RUTOS API at $RUTOS_IP${NC}"
        else
            printf "%b\n" "${GREEN}✓ RUTOS API reachable${NC}"
        fi
    fi
}

# Check UCI configuration
check_uci() {
    printf "%b\n" "${GREEN}Checking UCI configuration...${NC}"

    # Check mwan3 interface
    if ! uci -q get mwan3."$MWAN_MEMBER" >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Warning: mwan3 member '$MWAN_MEMBER' not found${NC}"
        printf "%b\n" "${YELLOW}Please configure mwan3 according to the documentation${NC}"
    else
        printf "%b\n" "${GREEN}✓ mwan3 member '$MWAN_MEMBER' found${NC}"
    fi

    # Check interface
    if ! uci -q get network."$MWAN_IFACE" >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Warning: Network interface '$MWAN_IFACE' not found${NC}"
    else
        printf "%b\n" "${GREEN}✓ Network interface '$MWAN_IFACE' found${NC}"
    fi
}

# Check directories
check_directories() {
    printf "%b\n" "${GREEN}Checking directories...${NC}"

    # Create directories if they don't exist
    for dir in "$STATE_DIR" "$LOG_DIR" "$DATA_DIR"; do
        if [ ! -d "$dir" ]; then
            printf "%b\n" "${YELLOW}Creating directory: $dir${NC}"
            mkdir -p "$dir"
        fi

        if [ ! -w "$dir" ]; then
            printf "%b\n" "${RED}Error: Directory not writable: $dir${NC}"
            exit 1
        fi
    done

    printf "%b\n" "${GREEN}✓ All directories accessible${NC}"
}

# Check configuration values
check_config_values() {
    printf "%b\n" "${GREEN}Checking configuration values...${NC}"

    # Check for placeholder values
    if [ "$PUSHOVER_TOKEN" = "YOUR_PUSHOVER_API_TOKEN" ]; then
        printf "%b\n" "${YELLOW}Warning: Pushover token not configured${NC}"
    fi

    if [ "$PUSHOVER_USER" = "YOUR_PUSHOVER_USER_KEY" ]; then
        printf "%b\n" "${YELLOW}Warning: Pushover user key not configured${NC}"
    fi

    # Check threshold values
    if [ "$PACKET_LOSS_THRESHOLD" = "0" ] || [ "$OBSTRUCTION_THRESHOLD" = "0" ]; then
        printf "%b\n" "${YELLOW}Warning: Zero thresholds may cause issues${NC}"
    fi

    printf "%b\n" "${GREEN}✓ Configuration values checked${NC}"
}

# Test Starlink API
test_starlink_api() {
    printf "%b\n" "${GREEN}Testing Starlink API...${NC}"

    if timeout "$API_TIMEOUT" "$GRPCURL_CMD" -plaintext -max-time "$API_TIMEOUT" -d '{"get_status":{}}' "$STARLINK_IP" SpaceX.API.Device.Device/Handle >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ Starlink API test successful${NC}"
    else
        printf "%b\n" "${YELLOW}Warning: Starlink API test failed${NC}"
        printf "%b\n" "${YELLOW}This may be normal if Starlink is not currently active${NC}"
    fi
}

# Extract variable names from template
extract_template_variables() {
    local template_file="$1"
    if [ ! -f "$template_file" ]; then
        return 1
    fi
    
    # Extract variables (exclude comments and empty lines)
    grep -E '^[A-Z_]+=.*' "$template_file" | cut -d'=' -f1 | sort
}

# Get current config variables
extract_config_variables() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Extract variables from config file
    grep -E '^[A-Z_]+=.*' "$config_file" | cut -d'=' -f1 | sort
}

# Compare configuration completeness
check_config_completeness() {
    printf "%b\n" "${GREEN}Checking configuration completeness...${NC}"
    
    # Try to find template file
    local template_file=""
    local config_dir="$(dirname "$CONFIG_FILE")"
    
    # Look for template in same directory as config file
    if [ -f "$config_dir/config.template.sh" ]; then
        template_file="$config_dir/config.template.sh"
    elif [ -f "$config_dir/config.advanced.template.sh" ]; then
        template_file="$config_dir/config.advanced.template.sh"
    # Look in parent directory
    elif [ -f "$config_dir/../config/config.template.sh" ]; then
        template_file="$config_dir/../config/config.template.sh"
    elif [ -f "$config_dir/../config/config.advanced.template.sh" ]; then
        template_file="$config_dir/../config/config.advanced.template.sh"
    else
        printf "%b\n" "${YELLOW}Warning: Could not find template file for comparison${NC}"
        return 0
    fi
    
    printf "%b\n" "${GREEN}Comparing against template: $template_file${NC}"
    
    # Get variables from both files
    local temp_template="/tmp/template_vars.$$"
    local temp_config="/tmp/config_vars.$$"
    
    if ! extract_template_variables "$template_file" > "$temp_template"; then
        printf "%b\n" "${RED}Error: Could not extract template variables${NC}"
        return 1
    fi
    
    if ! extract_config_variables "$CONFIG_FILE" > "$temp_config"; then
        printf "%b\n" "${RED}Error: Could not extract config variables${NC}"
        return 1
    fi
    
    # Find missing variables
    local missing_vars=""
    local extra_vars=""
    local total_missing=0
    local total_extra=0
    
    # Check for missing variables (in template but not in config)
    while IFS= read -r var; do
        if ! grep -q "^$var$" "$temp_config"; then
            missing_vars="$missing_vars $var"
            total_missing=$((total_missing + 1))
        fi
    done < "$temp_template"
    
    # Check for extra variables (in config but not in template)
    while IFS= read -r var; do
        if ! grep -q "^$var$" "$temp_template"; then
            extra_vars="$extra_vars $var"
            total_extra=$((total_extra + 1))
        fi
    done < "$temp_config"
    
    # Cleanup temp files
    rm -f "$temp_template" "$temp_config"
    
    # Report results
    if [ $total_missing -eq 0 ] && [ $total_extra -eq 0 ]; then
        printf "%b\n" "${GREEN}✓ Configuration is complete and matches template${NC}"
        return 0
    fi
    
    if [ $total_missing -gt 0 ]; then
        printf "%b\n" "${YELLOW}⚠ Missing configuration variables (${total_missing} found):${NC}"
        for var in $missing_vars; do
            printf "%b\n" "${YELLOW}  - $var${NC}"
        done
        printf "%b\n" "${YELLOW}Suggestion: Run update-config.sh to add missing variables${NC}"
    fi
    
    if [ $total_extra -gt 0 ]; then
        printf "%b\n" "${YELLOW}⚠ Extra configuration variables (${total_extra} found):${NC}"
        for var in $extra_vars; do
            printf "%b\n" "${YELLOW}  - $var${NC}"
        done
        printf "%b\n" "${YELLOW}Note: These may be custom variables or from an older version${NC}"
    fi
    
    return 1
}

# Check for placeholder values and provide recommendations
check_placeholder_values() {
    printf "%b\n" "${GREEN}Checking for placeholder values...${NC}"
    
    local placeholders_found=0
    
    # Common placeholder patterns
    local placeholder_patterns="
        YOUR_PUSHOVER_API_TOKEN
        YOUR_PUSHOVER_USER_KEY
        CHANGE_ME
        REPLACE_ME
        TODO
        FIXME
        EXAMPLE
        PLACEHOLDER
    "
    
    # Check for placeholder values in config
    for pattern in $placeholder_patterns; do
        if grep -q "$pattern" "$CONFIG_FILE" 2>/dev/null; then
            local var_name=$(grep "$pattern" "$CONFIG_FILE" | cut -d'=' -f1)
            printf "%b\n" "${YELLOW}⚠ Placeholder value found: $var_name${NC}"
            placeholders_found=$((placeholders_found + 1))
        fi
    done
    
    # Check for empty critical variables
    local critical_vars="PUSHOVER_TOKEN PUSHOVER_USER STARLINK_IP MWAN_IFACE MWAN_MEMBER"
    for var in $critical_vars; do
        local value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -z "$value" ] || [ "$value" = '""' ] || [ "$value" = "''" ]; then
            printf "%b\n" "${RED}✗ Critical variable is empty: $var${NC}"
            placeholders_found=$((placeholders_found + 1))
        fi
    done
    
    if [ $placeholders_found -eq 0 ]; then
        printf "%b\n" "${GREEN}✓ No placeholder values found${NC}"
    else
        printf "%b\n" "${YELLOW}Found $placeholders_found placeholder/empty values${NC}"
        printf "%b\n" "${YELLOW}Please update these values before deploying${NC}"
    fi
    
    return $placeholders_found
}

# Validate configuration value ranges and formats
validate_config_values() {
    printf "%b\n" "${GREEN}Validating configuration values...${NC}"
    
    local validation_errors=0
    
    # Validate numeric thresholds
    local numeric_vars="PACKET_LOSS_THRESHOLD OBSTRUCTION_THRESHOLD LATENCY_THRESHOLD CHECK_INTERVAL API_TIMEOUT"
    for var in $numeric_vars; do
        local value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -n "$value" ] && ! echo "$value" | grep -E '^[0-9]+$' >/dev/null; then
            printf "%b\n" "${RED}✗ Invalid numeric value for $var: $value${NC}"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # Validate boolean values (0 or 1)
    local boolean_vars="NOTIFY_ON_CRITICAL NOTIFY_ON_SOFT_FAIL NOTIFY_ON_HARD_FAIL NOTIFY_ON_RECOVERY NOTIFY_ON_INFO"
    for var in $boolean_vars; do
        local value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -n "$value" ] && [ "$value" != "0" ] && [ "$value" != "1" ]; then
            printf "%b\n" "${RED}✗ Invalid boolean value for $var: $value (should be 0 or 1)${NC}"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # Validate IP addresses
    local ip_vars="STARLINK_IP RUTOS_IP"
    for var in $ip_vars; do
        local value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -n "$value" ] && [ "$value" != "YOUR_IP_HERE" ]; then
            # Extract IP part (remove port if present)
            local ip_part=$(echo "$value" | cut -d':' -f1)
            if ! echo "$ip_part" | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' >/dev/null; then
                printf "%b\n" "${RED}✗ Invalid IP address format for $var: $value${NC}"
                validation_errors=$((validation_errors + 1))
            fi
        fi
    done
    
    # Validate file paths exist
    local path_vars="LOG_DIR STATE_DIR DATA_DIR"
    for var in $path_vars; do
        local value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -n "$value" ] && [ ! -d "$value" ]; then
            printf "%b\n" "${YELLOW}⚠ Directory does not exist for $var: $value${NC}"
            printf "%b\n" "${YELLOW}  (Will be created automatically)${NC}"
        fi
    done
    
    if [ $validation_errors -eq 0 ]; then
        printf "%b\n" "${GREEN}✓ Configuration values are valid${NC}"
    else
        printf "%b\n" "${RED}Found $validation_errors validation errors${NC}"
    fi
    
    return $validation_errors
}

# Main function
main() {
    printf "%b\n" "${GREEN}=== Starlink System Configuration Validator ===${NC}"
    echo ""

    check_root
    check_config_file
    load_config
    
    # Enhanced configuration validation
    local config_issues=0
    
    # Check configuration completeness against template
    if ! check_config_completeness; then
        config_issues=$((config_issues + 1))
    fi
    echo ""
    
    # Check for placeholder values
    if ! check_placeholder_values; then
        config_issues=$((config_issues + 1))
    fi
    echo ""
    
    # Validate configuration values
    if ! validate_config_values; then
        config_issues=$((config_issues + 1))
    fi
    echo ""
    
    # Original validation checks
    check_binaries
    check_network
    check_uci
    check_directories
    check_config_values  # Keep original for backward compatibility
    test_starlink_api

    echo ""
    if [ $config_issues -eq 0 ]; then
        printf "%b\n" "${GREEN}=== Validation Complete - Configuration is Ready ===${NC}"
        printf "%b\n" "${GREEN}✓ Configuration is complete and properly formatted${NC}"
    else
        printf "%b\n" "${YELLOW}=== Validation Complete - Configuration Issues Found ===${NC}"
        printf "%b\n" "${YELLOW}⚠ Found $config_issues configuration issue(s) that should be addressed${NC}"
    fi
    
    printf "%b\n" "${GREEN}System appears ready for deployment${NC}"
    echo ""
    printf "%b\n" "${YELLOW}Next steps:${NC}"
    
    if [ $config_issues -gt 0 ]; then
        printf "%b\n" "${YELLOW}1. Fix configuration issues listed above${NC}"
        printf "%b\n" "${YELLOW}2. Run update-config.sh to add missing variables${NC}"
        printf "%b\n" "${YELLOW}3. Re-run this validator to confirm fixes${NC}"
        printf "%b\n" "${YELLOW}4. Configure cron jobs as described in the documentation${NC}"
        printf "%b\n" "${YELLOW}5. Test the system manually before relying on it${NC}"
    else
        printf "%b\n" "${YELLOW}1. Configure cron jobs as described in the documentation${NC}"
        printf "%b\n" "${YELLOW}2. Test the system manually before relying on it${NC}"
    fi
    
    echo ""
    printf "%b\n" "${GREEN}Available tools:${NC}"
    printf "%b\n" "${GREEN}• Update config: $(dirname "$CONFIG_FILE")/../scripts/update-config.sh${NC}"
    printf "%b\n" "${GREEN}• Upgrade features: $(dirname "$CONFIG_FILE")/../scripts/upgrade-to-advanced.sh${NC}"
}

# Run main function
main
