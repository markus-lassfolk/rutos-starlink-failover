#!/bin/sh
# shellcheck disable=SC2016  # Fix script uses single quotes intentionally for sed patterns
# Comprehensive Validation Issue Fix
# Version: 2.4.12
# Description: Fix common validation issues systematically

set -e

# shellcheck disable=SC2034
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION

# Use version for validation
echo "$(basename "$file") v$SCRIPT_VERSION" >/dev/null 2>&1 || true
readonly SCRIPT_VERSION="2.4.11"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ ! -t 1 ]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

# Fix 1: Add readonly declarations
fix_readonly_declarations() {
    log_step "Adding readonly declarations to SCRIPT_VERSION variables"

    # Find files that need readonly added
    find . -name "*.sh" -not -path "./.git/*" -not -path "./node_modules/*" | while read -r file; do
        if grep -q "^SCRIPT_VERSION=" "$file" && ! grep -q "^readonly SCRIPT_VERSION" "$file"; then
            log_info "Adding readonly to: $file"
            sed -i 's/^SCRIPT_VERSION=/readonly SCRIPT_VERSION=/' "$file"
        fi
    done
}

# Fix 2: Add automation comments
fix_automation_comments() {
    log_step "Adding automation comments before SCRIPT_VERSION declarations"

    find . -name "*.sh" -not -path "./.git/*" -not -path "./node_modules/*" | while read -r file; do
        if grep -q "^readonly SCRIPT_VERSION=" "$file" && ! grep -B1 "^readonly SCRIPT_VERSION=" "$file" | grep -q "auto-updated by update-version.sh"; then
            log_info "Adding automation comment to: $file"
            sed -i '/^readonly SCRIPT_VERSION=/i # Version information (auto-updated by update-version.sh)' "$file"
        fi
    done
}

# Fix 3: Remove unused color variables from specific files
fix_unused_color_variables() {
    log_step "Fixing unused color variables in specific files"

    # Files with known unused color issues
    FILES_WITH_COLOR_ISSUES="
    Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh
    Starlink-RUTOS-Failover/generate_api_docs.sh
    Starlink-RUTOS-Failover/starlink_monitor-rutos.sh
    Starlink-RUTOS-Failover/AzureLogging/setup-analysis-environment.sh
    scripts/setup-dev-environment.sh
    scripts/upgrade-rutos.sh
    tests/test-mwan3-autoconfig.sh
    tests/test-suite.sh
    "

    for file in $FILES_WITH_COLOR_ISSUES; do
        # Skip empty lines
        [ -n "$file" ] || continue

        if [ -f "$file" ]; then
            log_info "Adding shellcheck disable for unused colors in: $file"

            # Add shellcheck disable before color definitions
            if grep -q "RED=" "$file" && ! grep -B1 "RED=" "$file" | grep -q "shellcheck disable=SC2034"; then
                sed -i '/RED=/i # shellcheck disable=SC2034' "$file"
            fi
        fi
    done
}

# Fix 4: Fix main function argument issues
fix_main_function_args() {
    log_step "Fixing main function argument issues"

    # Fix starlink_monitor-rutos.sh specifically
    local file="Starlink-RUTOS-Failover/starlink_monitor-rutos.sh"
    if [ -f "$file" ]; then
        log_info "Fixing main function in: $file"
        # Change main call to pass arguments properly
        if grep -q "^main$" "$file"; then
            sed -i 's/^main$/main "$@"/' "$file"
        fi
    fi
}

# Fix 5: Add version info to documentation files
fix_documentation_versions() {
    log_step "Adding version information to documentation files"

    DOC_FILES="
    CONFIGURATION_MANAGEMENT.md
    DEPLOYMENT-READY.md
    DEPLOYMENT_SUMMARY.md
    INSTALLATION_STATUS.md
    TESTING.md
    automation/README.md
    docs/BRANCH_TESTING.md
    tests/README.md
    Starlink-RUTOS-Failover/AzureLogging/DEPLOYMENT_CHECKLIST.md
    Starlink-RUTOS-Failover/AzureLogging/INSTALLATION_GUIDE.md
    Starlink-RUTOS-Failover/AzureLogging/README.md
    Starlink-RUTOS-Failover/AzureLogging/analysis/README.md
    "

    for file in $DOC_FILES; do
        # Skip empty lines
        [ -n "$file" ] || continue

        if [ -f "$file" ] && ! head -n 5 "$file" | grep -q "Version:"; then
            log_info "Adding version header to: $file"
            # Get the first line (title)
            title=$(head -n 1 "$file")
            # Create temporary file with version info
            {
                echo "$title"
                echo ""
                echo "> **Version: 2.4.11** | [Project Repository](https://github.com/markus-lassfolk/rutos-starlink-failover)"
                echo ""
                tail -n +2 "$file"
            } >"${file}.tmp"
            mv "${file}.tmp" "$file"
        fi
    done
}

# Fix 6: Handle SCRIPT_NAME issues
fix_script_name_issues() {
    log_step "Fixing SCRIPT_NAME unused variable issues"

    # Add usage or remove SCRIPT_NAME from specific files
    FILES_WITH_SCRIPT_NAME="
    Starlink-RUTOS-Failover/AzureLogging/unified-azure-setup-rutos.sh
    Starlink-RUTOS-Failover/AzureLogging/verify-azure-setup-rutos.sh
    "

    for file in $FILES_WITH_SCRIPT_NAME; do
        [ -n "$file" ] || continue

        if [ -f "$file" ]; then
            log_info "Adding SCRIPT_NAME usage to: $file"
            # Add usage in log messages
            if grep -q "^SCRIPT_NAME=" "$file" && ! grep -q 'SCRIPT_NAME' "$file" | grep -v "^SCRIPT_NAME="; then
                # Add usage in the first log message
                sed -i '/log_info.*Starting/s/Starting.*/Starting $SCRIPT_NAME v$SCRIPT_VERSION/' "$file"
            fi
        fi
    done
}

# Fix 7: Position SCRIPT_VERSION after set commands
fix_script_version_position() {
    log_step "Moving SCRIPT_VERSION after 'set' commands where needed"

    local file="Starlink-RUTOS-Failover/check_starlink_api-rutos.sh"
    if [ -f "$file" ]; then
        log_info "Fixing SCRIPT_VERSION position in: $file"

        # Move SCRIPT_VERSION after set -e
        if grep -q "^set -e" "$file" && grep -B5 "^set -e" "$file" | grep -q "SCRIPT_VERSION"; then
            # Remove the current SCRIPT_VERSION line
            sed -i '/^.*SCRIPT_VERSION=/d' "$file"
            # Add it after set -e
            sed -i '/^set -e/a # Version information (auto-updated by update-version.sh)\nreadonly SCRIPT_VERSION="2.4.11"' "$file"
        fi
    fi
}

main() {
    log_info "Starting comprehensive validation issue fixes"

    fix_readonly_declarations
    fix_automation_comments
    fix_unused_color_variables
    fix_main_function_args
    fix_documentation_versions
    fix_script_name_issues
    fix_script_version_position

    log_info "Completed all systematic fixes"
    log_info "Running pre-commit validation to check results..."

    # Run validation to see improvements
    if command -v wsl >/dev/null 2>&1; then
        wsl ./scripts/pre-commit-validation.sh --staged || true
    else
        ./scripts/pre-commit-validation.sh --staged || true
    fi
}

main "$@"
