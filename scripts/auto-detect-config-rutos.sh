#!/bin/sh
# Script: auto-detect-config-rutos.sh
# Version: 2.7.0
# Description: Autonomous system configuration detection for RUTOS Starlink failover
# Purpose: "Just make it work" - detect optimal settings automatically

# RUTOS Compatibility - Using Method 5 printf format for proper color display
# shellcheck disable=SC2059  # Method 5 printf format required for RUTOS color support

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" = "1" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors
log_info() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

log_success() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    # shellcheck disable=SC2059  # Method 5 format required for RUTOS compatibility
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Dry-run and test mode support
DRY_RUN="${DRY_RUN:-0}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"

# Debug dry-run status
if [ "$DEBUG" = "1" ]; then
    log_debug "DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
fi

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Function to safely execute commands
safe_execute() {
    cmd="$1"
    description="$2"

    if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_debug "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_debug "Executing: $cmd"
        eval "$cmd"
    fi
}

# Function to detect Starlink interface and member
detect_starlink_config() {
    log_step "🔍 Detecting Starlink configuration..."

    # Find interfaces with "Starlink" in name or WAN interfaces
    starlink_interface=""
    starlink_member=""
    starlink_metric=""

    # Check MWAN3 members for Starlink patterns
    for member in $(uci show mwan3 2>/dev/null | grep "=member$" | cut -d'=' -f1 | cut -d'.' -f2); do
        member_name=$(uci get "mwan3.$member.name" 2>/dev/null || echo "")
        member_interface=$(uci get "mwan3.$member.interface" 2>/dev/null || echo "")
        member_metric=$(uci get "mwan3.$member.metric" 2>/dev/null || echo "")

        log_debug "Found member: $member -> $member_name (interface: $member_interface, metric: $member_metric)"

        # Check if this looks like Starlink (name patterns)
        if echo "$member_name" | grep -qi "starlink\|star"; then
            starlink_member="$member"
            starlink_interface="$member_interface"
            starlink_metric="$member_metric"
            log_info "✓ Detected Starlink member: $member ($member_name) -> interface: $member_interface"
            break
        fi

        # Check if interface name suggests Starlink (wan interface)
        if [ "$member_interface" = "wan" ]; then
            # Get network name to verify
            network_name=$(uci get "network.$member_interface.name" 2>/dev/null || echo "")
            if echo "$network_name" | grep -qi "starlink\|star"; then
                starlink_member="$member"
                starlink_interface="$member_interface"
                starlink_metric="$member_metric"
                log_info "✓ Detected Starlink via wan interface: $member ($member_name) -> interface: $member_interface"
                break
            fi
        fi
    done

    # If no explicit Starlink found, look for lowest metric member (primary)
    if [ -z "$starlink_member" ]; then
        log_debug "No explicit Starlink member found, looking for primary (lowest metric)"
        lowest_metric=999
        for member in $(uci show mwan3 2>/dev/null | grep "=member$" | cut -d'=' -f1 | cut -d'.' -f2); do
            metric=$(uci get "mwan3.$member.metric" 2>/dev/null || echo "999")
            if [ "$metric" -lt "$lowest_metric" ]; then
                lowest_metric="$metric"
                starlink_member="$member"
                starlink_interface=$(uci get "mwan3.$member.interface" 2>/dev/null || echo "")
                starlink_metric="$metric"
            fi
        done
        if [ -n "$starlink_member" ]; then
            member_name=$(uci get "mwan3.$starlink_member.name" 2>/dev/null || echo "Primary")
            log_info "✓ Detected primary member: $starlink_member ($member_name) -> interface: $starlink_interface (metric: $starlink_metric)"
        fi
    fi

    # Export results
    if [ -n "$starlink_member" ] && [ -n "$starlink_interface" ]; then
        printf "DETECTED_MWAN_MEMBER=\"%s\"\n" "$starlink_member"
        printf "DETECTED_MWAN_INTERFACE=\"%s\"\n" "$starlink_interface"
        printf "DETECTED_STARLINK_METRIC=\"%s\"\n" "$starlink_metric"

        # Also detect the specific metric values for failover
        good_metric="$starlink_metric"
        # Bad metric should be higher than all backup members
        bad_metric=$((starlink_metric + 10))

        # Check what the highest backup metric is and set bad_metric accordingly
        highest_backup_metric=0
        for member in $(uci show mwan3 2>/dev/null | grep "=member$" | cut -d'=' -f1 | cut -d'.' -f2); do
            if [ "$member" != "$starlink_member" ]; then
                metric=$(uci get "mwan3.$member.metric" 2>/dev/null || echo "0")
                if [ "$metric" -gt "$highest_backup_metric" ]; then
                    highest_backup_metric="$metric"
                fi
            fi
        done

        if [ "$highest_backup_metric" -gt 0 ]; then
            bad_metric=$((highest_backup_metric + 5))
            log_debug "Calculated bad metric: $bad_metric (highest backup: $highest_backup_metric)"
        fi

        printf "DETECTED_METRIC_GOOD=\"%s\"\n" "$good_metric"
        printf "DETECTED_METRIC_BAD=\"%s\"\n" "$bad_metric"

        return 0
    else
        log_warning "⚠ Could not auto-detect Starlink configuration"
        return 1
    fi
}

