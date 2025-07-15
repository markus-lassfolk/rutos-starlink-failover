#!/bin/sh

# ==============================================================================
# UCI Configuration Analyzer and Optimizer for Starlink Failover
# Analyzes existing RUTX50 configuration and applies optimizations
# ==============================================================================

set -eu

# Configuration
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Currently unused
# CONFIG_FILE="$SCRIPT_DIR/../config/config.sh"  # Currently unused
BACKUP_DIR="/tmp/uci_backup_$(date +%Y%m%d_%H%M%S)"

# Colors for output
# Check if terminal supports colors (simplified for RUTOS compatibility)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[1;35m' # Bright magenta instead of dark blue for better readability
	CYAN='\033[0;36m'
	NC='\033[0m' # No Color
else
	# Fallback to no colors if terminal doesn't support them
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
	CYAN=""
	NC=""
fi

# Logging
log_info() {
	printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_warn() {
	printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
	printf "${RED}[ERROR]${NC} %s\n" "$1"
}

log_success() {
	printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

# Create backup
create_uci_backup() {
	log_info "Creating UCI configuration backup..."
	mkdir -p "$BACKUP_DIR"

	# Backup critical configurations
	configs="mwan3 network firewall gps simcard system wireless dhcp dropbear"

	for config in $configs; do
		uci export "$config" >"$BACKUP_DIR/${config}.uci" 2>/dev/null || {
			log_warn "Could not backup $config"
		}
	done

	log_success "Backup created at $BACKUP_DIR"
}

# Analyze current mwan3 configuration
analyze_mwan3() {
	log_info "Analyzing mwan3 configuration..."

	# Check if mwan3 is properly configured
	if ! uci get mwan3.globals >/dev/null 2>&1; then
		log_error "mwan3 not configured"
		return 1
	fi

	# Analyze interfaces
	interfaces
	interfaces=$(uci show mwan3 | grep -E "mwan3\.[^.]*\.interface=" | cut -d'=' -f2 | tr -d "'")

	log_info "Found mwan3 interfaces:"
	for iface in $interfaces; do
		enabled=""
		enabled=$(uci get "mwan3.${iface%.*}.enabled" 2>/dev/null || echo "0")

		if [ "$enabled" = "1" ]; then
			metric=""
			metric=$(uci show mwan3 | grep -E "member.*interface='?${iface}'?" | head -1 |
				sed -n 's/.*metric=.\([0-9]*\).*/\1/p')
			echo "  - $iface (enabled, metric: ${metric:-unknown})"
		else
			echo "  - $iface (disabled)"
		fi
	done
}

# Optimize mwan3 for Starlink failover
optimize_mwan3() {
	log_info "Optimizing mwan3 configuration for Starlink failover..."

	# Enhanced global settings
	uci set mwan3.globals.rtmon_interval='3' # Faster route monitoring
	uci set mwan3.globals.logging='1'        # Enable logging
	uci set mwan3.globals.debug='1'          # Debug level 1

	# Check if Starlink (wan) interface exists
	if uci get network.wan >/dev/null 2>&1; then
		log_info "Configuring Starlink (wan) interface..."

		# Enhanced wan interface settings
		uci set mwan3.wan.enabled='1'
		uci set mwan3.wan.family='ipv4'
		uci set mwan3.wan.recovery_wait='15' # 15 second recovery wait
		uci set mwan3.wan.flush_conntrack='connected' 'disconnected' 'ifup' 'ifdown'

		# Find and update wan condition or create new one
		wan_condition=""
		conditions=""
		conditions=$(uci show mwan3 | grep -E "@condition\[[0-9]+\]\.interface='wan'" | cut -d'[' -f2 | cut -d']' -f1)

		if [ -n "$conditions" ]; then
			wan_condition=$(echo "$conditions" | head -1)
			log_info "Updating existing wan condition [$wan_condition]"
		else
			# Create new condition
			uci add mwan3 condition
			wan_condition=$(uci show mwan3 | grep -E "@condition\[[0-9]+\]=" | tail -1 | cut -d'[' -f2 | cut -d']' -f1)
			log_info "Created new wan condition [$wan_condition]"
		fi

		# Configure enhanced monitoring for Starlink
		uci set "mwan3.@condition[$wan_condition].interface=wan"
		uci set "mwan3.@condition[$wan_condition].track_method=ping"
		uci set "mwan3.@condition[$wan_condition].track_ip=1.0.0.1" "8.8.8.8" "1.1.1.1"
		uci set "mwan3.@condition[$wan_condition].reliability=2" # 2 out of 3 must succeed
		uci set "mwan3.@condition[$wan_condition].timeout=1"
		uci set "mwan3.@condition[$wan_condition].interval=5" # Check every 5 seconds
		uci set "mwan3.@condition[$wan_condition].count=3"    # Use 3 IPs
		uci set "mwan3.@condition[$wan_condition].family=ipv4"
		uci set "mwan3.@condition[$wan_condition].up=2"   # 2 successful to mark up
		uci set "mwan3.@condition[$wan_condition].down=3" # 3 failed to mark down

		# Ensure member1 exists and is configured for Starlink
		if ! uci get mwan3.member1 >/dev/null 2>&1; then
			uci set mwan3.member1=member
		fi
		uci set mwan3.member1.interface='wan'
		uci set mwan3.member1.name='Starlink'
		uci set mwan3.member1.metric='1' # Highest priority

		log_success "Starlink interface optimized"
	else
		log_warn "Starlink (wan) interface not found in network config"
	fi

	# Commit mwan3 changes
	uci commit mwan3
	log_success "mwan3 configuration optimized"
}

# Add static route for Starlink management
add_starlink_route() {
	log_info "Adding static route for Starlink management interface..."

	# Check if route already exists
	existing_routes
	existing_routes=$(uci show network | grep -E "route.*target='192\.168\.100\.1'" || true)

	if [ -z "$existing_routes" ]; then
		# Add new route
		uci add network route
		route_index=""
		route_index=$(uci show network | grep -E "@route\[[0-9]+\]=" | tail -1 | cut -d'[' -f2 | cut -d']' -f1)

		uci set "network.@route[$route_index].interface=wan"
		uci set "network.@route[$route_index].target=192.168.100.1"
		uci set "network.@route[$route_index].netmask=255.255.255.255"
		uci set "network.@route[$route_index].gateway=0.0.0.0"

		uci commit network
		log_success "Static route added for Starlink management"
	else
		log_info "Starlink management route already exists"
	fi
}

# Configure GPS integration
configure_gps_integration() {
	log_info "Configuring GPS integration..."

	# Enable GPS if not already enabled
	if uci get gps.gpsd >/dev/null 2>&1; then
		uci set gps.gpsd.enabled='1'
		uci set gps.gpsd.glonass_sup='1'
		uci set gps.gpsd.galileo_sup='1'
		uci set gps.gpsd.beidou_sup='1'

		# Configure GPS forwarding for integration
		uci set gps.https.enabled='1'
		uci set gps.https.url='http://127.0.0.1:8080/gps/webhook'
		uci set gps.https.interval='10'

		uci commit gps
		log_success "GPS integration configured"
	else
		log_warn "GPS configuration not found"
	fi
}

# Optimize firewall for Starlink monitoring
optimize_firewall() {
	log_info "Optimizing firewall for Starlink monitoring..."

	# Allow gRPC traffic to Starlink (if not already allowed)
	# local starlink_rule=""  # Currently unused
	rules
	rules=$(uci show firewall | grep -E "name='.*[Ss]tarlink.*'" || true)

	if [ -z "$rules" ]; then
		# Add firewall rule for Starlink gRPC
		uci add firewall rule
		rule_index=""
		rule_index=$(uci show firewall | grep -E "@rule\[[0-9]+\]=" | tail -1 | cut -d'[' -f2 | cut -d']' -f1)

		uci set "firewall.@rule[$rule_index].name=Allow-Starlink-gRPC"
		uci set "firewall.@rule[$rule_index].src=lan"
		uci set "firewall.@rule[$rule_index].dest=wan"
		uci set "firewall.@rule[$rule_index].dest_ip=192.168.100.1"
		uci set "firewall.@rule[$rule_index].dest_port=9200"
		uci set "firewall.@rule[$rule_index].proto=tcp"
		uci set "firewall.@rule[$rule_index].target=ACCEPT"

		uci commit firewall
		log_success "Firewall rule added for Starlink gRPC"
	else
		log_info "Starlink firewall rules already exist"
	fi
}

# Configure system logging
configure_system_logging() {
	log_info "Configuring enhanced system logging..."

	# Increase log buffer size for better monitoring
	uci set system.system.log_buffer_size='256'
	uci set system.system.log_size='50000'
	uci set system.system.log_level='6' # Info level

	uci commit system
	log_success "System logging optimized"
}

# Apply configuration based on user's existing setup
apply_optimizations() {
	config_type="$1"

	case "$config_type" in
	"all")
		create_uci_backup
		optimize_mwan3
		add_starlink_route
		configure_gps_integration
		optimize_firewall
		configure_system_logging
		;;
	"mwan3")
		create_uci_backup
		optimize_mwan3
		;;
	"network")
		create_uci_backup
		add_starlink_route
		;;
	"gps")
		create_uci_backup
		configure_gps_integration
		;;
	"firewall")
		create_uci_backup
		optimize_firewall
		;;
	"analyze")
		analyze_mwan3
		return 0
		;;
	*)
		log_error "Unknown configuration type: $config_type"
		return 1
		;;
	esac

	# Restart affected services
	log_info "Restarting affected services..."
	/etc/init.d/mwan3 restart >/dev/null 2>&1 || log_warn "Could not restart mwan3"
	/etc/init.d/network reload >/dev/null 2>&1 || log_warn "Could not reload network"
	/etc/init.d/firewall restart >/dev/null 2>&1 || log_warn "Could not restart firewall"

	log_success "Configuration optimization complete!"
}

