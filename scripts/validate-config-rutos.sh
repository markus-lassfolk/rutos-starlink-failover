#!/bin/sh

# ==============================================================================
# Configuration Validation Script
#
# This script validates the configuration and checks system prerequisites
# before deploying the Starlink monitoring system.
#
# ==============================================================================

set -eu

# Script version information
# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
# Build: 1.0.2+198.38fb60b-dirty
SCRIPT_NAME="validate-config-rutos.sh"
COMPATIBLE_INSTALL_VERSION="1.0.0"

# Extract build info from comment above
BUILD_INFO=$(grep "# Build:" "$0" | head -1 | sed 's/# Build: //' || echo "unknown")

# Debug mode - set to 1 to enable debug output
DEBUG="${DEBUG:-0}"

# Colors for output - MUST be defined before functions that use them
# RUTOS-compatible color detection - Use same working approach as install script
# shellcheck disable=SC2034
RED=""
GREEN=""
YELLOW=""
BLUE=""
CYAN=""
NC=""

# Match install script logic exactly (this approach worked!)
if [ "${FORCE_COLOR:-}" = "1" ]; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;35m" # Bright magenta instead of dark blue for better readability
    CYAN="\033[0;36m"
    NC="\033[0m" # No Color
elif [ "${NO_COLOR:-}" != "1" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    case "${TERM:-}" in
        xterm* | screen* | tmux* | linux*)
            # Known terminal types that support colors
            RED="\033[0;31m"
            GREEN="\033[0;32m"
            YELLOW="\033[1;33m"
            BLUE="\033[1;35m" # Bright magenta instead of dark blue for better readability
            CYAN="\033[0;36m"
            NC="\033[0m" # No Color
            ;;
        *)
            # Unknown terminal - disable colors
            ;;
    esac
fi

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        print_status "$BLUE" "[DRY-RUN] Would execute: $description"
        return 0
    else
        eval "$cmd"
    fi
}

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to print colored output with timestamp
print_status() {
    color="$1"
    message="$2"
    # Use Method 5 format that works in RUTOS (embed variables in format string)
    case "$color" in
        "$RED") printf "${RED}[%s] %s${NC}\n" "$(get_timestamp)" "$message" ;;
        "$GREEN") printf "${GREEN}[%s] %s${NC}\n" "$(get_timestamp)" "$message" ;;
        "$YELLOW") printf "${YELLOW}[%s] %s${NC}\n" "$(get_timestamp)" "$message" ;;
        "$BLUE") printf "${BLUE}[%s] %s${NC}\n" "$(get_timestamp)" "$message" ;;
        "$CYAN") printf "${CYAN}[%s] %s${NC}\n" "$(get_timestamp)" "$message" ;;
        *) printf "[%s] %s\n" "$(get_timestamp)" "$message" ;;
    esac
}

# Debug output function
debug_msg() {
    if [ "$DEBUG" = "1" ]; then
        print_status "$BLUE" "DEBUG: $1"
    fi
}

# Installation directory path
INSTALL_DIR="${INSTALL_DIR:-/usr/local/starlink-monitor}"

# Show usage information
show_usage() {
    print_status "$BLUE" "Usage: $SCRIPT_NAME [options] [config_file]"
    print_status "$BLUE" "Options:"
    print_status "$BLUE" "  -h, --help      Show this help message"
    print_status "$BLUE" "  -m, --migrate   Force migration of outdated config template"
    print_status "$BLUE" "  -q, --quiet     Suppress output except errors"
    print_status "$BLUE" "  --repair        Repair common configuration format issues"
    printf "%b\n" "${BLUE}Arguments:${NC}"
    printf "%b\n" "${BLUE}  config_file     Path to configuration file (default: /etc/starlink-config/config.sh)${NC}"
    printf "%b\n" ""
    printf "%b\n" "${BLUE}Environment Variables:${NC}"
    printf "%b\n" "${BLUE}  DEBUG=1         Enable debug output for troubleshooting${NC}"
    printf "%b\n" ""
    printf "%b\n" "${BLUE}Examples:${NC}"
    printf "%b\n" "${BLUE}  $SCRIPT_NAME                    # Validate default config in /etc/starlink-config/config.sh${NC}"
    printf "%b\n" "${BLUE}  $SCRIPT_NAME /path/to/config.sh # Validate specific config${NC}"
    printf "%b\n" "${BLUE}  $SCRIPT_NAME --migrate          # Force migration of outdated template${NC}"
    printf "%b\n" "${BLUE}  $SCRIPT_NAME --repair           # Fix common configuration format issues${NC}"
    printf "%b\n" "${BLUE}  DEBUG=1 $SCRIPT_NAME            # Run with debug output${NC}"
}

# Parse command line arguments
FORCE_MIGRATION=false
# Use the persistent configuration directory as agreed
CONFIG_FILE="/etc/starlink-config/config.sh"

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

    # First validate the shell syntax before attempting to load
    printf "%b\n" "${BLUE}Validating shell syntax...${NC}"
    if ! sh -n "$CONFIG_FILE" 2>/dev/null; then
        printf "%b\n" "${RED}❌ CRITICAL: Configuration file has shell syntax errors!${NC}"
        printf "%b\n" "${RED}   Please check for:${NC}"
        printf "%b\n" "${RED}   - Missing quotes around values${NC}"
        printf "%b\n" "${RED}   - Unescaped special characters${NC}"
        printf "%b\n" "${RED}   - Malformed export statements${NC}"
        printf "%b\n" ""
        printf "%b\n" "${YELLOW}Syntax check output:${NC}"
        sh -n "$CONFIG_FILE" 2>&1 | head -10 | while IFS= read -r line; do
            printf "%b\n" "${RED}   $line${NC}"
        done
        printf "%b\n" ""
        return 1
    fi
    printf "%b\n" "${GREEN}✅ Shell syntax validation passed${NC}"

    # Now safely load the configuration
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"

    # Set default values for directories if not defined in config
    LOG_DIR="${LOG_DIR:-/etc/starlink-logs}"
    STATE_DIR="${STATE_DIR:-/tmp/run}"
    DATA_DIR="${DATA_DIR:-/usr/local/starlink-monitor/logs}" # Define missing DATA_DIR
}

