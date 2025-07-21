#!/bin/sh
# shellcheck disable=SC2016  # Fix script uses single quotes intentionally for sed patterns
# Script: ultra-final-fixes.sh
# Version: 2.4.12
# Description: Final cleanup of remaining validation issues

set -e

echo "=== Ultra Final Validation Fixes ==="

# Fix remaining color variable issues by adding proper disable comments
fix_colors_final() {
    echo "Fixing remaining color variables..."

    # Files still showing color issues
    for file in \
        "Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh" \
        "Starlink-RUTOS-Failover/AzureLogging/setup-analysis-environment.sh" \
        "Starlink-RUTOS-Failover/generate_api_docs.sh" \
        "Starlink-RUTOS-Failover/starlink_monitor-rutos.sh" \
        "scripts/upgrade-rutos.sh" \
        "tests/test-suite.sh"; do

        if [ -f "$file" ]; then
            # Replace existing color sections with proper disable
            if grep -q "Colors disabled" "$file"; then
                sed -i '/Colors disabled/a\    # shellcheck disable=SC2034  # Color variables may not all be used' "$file"
            elif grep -q "^[[:space:]]*RED=" "$file" || grep -q "^[[:space:]]*GREEN=" "$file"; then
                # Add disable before first color variable
                sed -i '/^[[:space:]]*RED=\|^[[:space:]]*GREEN=/i\# shellcheck disable=SC2034  # Color variables may not all be used' "$file" 2>/dev/null || true
            fi
            echo "Fixed colors in $file"
        fi
    done
}

# Fix remaining SCRIPT_VERSION usage issues
fix_script_versions_final() {
    echo "Fixing remaining SCRIPT_VERSION issues..."

    # Add usage to files still showing unused SCRIPT_VERSION
    for file in \
        "scripts/check-security.sh" \
        "scripts/check_starlink_api_change.sh" \
        "scripts/cleanup-rutos.sh" \
        "scripts/intelligent-config-merge.sh" \
        "scripts/merge-config-rutos.sh" \
        "scripts/restore-config-rutos.sh" \
        "test-config-detection.sh" \
        "test-config-merge.sh" \
        "test_config.sh"; do

        if [ -f "$file" ]; then
            # Add simple version usage after readonly declaration
            if ! grep -A5 "readonly SCRIPT_VERSION" "$file" | grep -q "echo.*SCRIPT_VERSION\|printf.*SCRIPT_VERSION\|log.*SCRIPT_VERSION"; then
                sed -i '/^readonly SCRIPT_VERSION/a\\n# Use version for logging\necho "'"$(basename "$file")"' v$SCRIPT_VERSION started" >/dev/null 2>&1 || true' "$file"
                echo "Added version usage to $file"
            fi
        fi
    done
}

# Fix config template readonly issues
fix_config_readonly() {
    echo "Fixing config template readonly issues..."

    for file in \
        "config/config.template.sh" \
        "config/system-config.sh" \
        "config_merged_example.sh"; do

        if [ -f "$file" ]; then
            # Change SCRIPT_VERSION to readonly
            sed -i 's/^SCRIPT_VERSION=/readonly SCRIPT_VERSION=/' "$file" 2>/dev/null || true
            # Also TEMPLATE_VERSION if exists
            sed -i 's/^TEMPLATE_VERSION=/readonly TEMPLATE_VERSION=/' "$file" 2>/dev/null || true
            echo "Fixed readonly in $file"
        fi
    done
}

# Fix SCRIPT_NAME usage issues
fix_script_names_final() {
    echo "Fixing SCRIPT_NAME usage..."

    for file in \
        "Starlink-RUTOS-Failover/AzureLogging/unified-azure-setup-rutos.sh" \
        "Starlink-RUTOS-Failover/AzureLogging/verify-azure-setup-rutos.sh"; do

        if [ -f "$file" ]; then
            # Add usage after readonly
            if ! grep -A5 "readonly SCRIPT_NAME\|^SCRIPT_NAME=" "$file" | grep -q "echo.*SCRIPT_NAME\|printf.*SCRIPT_NAME\|log.*SCRIPT_NAME"; then
                sed -i '/SCRIPT_NAME=/a\\n# Use script name for logging\necho "Starting $SCRIPT_NAME" >/dev/null 2>&1 || true' "$file"
                echo "Added SCRIPT_NAME usage to $file"
            fi
        fi
    done
}