# Generate configuration report
generate_report() {
	log_info "Generating configuration report..."

	report_file
	report_file="/tmp/starlink_config_report_$(date +%Y%m%d_%H%M%S).txt"

	{
		echo "Starlink Failover Configuration Report"
		echo "Generated: $(date)"
		echo "======================================="
		echo

		echo "MWAN3 Configuration:"
		echo "-------------------"
		uci show mwan3 | grep -E "(interface|member|condition)" || echo "No mwan3 config found"
		echo

		echo "Network Interfaces:"
		echo "------------------"
		uci show network | grep -E "proto|device|metric" || echo "No network config found"
		echo

		echo "GPS Status:"
		echo "----------"
		uci show gps | grep -E "enabled|interval" || echo "No GPS config found"
		echo

		echo "Firewall Rules:"
		echo "--------------"
		uci show firewall | grep -E "name|dest_ip.*192\.168\.100" || echo "No Starlink firewall rules found"
		echo

	} >"$report_file"

	log_success "Report generated: $report_file"

	# Display summary
	echo
	echo "Configuration Summary:"
	echo "====================="

	# MWAN3 status
	if uci get mwan3.wan.enabled 2>/dev/null | grep -q '1'; then
		echo "✅ MWAN3 Starlink interface: Enabled"
	else
		echo "❌ MWAN3 Starlink interface: Disabled"
	fi

	# Route status
	if uci show network | grep -q "target='192.168.100.1'"; then
		echo "✅ Starlink management route: Configured"
	else
		echo "❌ Starlink management route: Missing"
	fi

	# GPS status
	if uci get gps.gpsd.enabled 2>/dev/null | grep -q '1'; then
		echo "✅ GPS integration: Enabled"
	else
		echo "❌ GPS integration: Disabled"
	fi

	# Firewall status
	if uci show firewall | grep -q "192.168.100.1"; then
		echo "✅ Starlink firewall rules: Configured"
	else
		echo "❌ Starlink firewall rules: Missing"
	fi
}

