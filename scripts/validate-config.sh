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
SCRIPT_VERSION="1.0.1"
# Build: 1.0.1+181.c96c23f-dirty
SCRIPT_NAME="validate-config.sh"
COMPATIBLE_INSTALL_VERSION="1.0.0"

# Extract build info from comment above
BUILD_INFO=$(grep "# Build:" "$0" | head -1 | sed 's/# Build: //' || echo "unknown")

# Debug mode - set to 1 to enable debug output
DEBUG="${DEBUG:-0}"

# Function to get timestamp
get_timestamp() {
	date '+%Y-%m-%d %H:%M:%S'
}

# Function to print colored output with timestamp
print_status() {
	color="$1"
	message="$2"
	printf "%b[%s] %s%b\n" "$color" "$(get_timestamp)" "$message" "$NC"
}

# Debug output function
debug_msg() {
	if [ "$DEBUG" = "1" ]; then
		print_status "$BLUE" "DEBUG: $1"
	fi
}

# Colors for output
# Check if terminal supports colors
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;36m'
	NC='\033[0m' # No Color
else
	# Fallback to no colors if terminal doesn't support them
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	NC=''
fi

# Show usage information
show_usage() {
	print_status "$BLUE" "Usage: $SCRIPT_NAME [options] [config_file]"
	print_status "$BLUE" "Options:"
	print_status "$BLUE" "  -h, --help      Show this help message"
	print_status "$BLUE" "  -m, --migrate   Force migration of outdated config template"
	printf "%b\n" "${BLUE}Arguments:${NC}"
	printf "%b\n" "${BLUE}  config_file     Path to configuration file (default: ./config.sh)${NC}"
	printf "%b\n" ""
	printf "%b\n" "${BLUE}Environment Variables:${NC}"
	printf "%b\n" "${BLUE}  DEBUG=1         Enable debug output for troubleshooting${NC}"
	printf "%b\n" ""
	printf "%b\n" "${BLUE}Examples:${NC}"
	printf "%b\n" "${BLUE}  $SCRIPT_NAME                    # Validate default config.sh${NC}"
	printf "%b\n" "${BLUE}  $SCRIPT_NAME /path/to/config.sh # Validate specific config${NC}"
	printf "%b\n" "${BLUE}  $SCRIPT_NAME --migrate          # Force migration of outdated template${NC}"
	printf "%b\n" "${BLUE}  DEBUG=1 $SCRIPT_NAME            # Run with debug output${NC}"
}

# Parse command line arguments
FORCE_MIGRATION=false
CONFIG_FILE="./config.sh"

while [ $# -gt 0 ]; do
	case $1 in
	-h | --help)
		show_usage
		exit 0
		;;
	-m | --migrate)
		FORCE_MIGRATION=true
		shift
		;;
	-*)
		printf "%b\n" "${RED}Error: Unknown option: $1${NC}"
		show_usage
		exit 1
		;;
	*)
		CONFIG_FILE="$1"
		shift
		;;
	esac
done

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
	template_file="$1"
	if [ ! -f "$template_file" ]; then
		return 1
	fi

	# Extract variables (exclude comments and empty lines)
	grep -E '^[A-Z_]+=.*' "$template_file" | cut -d'=' -f1 | sort
}