# Check required binaries
check_binaries() {
    printf "%b\n" "${GREEN}Checking required binaries...${NC}"

    missing_binaries=""

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
        if ! command -v "$cmd" >/dev/null 2>&1; then
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

# Check network connectivity - basic system connectivity only
check_network() {
    printf "%b\n" "${GREEN}Checking basic network connectivity...${NC}"

    # Check if we have basic network connectivity (ping gateway or common DNS)
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ Basic network connectivity available${NC}"
    else
        printf "%b\n" "${YELLOW}Warning: Basic network connectivity test failed${NC}"
        printf "%b\n" "${YELLOW}This may affect script downloads and updates${NC}"
    fi

    # Note: Starlink API and service connectivity testing moved to test-connectivity-rutos.sh
    printf "%b\n" "${BLUE}ℹ For detailed connectivity testing, run: test-connectivity-rutos.sh${NC}"

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

# Test Starlink API - MOVED TO test-connectivity-rutos.sh
# This function has been moved to test-connectivity-rutos.sh for proper separation of concerns
# Configuration validation should focus on config completeness, not service connectivity
test_starlink_api() {
    printf "%b\n" "${BLUE}ℹ Starlink API testing moved to test-connectivity-rutos.sh${NC}"
    printf "%b\n" "${BLUE}  Run 'test-connectivity-rutos.sh' for comprehensive connectivity testing${NC}"
}

# Extract variable names from template
extract_template_variables() {
    template_file="$1"
    if [ ! -f "$template_file" ]; then
        return 1
    fi

    # Extract variables (exclude comments and empty lines, handle both export and non-export)
    {
        grep -E '^[A-Z_]+=.*' "$template_file" | cut -d'=' -f1
        grep -E '^export [A-Z_]+=.*' "$template_file" | sed 's/^export //' | cut -d'=' -f1
    } | sort -u
}

# Get current config variables
extract_config_variables() {
    config_file="$1"
    if [ ! -f "$config_file" ]; then
        return 1
    fi

    # Extract variables from config file (handle both export and non-export format)
    {
        grep -E '^[A-Z_]+=.*' "$config_file" | cut -d'=' -f1
        grep -E '^export [A-Z_]+=.*' "$config_file" | sed 's/^export //' | cut -d'=' -f1
    } | sort -u
}

# Compare configuration completeness
check_config_completeness() {
    printf "%b\n" "${GREEN}Checking configuration completeness...${NC}"

    # Try to find template file

    template_file=""
    config_dir="$(dirname "$CONFIG_FILE")"
    basic_template=""
    advanced_template=""

    # Find both template files
    if [ -f "$config_dir/config.template.sh" ]; then
        basic_template="$config_dir/config.template.sh"
    elif [ -f "$config_dir/../config/config.template.sh" ]; then
        basic_template="$config_dir/../config/config.template.sh"
    elif [ -f "/root/starlink-monitor/config/config.template.sh" ]; then
        basic_template="/root/starlink-monitor/config/config.template.sh"
    fi

    if [ -f "$config_dir/config.advanced.template.sh" ]; then
        advanced_template="$config_dir/config.advanced.template.sh"
    elif [ -f "$config_dir/../config/config.advanced.template.sh" ]; then
        advanced_template="$config_dir/../config/config.advanced.template.sh"
    elif [ -f "/root/starlink-monitor/config/config.advanced.template.sh" ]; then
        advanced_template="/root/starlink-monitor/config/config.advanced.template.sh"
    fi

    # Determine which template to use by checking the configuration
    printf "%b\n" "${BLUE}Determining configuration template type...${NC}"

    # Count variables in config (handle both export and non-export formats)
    config_var_count=$(grep -c "^export [A-Z_]*=" "$CONFIG_FILE" 2>/dev/null || printf "0")
    config_var_count_alt=$(grep -c "^[A-Z_]*=" "$CONFIG_FILE" 2>/dev/null || printf "0")

    # Ensure we have numeric values
    config_var_count="${config_var_count:-0}"
    config_var_count_alt="${config_var_count_alt:-0}"

    if [ "$config_var_count_alt" -gt "$config_var_count" ] 2>/dev/null; then
        config_var_count="$config_var_count_alt"
    fi

    # Check for advanced template indicators
    has_advanced_vars=0
    if grep -q "^export ENABLE_AZURE_LOGGING=" "$CONFIG_FILE" 2>/dev/null ||
        grep -q "^export AZURE_WORKSPACE_ID=" "$CONFIG_FILE" 2>/dev/null ||
        grep -q "^export GPS_DEVICE=" "$CONFIG_FILE" 2>/dev/null ||
        grep -q "^export ADVANCED_MONITORING=" "$CONFIG_FILE" 2>/dev/null ||
        grep -q "^ENABLE_AZURE_LOGGING=" "$CONFIG_FILE" 2>/dev/null ||
        grep -q "^AZURE_WORKSPACE_ID=" "$CONFIG_FILE" 2>/dev/null ||
        grep -q "^GPS_DEVICE=" "$CONFIG_FILE" 2>/dev/null ||
        grep -q "^ADVANCED_MONITORING=" "$CONFIG_FILE" 2>/dev/null ||
        [ "$config_var_count" -gt 25 ]; then
        has_advanced_vars=1
    fi

    # Select appropriate template
    if [ "$has_advanced_vars" -eq 1 ] && [ -n "$advanced_template" ]; then
        template_file="$advanced_template"
        printf "%b\n" "${GREEN}Detected advanced configuration (${config_var_count} variables)${NC}"
    elif [ -n "$basic_template" ]; then
        template_file="$basic_template"
        printf "%b\n" "${GREEN}Detected basic configuration (${config_var_count} variables)${NC}"
    elif [ -n "$advanced_template" ]; then
        template_file="$advanced_template"
        printf "%b\n" "${YELLOW}Using advanced template as fallback${NC}"
    else
        printf "%b\n" "${YELLOW}Warning: Could not find template file for comparison${NC}"
        printf "%b\n" "${YELLOW}Searched in: $config_dir/, $config_dir/../config/, /root/starlink-monitor/config/${NC}"
        return 0
    fi

    printf "%b\n" "${GREEN}Comparing against template: $template_file${NC}"

    # Check if config uses outdated template format
    debug_msg "Starting template format check"
    if check_outdated_template; then
        debug_msg "Template check result: OUTDATED"
        printf "%b\n" "${YELLOW}⚠ Configuration appears to use outdated template format${NC}"
        if offer_template_migration "$template_file"; then
            printf "%b\n" "${GREEN}✓ Configuration migrated to current template${NC}"
            printf "%b\n" "${BLUE}Re-run validation to verify the updated configuration${NC}"
            return 0
        fi
    fi

    # Get variables from both files

    temp_template="/tmp/template_vars.$$"
    temp_config="/tmp/config_vars.$$"

    if ! extract_template_variables "$template_file" >"$temp_template"; then
        printf "%b\n" "${RED}Error: Could not extract template variables${NC}"
        return 1
    fi

    if ! extract_config_variables "$CONFIG_FILE" >"$temp_config"; then
        printf "%b\n" "${RED}Error: Could not extract config variables${NC}"
        return 1
    fi

    # Find missing variables

    missing_vars=""
    # shellcheck disable=SC2034
    extra_vars=""
    total_missing=0
    # shellcheck disable=SC2034
    total_extra=0

    # Check for missing variables (in template but not in config)
    while IFS= read -r var; do
        if ! grep -q "^$var$" "$temp_config"; then
            missing_vars="$missing_vars $var"
            total_missing=$((total_missing + 1))
        fi
    done <"$temp_template"

    # Check for extra variables (in config but not in template)
    extra_vars_critical=""
    extra_vars_info=""
    total_extra_critical=0
    total_extra_info=0

    while IFS= read -r var; do
        if ! grep -q "^$var$" "$temp_template"; then
            # If we're using basic template but have both templates, check if variable exists in advanced template
            if [ -n "$basic_template" ] && [ -n "$advanced_template" ] && [ "$template_file" = "$basic_template" ]; then
                # Check if this variable exists in the advanced template
                if [ -f "$advanced_template" ] && grep -q "^$var=" "$advanced_template"; then
                    extra_vars_info="$extra_vars_info $var"
                    total_extra_info=$((total_extra_info + 1))
                else
                    extra_vars_critical="$extra_vars_critical $var"
                    total_extra_critical=$((total_extra_critical + 1))
                fi
            else
                extra_vars_info="$extra_vars_info $var"
                total_extra_info=$((total_extra_info + 1))
            fi
        fi
    done <"$temp_config"

    # Cleanup temp files
    rm -f "$temp_template" "$temp_config"

    # Report results - only treat as error if there are missing variables or critical extra variables
    if [ "$total_missing" -eq 0 ] && [ "$total_extra_critical" -eq 0 ]; then
        if [ "$total_extra_info" -gt 0 ]; then
            print_status "$GREEN" "✓ Configuration structure matches template (${total_extra_info} additional variables)"
        else
            print_status "$GREEN" "✓ Configuration structure matches template"
        fi
        return 0
    fi

    if [ "$total_missing" -gt 0 ]; then
        print_status "$YELLOW" "⚠ Missing configuration variables (${total_missing} found):"
        for var in $missing_vars; do
            print_status "$YELLOW" "  - $var"
        done
        print_status "$YELLOW" "Suggestion: Run update-config.sh to add missing variables"
    fi

    if [ "$total_extra_critical" -gt 0 ]; then
        print_status "$YELLOW" "⚠ Unknown configuration variables (${total_extra_critical} found):"
        for var in $extra_vars_critical; do
            print_status "$YELLOW" "  - $var"
        done
        print_status "$YELLOW" "Note: These may be custom variables or from an older version"
    fi

    if [ "$total_extra_info" -gt 0 ]; then
        print_status "$CYAN" "ℹ Additional configuration variables (${total_extra_info} found):"
        for var in $extra_vars_info; do
            print_status "$CYAN" "  - $var"
        done
        print_status "$CYAN" "Note: These appear to be advanced configuration options"
    fi

    # Only return error if there are missing variables or critical extra variables
    if [ "$total_missing" -gt 0 ] || [ "$total_extra_critical" -gt 0 ]; then
        return 1
    fi

    return 0
}

# Check for placeholder values and provide recommendations
check_placeholder_values() {
    print_status "$GREEN" "Checking for placeholder values..."

    placeholders_found=0
    placeholders_info=0

    # Source placeholder utility functions
    script_dir="$(dirname "$0")"
    if [ -f "$script_dir/placeholder-utils.sh" ]; then
        # shellcheck disable=SC1091
        . "$script_dir/placeholder-utils.sh"
    fi

    # Check Pushover configuration
    if ! is_pushover_configured; then
        if [ -n "$PUSHOVER_TOKEN" ] && [ -n "$PUSHOVER_USER" ]; then
            print_status "$CYAN" "ℹ Pushover notifications disabled (placeholder tokens detected)"
            print_status "$CYAN" "  System will work without notifications"
            placeholders_info=$((placeholders_info + 1))
        else
            print_status "$CYAN" "ℹ Pushover notifications disabled (tokens not set)"
            print_status "$CYAN" "  System will work without notifications"
            placeholders_info=$((placeholders_info + 1))
        fi
    else
        print_status "$GREEN" "✓ Pushover notifications properly configured"
    fi

    # Check for other placeholder patterns that are critical
    critical_placeholders="STARLINK_IP MWAN_IFACE MWAN_MEMBER"
    for var in $critical_placeholders; do
        # Try both export and non-export formats
        value=$(grep "^export $var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -z "$value" ]; then
            value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        fi
        if [ -n "$value" ] && is_placeholder "$value"; then
            print_status "$RED" "✗ Critical placeholder found: $var=$value"
            print_status "$RED" "  This must be configured for the system to work"
            placeholders_found=$((placeholders_found + 1))
        fi
    done

    # Check for empty critical variables
    for var in $critical_placeholders; do
        # Try both export and non-export formats
        value=$(grep "^export $var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -z "$value" ]; then
            value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        fi
        if [ -z "$value" ] || [ "$value" = '""' ] || [ "$value" = "''" ]; then
            print_status "$RED" "✗ Critical variable is empty: $var"
            print_status "$RED" "  This must be configured for the system to work"
            placeholders_found=$((placeholders_found + 1))
        fi
    done

    # Summary
    if [ "$placeholders_found" -eq 0 ] && [ "$placeholders_info" -eq 0 ]; then
        print_status "$GREEN" "✓ All configuration values are properly set"
    elif [ "$placeholders_found" -eq 0 ]; then
        print_status "$GREEN" "✓ All critical configuration values are set"
        print_status "$CYAN" "ℹ $placeholders_info optional feature(s) disabled (will work without them)"
    else
        print_status "$RED" "✗ Found $placeholders_found critical placeholder(s) that must be configured"
        if [ "$placeholders_info" -gt 0 ]; then
            print_status "$CYAN" "ℹ $placeholders_info optional feature(s) disabled (will work without them)"
        fi
    fi

    return "$placeholders_found"
}

# Validate configuration file format and common issues
validate_config_format() {
    printf "%b\n" "${GREEN}Validating configuration file format...${NC}"

    format_errors=0

    # Check for common syntax issues in the configuration file
    printf "%b\n" "${BLUE}Checking for common configuration format issues...${NC}"

    # Check for missing quotes on export lines
    unquoted_exports=$(grep -n '^[[:space:]]*export[[:space:]]*[A-Z_][A-Z0-9_]*=[^"'"'"'].*[[:space:]]' "$CONFIG_FILE" 2>/dev/null || true)
    if [ -n "$unquoted_exports" ]; then
        printf "%b\n" "${RED}⚠️  Found potentially unquoted values (may cause issues):${NC}"
        echo "$unquoted_exports" | while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            content=$(echo "$line" | cut -d: -f2-)
            printf "%b\n" "${RED}   Line $line_num: $content${NC}"
        done
        printf "%b\n" "${YELLOW}   Recommendation: Enclose values in double quotes${NC}"
        format_errors=$((format_errors + 1))
    fi

    # DISABLED: Complex quote detection - causing false positives
    # These patterns were incorrectly flagging valid configuration lines
    unmatched_quotes=""
    quotes_in_comments=""
    trailing_spaces=""
    stray_quote_comments=""

    # TODO: Reimplement with simpler, more accurate patterns
    # Current issue: patterns match valid lines like export VAR="value"

    if [ -n "$unmatched_quotes" ] || [ -n "$quotes_in_comments" ] || [ -n "$trailing_spaces" ] || [ -n "$stray_quote_comments" ]; then
        printf "%b\n" "${RED}❌ Found lines with quote formatting issues:${NC}"

        if [ -n "$unmatched_quotes" ]; then
            printf "%b\n" "${RED}   Missing closing quotes:${NC}"
            echo "$unmatched_quotes" | while IFS= read -r line; do
                line_num=$(echo "$line" | cut -d: -f1)
                content=$(echo "$line" | cut -d: -f2-)
                printf "%b\n" "${RED}     Line $line_num: $content${NC}"
            done
        fi

        if [ -n "$quotes_in_comments" ]; then
            printf "%b\n" "${RED}   Quotes incorrectly positioned in comments:${NC}"
            echo "$quotes_in_comments" | while IFS= read -r line; do
                line_num=$(echo "$line" | cut -d: -f1)
                content=$(echo "$line" | cut -d: -f2-)
                printf "%b\n" "${RED}     Line $line_num: $content${NC}"
                printf "%b\n" "${YELLOW}     Should be: $(echo "$content" | sed 's/="\([^#]*\)#\(.*\)"/="\1" #\2/')"
            done
        fi

        if [ -n "$trailing_spaces" ]; then
            printf "%b\n" "${RED}   Trailing spaces within quoted values:${NC}"
            echo "$trailing_spaces" | while IFS= read -r line; do
                line_num=$(echo "$line" | cut -d: -f1)
                content=$(echo "$line" | cut -d: -f2-)
                printf "%b\n" "${RED}     Line $line_num: $content${NC}"
                # Show what it should look like by removing trailing spaces
                fixed_content=$(echo "$content" | sed 's/^\([[:space:]]*export[[:space:]]*[A-Z_][A-Z0-9_]*="\)\([^"]*[^[:space:]]\)[[:space:]]*"/\1\2"/')
                printf "%b\n" "${YELLOW}     Should be: $fixed_content${NC}"
            done
        fi

        if [ -n "$stray_quote_comments" ]; then
            printf "%b\n" "${RED}   Stray quotes at end of comments:${NC}"
            echo "$stray_quote_comments" | while IFS= read -r line; do
                line_num=$(echo "$line" | cut -d: -f1)
                content=$(echo "$line" | cut -d: -f2-)
                printf "%b\n" "${RED}     Line $line_num: $content${NC}"
                # Show what it should look like by removing the trailing quote from comment
                fixed_content=$(echo "$content" | sed 's/"[[:space:]]*$//')
                printf "%b\n" "${YELLOW}     Should be: $fixed_content${NC}"
            done
        fi

        format_errors=$((format_errors + 1))
    fi

    # DISABLED: Malformed export detection - causing false positives
    # Pattern was incorrectly flagging valid export statements
    malformed_exports=""
    # invalid_syntax="" - REMOVED: unused variable

    # TODO: Reimplement with patterns that don't flag valid exports like:
    # export STARLINK_IP="192.168.100.1:9200" (this is VALID, not malformed)
    if [ -n "$malformed_exports" ]; then
        printf "%b\n" "${RED}❌ Found malformed export statements:${NC}"
        echo "$malformed_exports" | while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            content=$(echo "$line" | cut -d: -f2-)
            printf "%b\n" "${RED}   Line $line_num: $content${NC}"
        done
        format_errors=$((format_errors + 1))
    fi

    # Check for lines that look like exports but are missing the export keyword
    missing_export=$(grep -n '^[[:space:]]*[A-Z_][A-Z0-9_]*=' "$CONFIG_FILE" | grep -v '^[[:space:]]*export' 2>/dev/null || true)
    if [ -n "$missing_export" ]; then
        printf "%b\n" "${YELLOW}⚠️  Found variable assignments without 'export' keyword:${NC}"
        echo "$missing_export" | while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            content=$(echo "$line" | cut -d: -f2-)
            printf "%b\n" "${YELLOW}   Line $line_num: $content${NC}"
        done
        printf "%b\n" "${YELLOW}   These variables may not be available to other scripts${NC}"
    fi

    if [ "$format_errors" -eq 0 ]; then
        printf "%b\n" "${GREEN}✅ Configuration format validation passed${NC}"
    else
        printf "%b\n" "${RED}❌ Found $format_errors configuration format issues${NC}"
        printf "%b\n" "${RED}   These issues may prevent proper script operation${NC}"
    fi

    return "$format_errors"
}

# Validate configuration value ranges and formats
validate_config_values() {
    printf "%b\n" "${GREEN}Validating configuration values...${NC}"

    validation_errors=0

    # Validate numeric thresholds (including decimal values)

    numeric_vars="PACKET_LOSS_THRESHOLD OBSTRUCTION_THRESHOLD LATENCY_THRESHOLD CHECK_INTERVAL API_TIMEOUT"
    for var in $numeric_vars; do
        value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/[[:space:]]*#.*$//' | tr -d '"' | tr -d "'" | tr -d ' ')
        # Accept decimal, integer, and scientific notation
        if [ -n "$value" ] && ! printf "%s" "$value" | grep -Eq '^[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'; then
            printf "%b\n" "${RED}✗ Invalid numeric value for $var: $value${NC}"
            validation_errors=$((validation_errors + 1))
        fi
    done

    # Validate boolean values (0 or 1)

    boolean_vars="NOTIFY_ON_CRITICAL NOTIFY_ON_SOFT_FAIL NOTIFY_ON_HARD_FAIL NOTIFY_ON_RECOVERY NOTIFY_ON_INFO"
    for var in $boolean_vars; do
        value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/[[:space:]]*#.*$//' | tr -d '"' | tr -d "'" | tr -d ' ')
        # Only accept 0 or 1
        if [ -n "$value" ] && [ "$value" != "0" ] && [ "$value" != "1" ]; then
            printf "%b\n" "${RED}✗ Invalid boolean value for $var: $value (should be 0 or 1)${NC}"
            validation_errors=$((validation_errors + 1))
        fi
    done

    # Validate IP addresses

    ip_vars="STARLINK_IP RUTOS_IP"
    for var in $ip_vars; do
        value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/[[:space:]]*#.*$//' | tr -d '"' | tr -d "'" | tr -d ' ')
        if [ -n "$value" ] && [ "$value" != "YOUR_IP_HERE" ]; then
            # Extract IP part (remove port if present)
            ip_part=$(printf "%s" "$value" | cut -d':' -f1)
            if ! printf "%s" "$ip_part" | grep -Eq '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
                printf "%b\n" "${RED}✗ Invalid IP address format for $var: $value${NC}"
                validation_errors=$((validation_errors + 1))
            fi
        fi
    done

    # Validate file paths exist

    path_vars="LOG_DIR STATE_DIR DATA_DIR"
    for var in $path_vars; do
        value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/[[:space:]]*#.*$//' | tr -d '"' | tr -d "'" | tr -d ' ')
        if [ -n "$value" ] && [ ! -d "$value" ]; then
            printf "%b\n" "${YELLOW}⚠ Directory does not exist for $var: $value${NC}"
            printf "%b\n" "${YELLOW}  (Will be created automatically)${NC}"
        fi
    done

    if [ "$validation_errors" -eq 0 ]; then
        printf "%b\n" "${GREEN}✓ Configuration values are valid${NC}"
    else
        printf "%b\n" "${RED}Found $validation_errors validation errors${NC}"
    fi
    return "$validation_errors"
}

# Template migration function
migrate_config_to_template() {
    template_file="$1"
    backup_suffix="backup.$(date +%Y%m%d_%H%M%S)"
    config_backup="${CONFIG_FILE}.${backup_suffix}"

    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}[MIGRATE] Migrating configuration to updated template...${NC}\n"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}Template: %s${NC}\n" "$template_file"
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}Config: %s${NC}\n" "$CONFIG_FILE"

    # Create backup of current config
    if ! cp "$CONFIG_FILE" "$config_backup"; then
        printf "%b\n" "${RED}Error: Failed to create backup${NC}"
        return 1
    fi
    printf "%b\n" "${GREEN}✓ Backup created: $config_backup${NC}"

    # Extract current values from existing config
    temp_values="/tmp/config_values_$$"
    printf "%b\n" "${BLUE}Extracting current configuration values...${NC}"

    # Extract variable assignments, strip comments and quotes
    grep -E '^[A-Z_]+=.*' "$CONFIG_FILE" | while IFS='=' read -r var rest; do
        # Clean the value: remove quotes, strip inline comments
        value=$(echo "$rest" | sed 's/[[:space:]]*#.*$//' | sed 's/^["'"'"']//;s/["'"'"']$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo "$var=$value"
    done >"$temp_values"

    # Start with fresh template
    printf "%b\n" "${BLUE}Creating new configuration from template...${NC}"
    cp "$template_file" "$CONFIG_FILE"

    # Apply user values to template
    updated_count=0
    while IFS='=' read -r var value; do
        if [ -n "$var" ] && [ -n "$value" ]; then
            # Update the variable in the template, preserving structure
            if sed -i "s|^${var}=.*|${var}=\"${value}\"|" "$CONFIG_FILE" 2>/dev/null; then
                updated_count=$((updated_count + 1))
                printf "%b\n" "${GREEN}  ✓ Updated: $var${NC}"
            else
                printf "%b\n" "${YELLOW}  ⚠ Could not update: $var${NC}"
            fi
        fi
    done <"$temp_values"

    # Cleanup
    rm -f "$temp_values"

    printf "%b\n" "${GREEN}✓ Migration completed!${NC}"
    printf "%b\n" "${GREEN}  Updated $updated_count configuration values${NC}"
    printf "%b\n" "${GREEN}  New config has latest template structure and descriptions${NC}"
    printf "%b\n" "${YELLOW}  Review: $CONFIG_FILE${NC}"
    printf "%b\n" "${YELLOW}  Backup: $config_backup${NC}"

    return 0
}

# Offer template migration
offer_template_migration() {
    template_file="$1"

    printf "%b\n" "${YELLOW}⚠ Configuration appears to be using an older template format${NC}"
    printf "%b\n" "${YELLOW}  Issues found: ShellCheck comments, missing descriptions${NC}"
    printf "%b\n" "${BLUE}Available solution: Migrate to current template${NC}"
    printf "%b\n" "${BLUE}  • Preserves all your current settings${NC}"
    printf "%b\n" "${BLUE}  • Updates to latest template structure${NC}"
    printf "%b\n" "${BLUE}  • Adds proper descriptions and help text${NC}"
    printf "%b\n" "${BLUE}  • Removes technical ShellCheck comments${NC}"
    printf "%b\n" "${BLUE}  • Creates backup of current config${NC}"
    printf "%b\n" ""
    printf "%b" "${YELLOW}Migrate configuration to current template? (y/N): ${NC}"
    read -r answer

    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        migrate_config_to_template "$template_file"
        return 0
    else
        printf "%b\n" "${YELLOW}Skipping migration. Consider running update-config.sh later.${NC}"
        return 1
    fi
}

# Check if config uses outdated template format
check_outdated_template() {
    debug_msg "Checking if config uses outdated template format"
    debug_msg "Config file: $CONFIG_FILE"

    # Check for ShellCheck comments (primary indicator of outdated template)
    if grep -q "# shellcheck" "$CONFIG_FILE"; then
        debug_msg "Found ShellCheck comments - config appears outdated"
        return 0 # Found ShellCheck comments - outdated
    fi
    debug_msg "No ShellCheck comments found"

    # Check for specific outdated template patterns
    debug_msg "Checking for specific outdated template patterns"

    # Check for old variable names that indicate outdated template
    if grep -q "^ROUTER_IP=" "$CONFIG_FILE" ||
        grep -q "^DISH_IP=" "$CONFIG_FILE" ||
        grep -q "^DISH_PORT=" "$CONFIG_FILE"; then
        debug_msg "Found old variable names - config appears outdated"
        return 0 # Found old variable names - outdated
    fi
    debug_msg "No old variable names found"

    # Check for missing comprehensive descriptions (only if no proper descriptions exist)
    debug_msg "Checking for template completeness indicators"

    # Count variables with comprehensive descriptions vs short ones
    comprehensive_comments=0
    short_comments=0
    total_vars=0

    while read -r line; do
        if printf "%s" "$line" | grep -E '^[A-Z_]+=.*#' >/dev/null; then
            total_vars=$((total_vars + 1))
            # Extract comment part
            comment=$(printf "%s" "$line" | sed 's/.*#[[:space:]]*//')
            debug_msg "Variable comment: '$comment' (length: ${#comment})"

            # Check if comment is comprehensive (contains helpful description)
            if [ "${#comment}" -ge 30 ] && (printf "%s" "$comment" | grep -q -E "(default|should|used|connection|threshold|timeout|directory|command|notification)" >/dev/null 2>&1); then
                comprehensive_comments=$((comprehensive_comments + 1))
                debug_msg "  Comprehensive comment detected"
            elif [ "${#comment}" -lt 15 ]; then
                short_comments=$((short_comments + 1))
                debug_msg "  Very short comment detected"
            fi
        fi
    done <"$CONFIG_FILE"

    debug_msg "Total variables: $total_vars, Comprehensive comments: $comprehensive_comments, Short comments: $short_comments"

    # If we have very few comprehensive comments AND many short ones, likely outdated
    # But only if we have a reasonable number of variables to check
    if [ "$total_vars" -gt 10 ] && [ "$comprehensive_comments" -lt 5 ] && [ "$short_comments" -gt $((total_vars / 3)) ]; then
        debug_msg "Config appears outdated: only $comprehensive_comments comprehensive comments, $short_comments short comments out of $total_vars variables"
        return 0 # Likely outdated
    fi

    debug_msg "Config template appears current ($comprehensive_comments comprehensive comments, $short_comments short comments)"
    return 1 # Appears current
}

# Function to determine and display overall configuration status
show_overall_status() {
    structure_ok="$1"
    placeholders_found="$2"
    validation_errors="$3"
    format_errors="${4:-0}"

    echo ""
    if [ "$structure_ok" -eq 0 ] && [ "$placeholders_found" -eq 0 ] && [ "$validation_errors" -eq 0 ] && [ "$format_errors" -eq 0 ]; then
        print_status "$GREEN" "=== CONFIGURATION STATUS: READY FOR DEPLOYMENT ==="
        print_status "$GREEN" "✓ All configuration variables are properly set"
        print_status "$GREEN" "✓ No placeholder values detected"
        print_status "$GREEN" "✓ All values are valid"
        print_status "$GREEN" "✓ Configuration format is correct"
        return 0
    else
        # Check if we only have minor issues (structure OK but placeholders/validation errors)
        if [ "$structure_ok" -eq 0 ] && [ "$placeholders_found" -eq 0 ] && [ "$validation_errors" -eq 0 ] && [ "$format_errors" -eq 0 ]; then
            print_status "$GREEN" "=== CONFIGURATION STATUS: READY FOR DEPLOYMENT ==="
            return 0
        elif [ "$structure_ok" -eq 0 ] && [ "$placeholders_found" -eq 0 ] && [ "$validation_errors" -gt 0 ] && [ "$format_errors" -eq 0 ]; then
            print_status "$YELLOW" "=== CONFIGURATION STATUS: MINOR ISSUES DETECTED ==="
            print_status "$YELLOW" "✓ Configuration structure is valid"
            print_status "$YELLOW" "✓ No placeholder values detected"
            print_status "$YELLOW" "✓ Configuration format is correct"
            print_status "$YELLOW" "⚠ Configuration contains $validation_errors validation errors"
            return 1
        else
            print_status "$RED" "=== CONFIGURATION STATUS: NEEDS ATTENTION ==="

            if [ "$structure_ok" -ne 0 ]; then
                print_status "$RED" "✗ Configuration structure has issues"
            else
                print_status "$GREEN" "✓ Configuration structure is valid"
            fi

            if [ "$format_errors" -gt 0 ]; then
                print_status "$RED" "✗ Configuration format contains $format_errors syntax issues"
                print_status "$RED" "  This will prevent scripts from loading the configuration!"
            else
                print_status "$GREEN" "✓ Configuration format is correct"
            fi

            if [ "$placeholders_found" -gt 0 ]; then
                print_status "$RED" "✗ Configuration contains $placeholders_found placeholder/empty values"
                print_status "$RED" "  This means the config file hasn't been properly customized!"
            else
                print_status "$GREEN" "✓ No placeholder values detected"
            fi

            if [ "$validation_errors" -gt 0 ]; then
                print_status "$RED" "✗ Configuration contains $validation_errors validation errors"
            else
                print_status "$GREEN" "✓ All values are valid"
            fi

            return 1
        fi
    fi
}

# Function to repair common configuration format issues
repair_config_quotes() {
    config_file="$1"

    printf "%b\n" "${BLUE}Attempting to repair quote formatting issues...${NC}"

    # Create backup only if not skipped (when called from install script that already created backup)
    backup_file=""
    if [ "${SKIP_BACKUP:-0}" != "1" ]; then
        backup_file="${config_file}.backup-$(date +%Y%m%d-%H%M%S)"
        if cp "$config_file" "$backup_file"; then
            printf "%b\n" "${GREEN}✅ Created backup: $backup_file${NC}"
        else
            printf "%b\n" "${RED}❌ Failed to create backup. Aborting repair.${NC}"
            return 1
        fi
    else
        printf "%b\n" "${CYAN}ℹ  Skipping backup creation (already handled by caller)${NC}"
    fi

    # Fix quotes incorrectly positioned in comments, trailing spaces in quoted values, and stray quotes at end of comments
    # Pattern 1: export VAR="value # comment" -> export VAR="value" # comment"
    # Pattern 2: export VAR="value   " -> export VAR="value"
    # Pattern 3: export VAR="value" # comment" -> export VAR="value" # comment
    temp_file=$(mktemp)
    temp_file2=$(mktemp)
    temp_file3=$(mktemp)

    # First pass: Fix quote positioning
    if sed 's/^\([[:space:]]*export[[:space:]]*[A-Z_][A-Z0-9_]*="\)\([^"]*\)\(#.*\)"/\1\2" \3/' "$config_file" >"$temp_file"; then

        # Second pass: Remove trailing spaces within quotes - Fixed pattern
        if sed 's/^\([[:space:]]*export[[:space:]]*[A-Z_][A-Z0-9_]*="\)\([^"]*\)[[:space:]]*"/\1\2"/' "$temp_file" >"$temp_file2"; then

            # Third pass: Remove stray quotes at end of comments
            if sed 's/^\([[:space:]]*export[[:space:]]*[A-Z_][A-Z0-9_]*="[^"]*"[[:space:]]*#.*\)"[[:space:]]*$/\1/' "$temp_file2" >"$temp_file3"; then

                # Check if any changes were made in any pass
                if ! cmp -s "$config_file" "$temp_file3"; then
                    changes_made=""

                    # Check what type of fixes were made
                    if ! cmp -s "$config_file" "$temp_file"; then
                        changes_made="quote positioning"
                    fi
                    if ! cmp -s "$temp_file" "$temp_file2"; then
                        if [ -n "$changes_made" ]; then
                            changes_made="$changes_made and trailing spaces"
                        else
                            changes_made="trailing spaces in quoted values"
                        fi
                    fi
                    if ! cmp -s "$temp_file2" "$temp_file3"; then
                        if [ -n "$changes_made" ]; then
                            changes_made="$changes_made and stray quotes in comments"
                        else
                            changes_made="stray quotes in comments"
                        fi
                    fi

                    printf "%b\n" "${GREEN}✅ Fixed $changes_made${NC}"

                    # Count and show what was changed
                    printf "%b\n" "${CYAN}Changes made:${NC}"
                    if command -v diff >/dev/null 2>&1; then
                        diff -u "$config_file" "$temp_file3" | grep -E "^[\+\-]export" | head -10 || true
                    else
                        # Alternative: count the fixes made
                        fix_count=$(grep -c "^export.*=" "$temp_file3" 2>/dev/null || echo "unknown")
                        printf "%b\n" "${YELLOW}Quote formatting fixes applied to configuration${NC}"
                        printf "%b\n" "${CYAN}Total export statements processed: $fix_count${NC}"
                    fi

                    # Apply the changes
                    mv "$temp_file3" "$config_file"
                    rm -f "$temp_file" "$temp_file2" 2>/dev/null || true

                    printf "%b\n" "${GREEN}✅ Configuration file repaired successfully${NC}"
                    if [ -n "$backup_file" ]; then
                        printf "%b\n" "${YELLOW}💡 Backup saved as: $backup_file${NC}"
                    fi

                    return 0
                else
                    printf "%b\n" "${BLUE}ℹ️  No quote formatting issues found to repair${NC}"
                    rm -f "$temp_file" "$temp_file2" "$temp_file3" 2>/dev/null || true
                    return 0
                fi
            else
                printf "%b\n" "${RED}❌ Failed to process configuration file (third pass)${NC}"
                rm -f "$temp_file" "$temp_file2" "$temp_file3" 2>/dev/null || true
                return 1
            fi
        else
            printf "%b\n" "${RED}❌ Failed to process configuration file (second pass)${NC}"
            rm -f "$temp_file" "$temp_file2" "$temp_file3" 2>/dev/null || true
            return 1
        fi
    else
        printf "%b\n" "${RED}❌ Failed to process configuration file (first pass)${NC}"
        rm -f "$temp_file" "$temp_file2" "$temp_file3" 2>/dev/null || true
        return 1
    fi
}

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    print_status "$GREEN" "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Main function
main() {
    print_status "$GREEN" "=== Starlink System Configuration Validator ==="
    print_status "$BLUE" "Script: $SCRIPT_NAME"
    print_status "$BLUE" "Version: $SCRIPT_VERSION"
    print_status "$BLUE" "Build: $BUILD_INFO"
    print_status "$BLUE" "Compatible with install.sh: $COMPATIBLE_INSTALL_VERSION"
    if [ "$DEBUG" = "1" ]; then
        print_status "$YELLOW" "==================== DEBUG MODE ENABLED ===================="
        print_status "$YELLOW" "DEBUG: Script starting with DEBUG=1"
        print_status "$YELLOW" "DEBUG: Configuration file: $CONFIG_FILE"
        print_status "$YELLOW" "=========================================================="
    fi
    echo ""

    check_root
    check_config_file
    load_config

    # Handle repair mode option
    if [ "$REPAIR_MODE" = "true" ]; then
        printf "%b\n" "${YELLOW}Repair mode enabled - attempting to fix configuration format issues${NC}"
        echo ""

        if repair_config_quotes "$CONFIG_FILE"; then
            printf "%b\n" "${GREEN}✅ Configuration repair completed successfully${NC}"
            printf "%b\n" "${BLUE}💡 Please re-run validation to verify the fixes${NC}"
            exit 0
        else
            printf "%b\n" "${RED}❌ Configuration repair failed${NC}"
            exit 1
        fi
    fi

    # Handle force migration option
    if [ "$FORCE_MIGRATION" = "true" ]; then
        printf "%b\n" "${YELLOW}Force migration mode enabled${NC}"
        if check_outdated_template; then
            # Find template file
            template_file="$(dirname "$CONFIG_FILE")/../config/config.template.sh"
            if [ ! -f "$template_file" ]; then
                template_file="./config/config.template.sh"
            fi
            if [ ! -f "$template_file" ]; then
                printf "%b\n" "${RED}Error: Cannot find template file${NC}"
                exit 1
            fi
            migrate_config_to_template "$template_file"
            printf "%b\n" "${GREEN}Migration completed. Please re-run validation.${NC}"
            exit 0
        else
            printf "%b\n" "${GREEN}Configuration template is already current.${NC}"
            exit 0
        fi
    fi

    # Enhanced configuration validation
    config_issues=0
    structure_ok=0
    placeholders_found=0
    validation_errors=0

    # Check configuration completeness against template
    if ! check_config_completeness; then
        structure_ok=1
        config_issues=$((config_issues + 1))
    fi
    echo ""

    # Check for placeholder values
    if ! check_placeholder_values; then
        placeholders_found=$?
        config_issues=$((config_issues + 1))
    fi
    echo ""

    # Validate configuration file format
    if ! validate_config_format; then
        format_errors=$?
        config_issues=$((config_issues + 1))
    fi
    echo ""

    # Validate configuration values
    if ! validate_config_values; then
        validation_errors=$?
        config_issues=$((config_issues + 1))
    fi
    echo ""

    # Show overall configuration status
    show_overall_status "$structure_ok" "$placeholders_found" "$validation_errors" "$format_errors"
    echo ""

    # Original validation checks
    check_binaries
    check_network
    check_uci
    check_directories
    check_config_values # Keep original for backward compatibility
    test_starlink_api

    echo ""
    if [ $config_issues -eq 0 ]; then
        print_status "$GREEN" "=== Validation Complete - System Ready ==="
        print_status "$GREEN" "✓ All checks passed successfully"
    else
        print_status "$YELLOW" "=== Validation Complete - Issues Found ==="
        print_status "$YELLOW" "⚠ Found $config_issues configuration issue(s) that should be addressed"
    fi

    print_status "$GREEN" "System infrastructure appears ready for deployment"
    echo ""
    print_status "$YELLOW" "Next steps:"

    if [ $config_issues -gt 0 ]; then
        print_status "$YELLOW" "1. Fix configuration issues listed above"
        print_status "$YELLOW" "2. Run update-config.sh to add missing variables"
        print_status "$YELLOW" "3. Re-run this validator to confirm fixes"
        print_status "$YELLOW" "4. Configure cron jobs as described in the documentation"
        print_status "$YELLOW" "5. Test the system manually before relying on it"
    else
        print_status "$YELLOW" "1. Configure cron jobs as described in the documentation"
        print_status "$YELLOW" "2. Test the system manually before relying on it"
    fi

    echo ""
    print_status "$GREEN" "Available tools:"
    print_status "$GREEN" "• Update config: $(dirname "$CONFIG_FILE")/../scripts/update-config.sh"
    print_status "$GREEN" "• Upgrade features: $(dirname "$CONFIG_FILE")/../scripts/upgrade-to-advanced.sh"
    print_status "$GREEN" "• Migrate outdated template: $SCRIPT_NAME --migrate"
    echo ""
    print_status "$BLUE" "📝 Configuration File Editing:"
    print_status "$BLUE" "• Edit main config: vi $CONFIG_FILE"
    if [ -f "/usr/bin/nano" ]; then
        print_status "$BLUE" "• Or use nano: nano $CONFIG_FILE"
    fi
    echo ""
    print_status "$CYAN" "💡 Pro tip: Test your configuration changes with:"
    print_status "$CYAN" "• Run connectivity tests: $INSTALL_DIR/scripts/test-connectivity-rutos.sh"
    print_status "$CYAN" "• Re-run this validator: $SCRIPT_NAME"
}

# Parse command line arguments
QUIET_MODE=0
FORCE_MIGRATION="false"
REPAIR_MODE="false"

while [ $# -gt 0 ]; do
    case "$1" in
        --quiet | -q)
            QUIET_MODE=1
            shift
            ;;
        --migrate)
            FORCE_MIGRATION="true"
            shift
            ;;
        --repair)
            REPAIR_MODE="true"
            shift
            ;;
        --help | -h)
            show_usage
            exit 0
            ;;
        -*)
            printf "%b\n" "${RED}Unknown option: $1${NC}" >&2
            show_usage >&2
            exit 1
            ;;
        *)
            # Treat remaining arguments as config file path
            CONFIG_FILE="$1"
            shift
            ;;
    esac
done

# Override print_status function in quiet mode
if [ "$QUIET_MODE" = "1" ]; then
    print_status() {
        # In quiet mode, only output errors to stderr
        if [ "$1" = "$RED" ]; then
            printf "%b\n" "$2" >&2
        fi
    }
    debug_msg() {
        # Suppress debug messages in quiet mode unless DEBUG=1
        if [ "${DEBUG:-0}" = "1" ]; then
            printf "[DEBUG] %s\n" "$1" >&2
        fi
    }
fi

# Run main function
main
