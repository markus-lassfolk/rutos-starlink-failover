#!/bin/sh
# Quick validation fixes for the most critical issues
# Version: 2.7.1

set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
# shellcheck disable=SC2034 # Colors defined per project convention, some may be unused
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

FIXES_APPLIED=0

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

fix_color_detection() {
    log_info "Adding color detection logic to verify-install-completeness.sh..."

    # Add proper color detection after line 6
    awk '
    NR == 6 && /^# Colors for output$/ {
        print $0
        print ""
        print "# Color detection logic (RUTOS compatible)"
        print "if [ -t 1 ] && [ \"${TERM:-}\" != \"dumb\" ] && [ \"${NO_COLOR:-}\" != \"1\" ]; then"
        next
    }
    { print }
    ' "verify-install-completeness.sh" >"verify-install-completeness.sh.tmp"

    mv "verify-install-completeness.sh.tmp" "verify-install-completeness.sh"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
    log_success "Fixed color detection in verify-install-completeness.sh"
}

fix_unused_colors() {
    log_info "Removing unused color variables..."

    # Fix test-rutos-fixes.sh
    if grep -q "CYAN=" "test-rutos-fixes.sh"; then
        sed -i 's/.*CYAN=.*//g' "test-rutos-fixes.sh"
        sed -i '/^$/N;/^\n$/d' "test-rutos-fixes.sh" # Remove empty lines
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        log_success "Removed unused CYAN from test-rutos-fixes.sh"
    fi

    # Fix verify-install-completeness.sh
    if grep -q "RED=" "verify-install-completeness.sh"; then
        # Only keep used colors (GREEN, YELLOW, BLUE, NC)
        sed -i '/RED=/d; /CYAN=/d' "verify-install-completeness.sh"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        log_success "Removed unused colors from verify-install-completeness.sh"
    fi
}

fix_printf_formats() {
    log_info "Fixing printf format strings..."

    # Fix test-rutos-fixes.sh printf issues
    if [ -f "test-rutos-fixes.sh" ]; then
        # shellcheck disable=SC2016 # These are literal sed patterns, not variable expansions
        sed -i 's/printf "${GREEN}/printf "%s" "${GREEN}/g' "test-rutos-fixes.sh"
        # shellcheck disable=SC2016 # These are literal sed patterns, not variable expansions
        sed -i 's/printf "${YELLOW}/printf "%s" "${YELLOW}/g' "test-rutos-fixes.sh"
        # shellcheck disable=SC2016 # These are literal sed patterns, not variable expansions
        sed -i 's/printf "${BLUE}/printf "%s" "${BLUE}/g' "test-rutos-fixes.sh"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        log_success "Fixed printf formats in test-rutos-fixes.sh"
    fi
}

fix_grep_optimizations() {
    log_info "Applying grep optimizations..."

    # Fix comprehensive-stats-analysis.sh
    if [ -f "comprehensive-stats-analysis.sh" ]; then
        # Replace grep|wc -l with grep -c
        sed -i 's/grep.*|.*wc -l/grep -c/g' "comprehensive-stats-analysis.sh"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        log_success "Optimized grep usage in comprehensive-stats-analysis.sh"
    fi
}

fix_sc2004_arithmetic() {
    log_info "Fixing unnecessary \${} in arithmetic variables..."

    # Fix the unified monitor script
    if [ -f "Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh" ]; then
        # Fix SC2004 issues (unnecessary ${} in arithmetic)
        # shellcheck disable=SC2016 # These are literal sed patterns, not variable expansions
        sed -i 's/\${packet_loss}/packet_loss/g' "Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh"
        # shellcheck disable=SC2016 # These are literal sed patterns, not variable expansions
        sed -i 's/\${obstruction}/obstruction/g' "Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        log_success "Fixed arithmetic variables in starlink_monitor_unified-rutos.sh"
    fi
}

# Main execution
log_info "Starting validation fixes for critical issues... (v$SCRIPT_VERSION)"

fix_color_detection
fix_unused_colors
fix_printf_formats
fix_grep_optimizations
fix_sc2004_arithmetic

log_success "Validation fixes complete! Applied $FIXES_APPLIED fixes."
log_info "These fixes address CRITICAL and MAJOR issues identified in validation."
log_info "Run the validation script again to verify improvements."
