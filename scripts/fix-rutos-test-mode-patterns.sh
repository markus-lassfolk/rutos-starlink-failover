#!/bin/sh
# Script: fix-rutos-test-mode-patterns.sh
# Version: 2.8.0
# Description: Fix incorrect RUTOS_TEST_MODE usage patterns across the codebase

set -e

# Version information
SCRIPT_VERSION="2.8.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "fix-rutos-test-mode-patterns.sh" "$SCRIPT_VERSION"

# List of files with incorrect RUTOS_TEST_MODE patterns (from grep search)
AFFECTED_FILES="
test-bootstrap-remote.sh
Starlink-RUTOS-Failover/check_starlink_api-rutos.sh
Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh
gps-integration/gps-collector-rutos.sh
deploy-starlink-solution-rutos.sh
cellular-integration/smart-failover-engine-rutos.sh
cellular-integration/optimize-logger-with-cellular-rutos.sh
cellular-integration/demo-cellular-integration-rutos.sh
cellular-integration/cellular-data-collector-rutos.sh
gps-integration/gps-location-analyzer-rutos.sh
scripts/auto-detect-config-rutos.sh
Starlink-RUTOS-Failover/starlink_logger-rutos.sh
scripts/bootstrap-install-rutos.sh
Starlink-RUTOS-Failover/AzureLogging/complete-setup-rutos.sh
gps-integration/integrate-gps-into-install-rutos.sh
Starlink-RUTOS-Failover/AzureLogging/log-shipper-rutos.sh
gps-integration/optimize-logger-with-gps-rutos.sh
Starlink-RUTOS-Failover/AzureLogging/setup-persistent-logging-rutos.sh
"

# Main function to fix RUTOS_TEST_MODE patterns
main() {
    log_info "Starting RUTOS_TEST_MODE pattern fixes v$SCRIPT_VERSION"

    # Get workspace root
    workspace_root="$(cd "$(dirname "$0")/.." && pwd)"
    log_debug "Workspace root: $workspace_root"

    # Counters
    files_processed=0
    files_fixed=0
    files_skipped=0

    log_step "Processing files with incorrect RUTOS_TEST_MODE patterns"

    # Process each affected file
    echo "$AFFECTED_FILES" | while read -r file_path; do
        # Skip empty lines
        [ -z "$file_path" ] && continue

        full_path="$workspace_root/$file_path"
        files_processed=$((files_processed + 1))

        log_debug "Processing: $file_path"

        if [ ! -f "$full_path" ]; then
            log_warning "File not found: $full_path"
            files_skipped=$((files_skipped + 1))
            continue
        fi

        # Check if file contains the incorrect pattern
        if grep -q '\[ "$DRY_RUN" = "1" \] || \[ "$RUTOS_TEST_MODE" = "1" \]' "$full_path"; then
            log_info "Fixing: $file_path"

            # Create backup
            backup_file="${full_path}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$full_path" "$backup_file"
            log_debug "Created backup: $backup_file"

            # Apply fix using sed
            if fix_file_pattern "$full_path"; then
                files_fixed=$((files_fixed + 1))
                log_success "Fixed: $file_path"
            else
                log_error "Failed to fix: $file_path"
                # Restore backup
                mv "$backup_file" "$full_path"
                log_info "Restored backup for: $file_path"
            fi
        else
            log_debug "No incorrect pattern found in: $file_path"
        fi
    done

    # Summary
    log_step "Fix Summary"
    log_info "Files processed: $files_processed"
    log_success "Files fixed: $files_fixed"
    if [ $files_skipped -gt 0 ]; then
        log_warning "Files skipped: $files_skipped"
    fi

    if [ $files_fixed -gt 0 ]; then
        log_info "RUTOS_TEST_MODE pattern fixes completed successfully"
        log_info "RUTOS_TEST_MODE now properly enables trace logging only"
        log_info "DRY_RUN continues to control execution prevention"
    else
        log_warning "No files were fixed - they may already be correct"
    fi
}

# Function to fix the pattern in a specific file
fix_file_pattern() {
    file_path="$1"

    # Replace the incorrect pattern with correct DRY_RUN-only check
    # Pattern: if [ "$DRY_RUN" = "1" ] || [ "$RUTOS_TEST_MODE" = "1" ]; then
    # Replace with: if [ "$DRY_RUN" = "1" ]; then

    sed_script='
        s/if \[ "\$DRY_RUN" = "1" \] || \[ "\$RUTOS_TEST_MODE" = "1" \]; then/if [ "$DRY_RUN" = "1" ]; then/g
        s/if \[ \$DRY_RUN = 1 \] || \[ \$RUTOS_TEST_MODE = 1 \]; then/if [ $DRY_RUN = 1 ]; then/g
    '

    # Apply the fix
    if sed "$sed_script" "$file_path" >"${file_path}.tmp"; then
        mv "${file_path}.tmp" "$file_path"
        return 0
    else
        rm -f "${file_path}.tmp"
        return 1
    fi
}

# Function to validate the fixes
validate_fixes() {
    log_step "Validating fixes"

    workspace_root="$(cd "$(dirname "$0")/.." && pwd)"
    remaining_issues=0

    # Check for any remaining incorrect patterns
    log_debug "Checking for remaining incorrect patterns..."

    find "$workspace_root" -name "*.sh" -type f -exec grep -l '\[ "$DRY_RUN" = "1" \] || \[ "$RUTOS_TEST_MODE" = "1" \]' {} \; | while read -r file; do
        log_warning "Still has incorrect pattern: $file"
        remaining_issues=$((remaining_issues + 1))
    done

    if [ $remaining_issues -eq 0 ]; then
        log_success "All RUTOS_TEST_MODE patterns have been corrected"
    else
        log_error "$remaining_issues files still have incorrect patterns"
        return 1
    fi

    return 0
}

# Execute main function
main "$@"

# Validate the fixes
if [ "${SKIP_VALIDATION:-0}" != "1" ]; then
    validate_fixes
fi
