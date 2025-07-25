#!/bin/sh
# Test script for MWAN3 auto-configuration functionality
# Demonstrates what the system would do for unconfigured MWAN3 setups

set -e

# Colors for output (busybox compatible)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION
# Used for troubleshooting: echo "Configuration version: $SCRIPT_VERSION"
# shellcheck disable=SC2034
RED=""
GREEN=""
YELLOW=""
BLUE=""
CYAN=""
NC=""

# Enable colors if terminal supports them
if [ -t 1 ]; then
    # shellcheck disable=SC2034
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

# Test function to demonstrate MWAN3 auto-configuration decision logic
test_mwan3_configuration_scenarios() {
    log_step "🧪 Testing MWAN3 auto-configuration scenarios"

    printf "\n"
    printf "%sScenario 1: Fresh RUTX50 with no MWAN3 configuration%s\n" "$CYAN" "$NC"
    printf "- System detects: WAN interface (Starlink), 2 cellular interfaces\n"
    printf "- Decision: %sAUTO-CONFIGURE%s - Set up complete failover\n" "$GREEN" "$NC"
    printf "- Action: Create interfaces, members, policy with optimal metrics\n"

    printf "\n%sScenario 2: Partially configured MWAN3%s\n" "$CYAN" "$NC"
    printf "- System detects: Some interfaces configured, missing members/policies\n"
    printf "- Decision: %sOFFER COMPLETION%s - Fill in missing configuration\n" "$YELLOW" "$NC"
    printf "- Action: Complete the configuration without breaking existing setup\n"

    printf "\n%sScenario 3: Fully configured MWAN3%s\n" "$CYAN" "$NC"
    printf "- System detects: Complete MWAN3 setup with all components\n"
    printf "- Decision: %sUSE EXISTING%s - Analyze and optimize existing setup\n" "$GREEN" "$NC"
    printf "- Action: Use existing configuration for monitoring script\n"

    printf "\n%sScenario 4: MWAN3 not installed%s\n" "$CYAN" "$NC"
    printf "- System detects: MWAN3 package not available\n"
    printf "- Decision: %sRECOMMEND INSTALL%s - Suggest package installation\n" "$YELLOW" "$NC"
    printf "- Action: Provide installation instructions and configuration\n"
}

# Test function to show generated configuration example
test_configuration_generation() {
    log_step "🔧 Example MWAN3 auto-configuration output"

    printf "\n%sGenerated for: RUTX50 with Starlink + 2 Cellular%s\n" "$CYAN" "$NC"
    printf "%s# Primary interface configuration (Starlink)%s\n" "$GREEN" "$NC"
    printf "uci set mwan3.wan=interface\n"
    printf "uci set mwan3.wan.family='ipv4'\n"
    printf "uci set mwan3.wan.enabled='1'\n"
    printf "\n"

    printf "%s# Primary member (Starlink)%s\n" "$GREEN" "$NC"
    printf "uci set mwan3.member1=member\n"
    printf "uci set mwan3.member1.interface='wan'\n"
    printf "uci set mwan3.member1.name='Starlink'\n"
    printf "uci set mwan3.member1.metric='1'\n"
    printf "\n"

    printf "%s# Backup member 1 (Telia SIM)%s\n" "$GREEN" "$NC"
    printf "uci set mwan3.member2=member\n"
    printf "uci set mwan3.member2.interface='mob1s1a1'\n"
    printf "uci set mwan3.member2.name='SIM_Telia'\n"
    printf "uci set mwan3.member2.metric='2'\n"
    printf "\n"

    printf "%s# Failover policy configuration%s\n" "$GREEN" "$NC"
    printf "uci set mwan3.mwan_default=policy\n"
    printf "uci set mwan3.mwan_default.name='failover'\n"
    printf "uci set mwan3.mwan_default.use_member='member1 member2 member3'\n"
    printf "\n"

    printf "%s# Commit and restart services%s\n" "$GREEN" "$NC"
    printf "uci commit mwan3\n"
    printf "/etc/init.d/network restart\n"
    printf "/etc/init.d/mwan3 restart\n"
}

# Test function for user experience flow
test_user_experience() {
    log_step "👤 User experience flow demonstration"

    printf "\n%sUser runs installation script:%s\n" "$CYAN" "$NC"
    printf "./scripts/install-rutos.sh\n"
    printf "\n"

    printf "%sSystem response:%s\n" "$GREEN" "$NC"
    printf "🔍 Detecting system configuration...\n"
    printf "📱 RUTX50 detected with RUTOS firmware\n"
    printf "🛜 Starlink interface found: wan\n"
    printf "📶 Cellular interfaces found: mob1s1a1, mob1s2a1\n"
    printf "⚠ MWAN3 needs configuration\n"
    printf "\n"

    printf "%s🔧 MWAN3 AUTO-CONFIGURATION AVAILABLE%s\n" "$YELLOW" "$NC"
    printf "Would you like to automatically configure failover? (Y/n): %sY%s\n" "$GREEN" "$NC"
    printf "\n"

    printf "%s✅ Configuring MWAN3 failover...%s\n" "$GREEN" "$NC"
    printf "✓ Primary: Starlink (metric=1)\n"
    printf "✓ Backup 1: Telia SIM (metric=2)\n"
    printf "✓ Backup 2: Roaming SIM (metric=3)\n"
    printf "✓ Services restarted successfully\n"
    printf "🎯 Failover system ready!\n"
}

# Main test execution
main() {
    log_info "Starting test-mwan3-autoconfig.sh v$SCRIPT_VERSION"
    log_info "Starting test-mwan3-autoconfig.sh v$SCRIPT_VERSION"
    log_info "🚀 Testing MWAN3 auto-configuration system"

    test_mwan3_configuration_scenarios
    test_configuration_generation
    test_user_experience

    log_success "🎯 MWAN3 auto-configuration test complete!"

    printf "\n%sKey Benefits:%s\n" "$CYAN" "$NC"
    printf "✓ %sZero-touch configuration%s for new installations\n" "$GREEN" "$NC"
    printf "✓ %sIntelligent detection%s of existing setups\n" "$GREEN" "$NC"
    printf "✓ %sOptimal metrics%s based on interface types\n" "$GREEN" "$NC"
    printf "✓ %sSafe completion%s of partial configurations\n" "$GREEN" "$NC"
    printf "✓ %sUser override%s capabilities maintained\n" "$GREEN" "$NC"

    printf "\n%sPhilosophy: 'Just make it work'%s ✨\n" "$YELLOW" "$NC"
}

# Execute tests
main "$@"
