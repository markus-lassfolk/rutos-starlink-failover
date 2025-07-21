#!/bin/sh
# shellcheck disable=SC2016  # Fix script uses single quotes intentionally for sed patterns
# Script: fix-final-issues.sh
# Version: 2.4.12
# Description: Fix remaining validation issues after comprehensive cleanup

set -e

# Version information
# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Fix unused color variables by adding shellcheck disable comments
fix_unused_colors() {
    log_step "Fixing unused color variables"

    # Files with unused colors based on validation output
    color_files="
Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh
Starlink-RUTOS-Failover/AzureLogging/setup-analysis-environment.sh
Starlink-RUTOS-Failover/generate_api_docs.sh
Starlink-RUTOS-Failover/starlink_monitor-rutos.sh
scripts/check_starlink_api_change.sh
scripts/cleanup-rutos.sh
scripts/setup-dev-environment.sh
scripts/upgrade-rutos.sh
tests/test-suite.sh
"

    for file in $color_files; do
        if [ -f "$file" ]; then
            log_info "Processing unused colors in: $file"

            # Add shellcheck disable comment for unused color variables
            if grep -q "^RED=" "$file" && ! grep -q "# shellcheck disable=SC2034" "$file"; then
                # Find the line with color definitions and add disable comment before it
                sed -i '/^# Standard colors for consistent output/a\
# shellcheck disable=SC2034  # Color variables may not all be used in every script' "$file"
                log_success "✓ Added shellcheck disable comment for colors: $file"
            fi
        fi
    done
}

# Fix unused SCRIPT_VERSION variables by adding usage patterns
fix_unused_script_versions() {
    log_step "Fixing unused SCRIPT_VERSION variables"

    # Files with unused SCRIPT_VERSION based on validation output
    version_files="
Starlink-RUTOS-Failover/starlink_logger-rutos.sh
fix-check-interval.sh
scripts/check-security.sh
scripts/check_starlink_api_change.sh
scripts/cleanup-rutos.sh
scripts/format-markdown.sh
scripts/intelligent-config-merge.sh
scripts/merge-config-rutos.sh
scripts/restore-config-rutos.sh
scripts/validate-markdown.sh
test-config-detection.sh
test-config-merge.sh
test_config.sh
tests/test-mwan3-autoconfig.sh
"

    for file in $version_files; do
        if [ -f "$file" ]; then
            log_info "Adding version usage pattern to: $file"

            # Check if file has main function
            if grep -q "^main(" "$file"; then
                # Add version display to main function if not already present
                if ! grep -q "SCRIPT_VERSION" "$file" | grep -v "readonly SCRIPT_VERSION" >/dev/null; then
                    # Add version display at start of main function
                    sed -i '/^main() {/a\
    log_info "Starting '"$(basename "$file")"' v$SCRIPT_VERSION"' "$file"
                    log_success "✓ Added version display to main(): $file"
                fi
            elif grep -q "help.*function\|usage.*function\|show_help" "$file"; then
                # Add version to help/usage function
                sed -i '/printf.*Usage:\|echo.*Usage:\|printf.*Help:\|echo.*Help:/a\
    printf "Version: %s\\n" "$SCRIPT_VERSION"' "$file"
                log_success "✓ Added version to help function: $file"
            else
                # Add simple version display at start of script after logging setup
                if grep -q "log_info\|printf.*INFO" "$file"; then
                    sed -i '/log_info\|printf.*INFO/i\
log_info "'"$(basename "$file")"' v$SCRIPT_VERSION"' "$file"
                    log_success "✓ Added version logging: $file"
                fi
            fi
        fi
    done
}

# Fix unused SCRIPT_NAME variables
fix_unused_script_names() {
    log_step "Fixing unused SCRIPT_NAME variables"

    script_name_files="
Starlink-RUTOS-Failover/AzureLogging/unified-azure-setup-rutos.sh
Starlink-RUTOS-Failover/AzureLogging/verify-azure-setup-rutos.sh
scripts/self-update-rutos.sh
"

    for file in $script_name_files; do
        if [ -f "$file" ]; then
            log_info "Adding SCRIPT_NAME usage to: $file"

            # Add usage pattern for SCRIPT_NAME
            if grep -q "log_info\|printf.*INFO" "$file"; then
                sed -i 's/log_info.*Starting.*/log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"/' "$file"
                log_success "✓ Added SCRIPT_NAME usage: $file"
            fi
        fi
    done
}