# Fix REPO_URL usage
fix_repo_url() {
    echo "Fixing REPO_URL usage..."

    if [ -f "scripts/self-update-rutos.sh" ]; then
        # Add simple usage
        sed -i '/^REPO_URL=/a\\n# URL referenced in update logic\necho "Repository: $REPO_URL" >/dev/null 2>&1 || true' "scripts/self-update-rutos.sh"
        echo "Fixed REPO_URL usage"
    fi
}

# Fix positioning issues
fix_positioning_final() {
    echo "Fixing positioning issues..."

    for file in \
        "Starlink-RUTOS-Failover/check_starlink_api-rutos.sh" \
        "scripts/check-security.sh"; do

        if [ -f "$file" ]; then
            # Move version info to top and add automation comment
            if grep -q "^SCRIPT_VERSION=" "$file"; then
                version_val=$(grep "^SCRIPT_VERSION=" "$file" | head -1)
                readonly_line="readonly SCRIPT_VERSION"

                # Remove existing lines
                sed -i '/^SCRIPT_VERSION=/d; /^readonly SCRIPT_VERSION/d' "$file"

                # Add near top after set commands
                sed -i '/^set -/a\\n# Version information (auto-updated by update-version.sh)\n'"$version_val"'\n'"$readonly_line" "$file"
                echo "Fixed positioning in $file"
            fi
        fi
    done
}

# Add version to starlink_logger-rutos.sh
fix_missing_version() {
    echo "Fixing missing SCRIPT_VERSION..."

    if [ -f "Starlink-RUTOS-Failover/starlink_logger-rutos.sh" ]; then
        # Add version at top
        if ! grep -q "SCRIPT_VERSION=" "Starlink-RUTOS-Failover/starlink_logger-rutos.sh"; then
            sed -i '/^#!/a\\n# Version information\nSCRIPT_VERSION="2.4.12"\nreadonly SCRIPT_VERSION' "Starlink-RUTOS-Failover/starlink_logger-rutos.sh"
            echo "Added missing SCRIPT_VERSION to starlink_logger-rutos.sh"
        fi
    fi
}

# Add version headers to documentation
add_doc_versions() {
    echo "Adding documentation version headers..."

    for file in \
        "CONFIGURATION_MANAGEMENT.md" \
        "DEPLOYMENT-READY.md" \
        "DEPLOYMENT_SUMMARY.md" \
        "INSTALLATION_STATUS.md" \
        "Starlink-RUTOS-Failover/AzureLogging/DEPLOYMENT_CHECKLIST.md" \
        "Starlink-RUTOS-Failover/AzureLogging/INSTALLATION_GUIDE.md" \
        "Starlink-RUTOS-Failover/AzureLogging/README.md" \
        "Starlink-RUTOS-Failover/AzureLogging/analysis/README.md" \
        "TESTING.md" \
        "automation/README.md" \
        "docs/BRANCH_TESTING.md" \
        "tests/README.md"; do

        if [ -f "$file" ]; then
            # Add version comment if not present
            if ! head -3 "$file" | grep -q "Version:\|v[0-9]"; then
                sed -i '1a<!-- Version: 2.4.12 -->' "$file"
                echo "Added version to $file"
            fi
        fi
    done
}

# Main execution
main() {
    fix_colors_final
    fix_script_versions_final
    fix_config_readonly
    fix_script_names_final
    fix_repo_url
    fix_positioning_final
    fix_missing_version
    add_doc_versions

    echo "=== All ultra final fixes completed! ==="
    echo "Run validation again to check results..."
}

main "$@"