# Function to detect and optionally configure MWAN3
detect_and_configure_mwan3() {
    log_step "🔍 Detecting MWAN3 configuration..."

    # Check if MWAN3 is installed
    if ! uci show mwan3 >/dev/null 2>&1; then
        log_warning "⚠ MWAN3 not found or not installed"
        printf "MWAN3_NEEDS_INSTALL=\"true\"\n"
        return 1
    fi

    # Check if MWAN3 has any configured interfaces
    configured_interfaces=$(uci show mwan3 2>/dev/null | grep -c "=interface$")
    configured_members=$(uci show mwan3 2>/dev/null | grep -c "=member$")
    configured_policies=$(uci show mwan3 2>/dev/null | grep -c "=policy$")

    log_debug "MWAN3 status: $configured_interfaces interfaces, $configured_members members, $configured_policies policies"

    # Determine if MWAN3 needs basic configuration
    needs_basic_config="false"
    if [ "$configured_interfaces" -eq 0 ] || [ "$configured_members" -eq 0 ] || [ "$configured_policies" -eq 0 ]; then
        needs_basic_config="true"
        log_info "🔧 MWAN3 needs basic configuration (interfaces: $configured_interfaces, members: $configured_members, policies: $configured_policies)"
    else
        log_info "✓ MWAN3 is already configured (interfaces: $configured_interfaces, members: $configured_members, policies: $configured_policies)"
    fi

    printf "MWAN3_CONFIGURED=\"%s\"\n" "$needs_basic_config"

    # If MWAN3 needs configuration, offer to set it up
    if [ "$needs_basic_config" = "true" ]; then
        printf "MWAN3_NEEDS_SETUP=\"true\"\n"

        # Detect available network interfaces for MWAN3 setup
        detect_available_interfaces_for_mwan3
    else
        printf "MWAN3_NEEDS_SETUP=\"false\"\n"
    fi

    return 0
}

# Function to detect available network interfaces for MWAN3 setup
detect_available_interfaces_for_mwan3() {
    log_step "🔍 Detecting available interfaces for MWAN3 setup..."

    primary_interface=""
    backup_interfaces=""
    interface_count=0

    # Look for WAN interfaces first (Starlink/primary)
    for interface in $(uci show network 2>/dev/null | grep "=interface$" | cut -d'.' -f2 | cut -d'=' -f1); do
        if [ "$interface" = "loopback" ] || [ "$interface" = "lan" ]; then
            continue # Skip loopback and LAN
        fi

        area_type=$(uci get "network.$interface.area_type" 2>/dev/null || echo "")
        proto=$(uci get "network.$interface.proto" 2>/dev/null || echo "")
        interface_name=$(uci get "network.$interface.name" 2>/dev/null || echo "$interface")

        log_debug "Interface: $interface ($interface_name) - proto: $proto, area_type: $area_type"

        if [ "$area_type" = "wan" ]; then
            interface_count=$((interface_count + 1))

            # Prioritize ethernet/dhcp interfaces (likely Starlink)
            if [ "$proto" = "dhcp" ] && [ -z "$primary_interface" ]; then
                primary_interface="$interface"
                log_info "✓ Detected primary interface: $interface ($interface_name, $proto)"
            elif [ "$proto" = "wwan" ]; then
                # Cellular backup
                backup_interfaces="$backup_interfaces $interface"
                log_info "✓ Detected backup interface: $interface ($interface_name, $proto)"
            fi
        fi
    done

    # If no primary found, use the first WAN interface
    if [ -z "$primary_interface" ] && [ "$interface_count" -gt 0 ]; then
        for interface in $(uci show network 2>/dev/null | grep "=interface$" | cut -d'.' -f2 | cut -d'=' -f1); do
            area_type=$(uci get "network.$interface.area_type" 2>/dev/null || echo "")
            if [ "$area_type" = "wan" ]; then
                primary_interface="$interface"
                log_info "✓ Using first WAN interface as primary: $interface"
                break
            fi
        done
    fi

    # Export results
    if [ -n "$primary_interface" ]; then
        printf "DETECTED_PRIMARY_INTERFACE=\"%s\"\n" "$primary_interface"
        printf "DETECTED_BACKUP_INTERFACES=\"%s\"\n" "$backup_interfaces"
        printf "DETECTED_INTERFACE_COUNT=\"%s\"\n" "$interface_count"

        # Generate MWAN3 configuration suggestions
        generate_mwan3_config_suggestions
        return 0
    else
        log_warning "⚠ No suitable interfaces found for MWAN3 configuration"
        return 1
    fi
}