# Restore from backup
restore_backup() {
	backup_path="$1"

	if [ ! -d "$backup_path" ]; then
		log_error "Backup directory not found: $backup_path"
		return 1
	fi

	log_warn "Restoring configuration from backup..."

	for config_file in "$backup_path"/*.uci; do
		if [ -f "$config_file" ]; then
			config_name=""
			config_name=$(basename "$config_file" .uci)

			log_info "Restoring $config_name..."
			uci import "$config_name" <"$config_file" || {
				log_error "Failed to restore $config_name"
				continue
			}
			uci commit "$config_name"
		fi
	done

	log_success "Configuration restored from backup"
}

# Main function
main() {
	action="${1:-analyze}"

	# Check if running on OpenWrt/RUTOS
	if ! command -v uci >/dev/null 2>&1; then
		log_error "This script requires UCI (OpenWrt/RUTOS system)"
		exit 1
	fi

	case "$action" in
	"analyze")
		analyze_mwan3
		generate_report
		;;
	"optimize")
		apply_optimizations "all"
		generate_report
		;;
	"optimize-mwan3")
		apply_optimizations "mwan3"
		;;
	"optimize-network")
		apply_optimizations "network"
		;;
	"optimize-gps")
		apply_optimizations "gps"
		;;
	"optimize-firewall")
		apply_optimizations "firewall"
		;;
	"restore")
		if [ -n "${2:-}" ]; then
			restore_backup "$2"
		else
			log_error "Please specify backup directory path"
			exit 1
		fi
		;;
	"report")
		generate_report
		;;
	"help" | "--help" | "-h")
		echo "Usage: $0 [action]"
		echo
		echo "Actions:"
		echo "  analyze           - Analyze current configuration (default)"
		echo "  optimize          - Apply all optimizations"
		echo "  optimize-mwan3    - Optimize only mwan3 configuration"
		echo "  optimize-network  - Optimize only network configuration"
		echo "  optimize-gps      - Optimize only GPS configuration"
		echo "  optimize-firewall - Optimize only firewall configuration"
		echo "  restore <path>    - Restore from backup directory"
		echo "  report            - Generate configuration report"
		echo "  help              - Show this help"
		echo
		;;
	*)
		log_error "Unknown action: $action"
		echo "Use '$0 help' for usage information"
		exit 1
		;;
	esac
}

# Run main function with all arguments
main "$@"