# Get current config variables
extract_config_variables() {
	config_file="$1"
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

	template_file=""
	config_dir="$(dirname "$CONFIG_FILE")"

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
	# Look in installation directory structure
	elif [ -f "/root/starlink-monitor/config/config.template.sh" ]; then
		template_file="/root/starlink-monitor/config/config.template.sh"
	elif [ -f "/root/starlink-monitor/config/config.advanced.template.sh" ]; then
		template_file="/root/starlink-monitor/config/config.advanced.template.sh"
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
	extra_vars=""
	total_missing=0
	total_extra=0

	# Check for missing variables (in template but not in config)
	while IFS= read -r var; do
		if ! grep -q "^$var$" "$temp_config"; then
			missing_vars="$missing_vars $var"
			total_missing=$((total_missing + 1))
		fi
	done <"$temp_template"

	# Check for extra variables (in config but not in template)
	while IFS= read -r var; do
		if ! grep -q "^$var$" "$temp_template"; then
			extra_vars="$extra_vars $var"
			total_extra=$((total_extra + 1))
		fi
	done <"$temp_config"

	# Cleanup temp files
	rm -f "$temp_template" "$temp_config"

	# Report results
	if [ "$total_missing" -eq 0 ] && [ "$total_extra" -eq 0 ]; then
		print_status "$GREEN" "✓ Configuration structure matches template"
		return 0
	fi

	if [ "$total_missing" -gt 0 ]; then
		print_status "$YELLOW" "⚠ Missing configuration variables (${total_missing} found):"
		for var in $missing_vars; do
			print_status "$YELLOW" "  - $var"
		done
		print_status "$YELLOW" "Suggestion: Run update-config.sh to add missing variables"
	fi

	if [ "$total_extra" -gt 0 ]; then
		print_status "$YELLOW" "⚠ Extra configuration variables (${total_extra} found):"
		for var in $extra_vars; do
			print_status "$YELLOW" "  - $var"
		done
		print_status "$YELLOW" "Note: These may be custom variables or from an older version"
	fi

	return 1
}

# Check for placeholder values and provide recommendations
check_placeholder_values() {
	print_status "$GREEN" "Checking for placeholder values..."

	placeholders_found=0

	# Common placeholder patterns

	placeholder_patterns="
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
			var_name=$(grep "$pattern" "$CONFIG_FILE" | cut -d'=' -f1)
			print_status "$YELLOW" "⚠ Placeholder value found: $var_name"
			placeholders_found=$((placeholders_found + 1))
		fi
	done

	# Check for empty critical variables

	critical_vars="PUSHOVER_TOKEN PUSHOVER_USER STARLINK_IP MWAN_IFACE MWAN_MEMBER"
	for var in $critical_vars; do
		value=$(grep "^$var=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
		if [ -z "$value" ] || [ "$value" = '""' ] || [ "$value" = "''" ]; then
			print_status "$RED" "✗ Critical variable is empty: $var"
			placeholders_found=$((placeholders_found + 1))
		fi
	done

	if [ "$placeholders_found" -eq 0 ]; then
		print_status "$GREEN" "✓ No placeholder values found"
	else
		print_status "$YELLOW" "Found $placeholders_found placeholder/empty values"
		print_status "$YELLOW" "Please update these values before deploying"
	fi
	return "$placeholders_found"
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

	printf "%b\n" "${YELLOW}🔄 Migrating configuration to updated template...${NC}"
	printf "%b\n" "${BLUE}Template: $template_file${NC}"
	printf "%b\n" "${BLUE}Config: $CONFIG_FILE${NC}"

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

	echo ""
	if [ "$structure_ok" -eq 0 ] && [ "$placeholders_found" -eq 0 ] && [ "$validation_errors" -eq 0 ]; then
		print_status "$GREEN" "=== CONFIGURATION STATUS: READY FOR DEPLOYMENT ==="
		print_status "$GREEN" "✓ All configuration variables are properly set"
		print_status "$GREEN" "✓ No placeholder values detected"
		print_status "$GREEN" "✓ All values are valid"
		return 0
	else
		print_status "$RED" "=== CONFIGURATION STATUS: NEEDS ATTENTION ==="

		if [ "$structure_ok" -ne 0 ]; then
			print_status "$RED" "✗ Configuration structure has issues"
		fi

		if [ "$placeholders_found" -gt 0 ]; then
			print_status "$RED" "✗ Configuration contains $placeholders_found placeholder/empty values"
			print_status "$RED" "  This means the config file hasn't been properly customized!"
		fi

		if [ "$validation_errors" -gt 0 ]; then
			print_status "$RED" "✗ Configuration contains $validation_errors validation errors"
		fi

		return 1
	fi
}

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

	# Validate configuration values
	if ! validate_config_values; then
		validation_errors=$?
		config_issues=$((config_issues + 1))
	fi
	echo ""

	# Show overall configuration status
	show_overall_status "$structure_ok" "$placeholders_found" "$validation_errors"
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
}

# Run main function
main