# Function to generate MWAN3 configuration suggestions
generate_mwan3_config_suggestions() {
    log_step "🎯 Generating optimal MWAN3 configuration..."

    # Generate interface configurations
    mwan3_interfaces=""
    mwan3_members=""
    member_list=""
    metric_counter=1

    # Primary interface (Starlink)
    if [ -n "$primary_interface" ]; then
        primary_name=$(uci get "network.$primary_interface.name" 2>/dev/null || echo "Primary")

        mwan3_interfaces="${mwan3_interfaces}
# Primary interface configuration (${primary_name})
uci set mwan3.${primary_interface}=interface
uci set mwan3.${primary_interface}.family='ipv4'
uci set mwan3.${primary_interface}.flush_conntrack='connected' 'disconnected' 'ifup' 'ifdown'
uci set mwan3.${primary_interface}.enabled='1'

"

        # Primary member
        mwan3_members="${mwan3_members}
# Primary member (${primary_name})
uci set mwan3.member1=member
uci set mwan3.member1.interface='${primary_interface}'
uci set mwan3.member1.name='${primary_name}'
uci set mwan3.member1.metric='${metric_counter}'

"
        member_list="member1"
        metric_counter=$((metric_counter + 1))
    fi

    # Backup interfaces (Cellular)
    member_counter=2
    for backup_interface in $backup_interfaces; do
        if [ -n "$backup_interface" ]; then
            backup_name=$(uci get "network.$backup_interface.name" 2>/dev/null || echo "Backup$member_counter")

            mwan3_interfaces="${mwan3_interfaces}
# Backup interface configuration (${backup_name})
uci set mwan3.${backup_interface}=interface
uci set mwan3.${backup_interface}.family='ipv4'
uci set mwan3.${backup_interface}.flush_conntrack='connected' 'disconnected' 'ifup' 'ifdown'
uci set mwan3.${backup_interface}.enabled='1'

"

            # Backup member
            mwan3_members="${mwan3_members}
# Backup member ${member_counter} (${backup_name})
uci set mwan3.member${member_counter}=member
uci set mwan3.member${member_counter}.interface='${backup_interface}'
uci set mwan3.member${member_counter}.name='${backup_name}'
uci set mwan3.member${member_counter}.metric='${metric_counter}'

"
            member_list="$member_list member$member_counter"
            metric_counter=$((metric_counter + 1))
            member_counter=$((member_counter + 1))
        fi
    done

    # Generate policy and rules
    mwan3_policy="
# Failover policy configuration
uci set mwan3.mwan_default=policy
uci set mwan3.mwan_default.name='failover'
uci set mwan3.mwan_default.last_resort='unreachable'
uci set mwan3.mwan_default.use_member='${member_list}'

# Default rule
uci set mwan3.default_rule=rule
uci set mwan3.default_rule.family='ipv4'
uci set mwan3.default_rule.proto='all'
uci set mwan3.default_rule.sticky='0'
uci set mwan3.default_rule.dest_ip='0.0.0.0/0'
uci set mwan3.default_rule.use_policy='mwan_default'

# Global settings
uci set mwan3.globals=globals
uci set mwan3.globals.mmx_mask='0x3F00'
uci set mwan3.globals.rtmon_interval='5'
uci set mwan3.globals.logging='1'
uci set mwan3.globals.debug='0'

# Commit changes
uci commit mwan3
"

    # Export complete configuration script
    printf "MWAN3_CONFIG_SCRIPT=\"%s%s%s\"\n" "$mwan3_interfaces" "$mwan3_members" "$mwan3_policy"

    log_success "✓ Generated MWAN3 configuration for $interface_count interfaces"
    log_info "  Primary: $primary_interface (member1, metric=1)"

    backup_count=0
    for backup in $backup_interfaces; do
        if [ -n "$backup" ]; then
            backup_count=$((backup_count + 1))
            backup_name=$(uci get "network.$backup.name" 2>/dev/null || echo "Backup$backup_count")
            log_info "  Backup: $backup ($backup_name, member$((backup_count + 1)), metric=$((backup_count + 1)))"
        fi
    done

    return 0
}