# Add version headers to documentation files
fix_documentation_versions() {
    log_step "Adding version headers to documentation files"

    doc_files="
CONFIGURATION_MANAGEMENT.md
DEPLOYMENT-READY.md  
DEPLOYMENT_SUMMARY.md
INSTALLATION_STATUS.md
Starlink-RUTOS-Failover/AzureLogging/DEPLOYMENT_CHECKLIST.md
Starlink-RUTOS-Failover/AzureLogging/INSTALLATION_GUIDE.md
Starlink-RUTOS-Failover/AzureLogging/README.md
Starlink-RUTOS-Failover/AzureLogging/analysis/README.md
TESTING.md
automation/README.md
docs/BRANCH_TESTING.md
tests/README.md
"

    for file in $doc_files; do
        if [ -f "$file" ]; then
            # Check if file already has version info
            if ! head -5 "$file" | grep -q "Version:\|v[0-9]"; then
                log_info "Adding version header to: $file"

                # Get first line to determine if it's a title
                first_line=$(head -1 "$file")

                # Add version info after the title
                if echo "$first_line" | grep -q "^#"; then
                    # Markdown title exists, add version after it
                    sed -i '1a\\n<!-- Version: 2.4.12 -->' "$file"
                    log_success "✓ Added version comment to: $file"
                else
                    # No title, add version at top
                    sed -i '1i<!-- Version: 2.4.12 -->\n' "$file"
                    log_success "✓ Added version comment to: $file"
                fi
            else
                log_info "Version already present in: $file"
            fi
        fi
    done
}

# Fix positioning issues (SCRIPT_VERSION after set commands)
fix_positioning_issues() {
    log_step "Fixing SCRIPT_VERSION positioning issues"

    positioning_files="
Starlink-RUTOS-Failover/check_starlink_api-rutos.sh
scripts/check-security.sh
"

    for file in $positioning_files; do
        if [ -f "$file" ]; then
            log_info "Fixing SCRIPT_VERSION positioning in: $file"

            # Move SCRIPT_VERSION after set commands
            if grep -q "^set -" "$file" && grep -q "^SCRIPT_VERSION=" "$file"; then
                # Extract SCRIPT_VERSION line
                version_line=$(grep "^SCRIPT_VERSION=" "$file")
                readonly_line=$(grep "^readonly SCRIPT_VERSION" "$file" 2>/dev/null || echo "")

                # Remove existing lines
                sed -i '/^SCRIPT_VERSION=/d' "$file"
                sed -i '/^readonly SCRIPT_VERSION/d' "$file"

                # Add after last set command
                sed -i '/^set -/a\\n# Version information\n'"$version_line"'\n'"${readonly_line:-readonly SCRIPT_VERSION}" "$file"

                log_success "✓ Fixed SCRIPT_VERSION positioning: $file"
            fi
        fi
    done
}

# Fix specific issues in pre-commit-validation.sh
fix_validation_script_issues() {
    log_step "Fixing pre-commit-validation.sh specific issues"

    file="scripts/pre-commit-validation.sh"
    if [ -f "$file" ]; then
        # Remove unused shebang_line_num variable
        sed -i '/local shebang_line_num=1/d' "$file"

        # Fix sed usage to use parameter expansion - use simpler approach
        sed -i 's/dir_pattern=$(echo "$pattern" | sed.*)/dir_pattern=${pattern%\/}/' "$file"

        log_success "✓ Fixed pre-commit-validation.sh issues"
    fi
}

# Main execution
main() {
    log_info "Starting final validation fixes v$SCRIPT_VERSION"

    fix_unused_colors
    fix_unused_script_versions
    fix_unused_script_names
    fix_documentation_versions
    fix_positioning_issues
    fix_validation_script_issues

    log_success "All final validation fixes completed"
    log_info "Run pre-commit validation again to verify fixes"
}

# Execute main function
main "$@"