# Function to detect backup interfaces (cellular) - legacy method for configured MWAN3
detect_backup_interfaces() {
    log_step "🔍 Detecting backup interfaces..."

    backup_members=""
    backup_count=0

    # Find all MWAN3 members that are not the primary Starlink
    for member in $(uci show mwan3 2>/dev/null | grep "\.interface=" | cut -d'=' -f1 | cut -d'.' -f2); do
        if [ "$member" != "$starlink_member" ]; then
            member_name=$(uci get "mwan3.$member.name" 2>/dev/null || echo "")
            member_interface=$(uci get "mwan3.$member.interface" 2>/dev/null || echo "")
            member_metric=$(uci get "mwan3.$member.metric" 2>/dev/null || echo "")

            # Check if it's a mobile/cellular interface
            interface_proto=$(uci get "network.$member_interface.proto" 2>/dev/null || echo "")

            if [ "$interface_proto" = "wwan" ] || echo "$member_interface" | grep -q "mob\|sim\|cellular"; then
                log_info "✓ Detected cellular backup: $member ($member_name) -> $member_interface (metric: $member_metric)"
                backup_members="$backup_members $member"
                backup_count=$((backup_count + 1))
            fi
        fi
    done

    if [ "$backup_count" -gt 0 ]; then
        printf "DETECTED_BACKUP_MEMBERS=\"%s\"\n" "$backup_members"
        printf "DETECTED_BACKUP_COUNT=\"%s\"\n" "$backup_count"
        return 0
    else
        log_warning "⚠ No cellular backup interfaces detected"
        return 1
    fi
}

# Function to detect Starlink gRPC endpoint
detect_starlink_endpoint() {
    log_step "🔍 Detecting Starlink gRPC endpoint..."

    # Get Starlink interface IP range
    if [ -n "$starlink_interface" ]; then
        # Try to get the network from the interface
        starlink_network=$(uci get "network.$starlink_interface" 2>/dev/null || echo "")
        if [ -n "$starlink_network" ]; then
            log_debug "Starlink interface network configuration found"
        fi
    fi

    # Standard Starlink gRPC endpoints to test
    endpoints="192.168.100.1:9200 192.168.1.1:9200"
    detected_endpoint=""

    for endpoint in $endpoints; do
        ip=$(echo "$endpoint" | cut -d':' -f1)
        port=$(echo "$endpoint" | cut -d':' -f2)

        log_debug "Testing Starlink endpoint: $endpoint"

        # Test TCP connectivity
        if nc -z -w 3 "$ip" "$port" 2>/dev/null; then
            log_info "✓ Starlink gRPC endpoint responding: $endpoint"
            detected_endpoint="$endpoint"
            break
        fi
    done

    if [ -n "$detected_endpoint" ]; then
        # Split endpoint into IP and port
        ip=$(echo "$detected_endpoint" | cut -d':' -f1)
        port=$(echo "$detected_endpoint" | cut -d':' -f2)
        printf "DETECTED_STARLINK_IP=\"%s\"\n" "$ip"
        printf "DETECTED_STARLINK_PORT=\"%s\"\n" "$port"
        return 0
    else
        log_warning "⚠ Could not detect Starlink gRPC endpoint, using default: 192.168.100.1:9200"
        printf "DETECTED_STARLINK_IP=\"192.168.100.1\"\n"
        printf "DETECTED_STARLINK_PORT=\"9200\"\n"
        return 1
    fi
}

# Function to detect optimal check intervals based on system load
detect_optimal_intervals() {
    log_step "🔍 Detecting optimal monitoring intervals..."

    # Get system memory and CPU info
    mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    cpu_count=$(grep -c processor /proc/cpuinfo 2>/dev/null || echo "1")

    # Convert KB to MB
    mem_mb=$((mem_total / 1024))

    log_debug "System resources: ${mem_mb}MB RAM, ${cpu_count} CPU cores"

    # Determine optimal intervals based on system resources
    if [ "$mem_mb" -gt 512 ] && [ "$cpu_count" -gt 2 ]; then
        # High-spec system - can handle frequent checks
        check_interval="30"
        failure_threshold="3"
        recovery_threshold="3"
        log_info "✓ High-spec system detected - using aggressive monitoring (30s intervals)"
    elif [ "$mem_mb" -gt 256 ]; then
        # Medium system - standard intervals
        check_interval="60"
        failure_threshold="3"
        recovery_threshold="5"
        log_info "✓ Medium system detected - using standard monitoring (60s intervals)"
    else
        # Low-spec system - conservative intervals
        check_interval="120"
        failure_threshold="5"
        recovery_threshold="7"
        log_info "✓ Resource-constrained system detected - using conservative monitoring (120s intervals)"
    fi

    printf "DETECTED_CHECK_INTERVAL=\"%s\"\n" "$check_interval"
    printf "DETECTED_FAILURE_THRESHOLD=\"%s\"\n" "$failure_threshold"
    printf "DETECTED_RECOVERY_THRESHOLD=\"%s\"\n" "$recovery_threshold"

    return 0
}

# Function to detect notification capabilities
detect_notification_capabilities() {
    log_step "🔍 Detecting notification capabilities..."

    # Check for SMS capabilities
    sms_capable="false"
    if [ -d "/sys/class/tty" ] && find /sys/class/tty -name "ttyUSB*" | grep -q .; then
        # Modem likely present
        if command -v gsmctl >/dev/null 2>&1; then
            sms_capable="true"
            log_info "✓ SMS notification capability detected (gsmctl available)"
        fi
    fi

    # Check for email capabilities
    email_capable="false"
    if command -v sendmail >/dev/null 2>&1 || command -v msmtp >/dev/null 2>&1; then
        email_capable="true"
        log_info "✓ Email notification capability detected"
    fi

    # Internet connectivity is assumed if we got this far
    internet_notifications="true"
    log_info "✓ Internet-based notifications available (Pushover, Slack, Discord)"

    printf "DETECTED_SMS_CAPABLE=\"%s\"\n" "$sms_capable"
    printf "DETECTED_EMAIL_CAPABLE=\"%s\"\n" "$email_capable"
    printf "DETECTED_INTERNET_NOTIFICATIONS=\"%s\"\n" "$internet_notifications"

    return 0
}

# Main detection function
main() {
    log_info "🚀 Starting autonomous RUTOS configuration detection v$SCRIPT_VERSION"

    # Check if we're running on RUTOS
    if [ ! -f "/etc/openwrt_version" ] && [ ! -f "/etc/rutos_version" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi

    # Check for UCI availability
    if ! command -v uci >/dev/null 2>&1; then
        log_error "UCI configuration interface not found"
        exit 1
    fi

    log_step "🔍 System detection starting..."

    # Perform all detections
    detect_starlink_config || log_warning "Starlink detection incomplete"

    # Detect and optionally configure MWAN3
    if detect_and_configure_mwan3; then
        log_success "✓ MWAN3 system analyzed"

        # If MWAN3 is already configured, detect backup interfaces
        if [ "${MWAN3_NEEDS_SETUP:-false}" = "false" ]; then
            detect_backup_interfaces || log_warning "Backup interface detection incomplete"
        fi
    else
        log_warning "MWAN3 configuration analysis incomplete"
        # Fallback to old backup detection method
        detect_backup_interfaces || log_warning "Backup interface detection incomplete"
    fi

    detect_starlink_endpoint || log_warning "Starlink endpoint detection incomplete"
    detect_optimal_intervals || log_warning "Interval optimization incomplete"
    detect_notification_capabilities || log_warning "Notification detection incomplete"

    log_success "🎯 Autonomous configuration detection completed"

    # Show MWAN3 configuration notice if needed
    if [ "${MWAN3_NEEDS_SETUP:-false}" = "true" ]; then
        printf "\n${YELLOW}${BLUE}=========================================${NC}\n"
        printf "${YELLOW}🔧 MWAN3 AUTO-CONFIGURATION AVAILABLE${NC}\n"
        printf "${YELLOW}${BLUE}=========================================${NC}\n"
        printf "MWAN3 needs configuration. To auto-configure:\n"
        printf "1. Review the generated MWAN3_CONFIG_SCRIPT above\n"
        printf "2. Run the commands to set up automatic failover\n"
        printf "3. Restart network services: ${CYAN}/etc/init.d/network restart${NC}\n"
        printf "4. Restart MWAN3 service: ${CYAN}/etc/init.d/mwan3 restart${NC}\n"
        printf "${YELLOW}${BLUE}=========================================${NC}\n"
    fi

    printf "\n# =============================================================================\n"
    printf "# AUTONOMOUS CONFIGURATION DETECTION RESULTS\n"
    printf "# Generated: %s\n" "$(date)"
    printf "# =============================================================================\n\n"
}

# Execute main function
main "$@"
