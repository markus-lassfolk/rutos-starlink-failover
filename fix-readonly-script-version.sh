#!/bin/sh
set -e

# =============================================================================
# Fix SCRIPT_VERSION readonly conflicts in RUTOS scripts
# This script systematically fixes the "readonly: SCRIPT_VERSION: is read only"
# error across all RUTOS scripts by ensuring proper version handling.
# =============================================================================

SCRIPT_VERSION="2.8.0"

# Load RUTOS library if available (but don't fail if not)
if [ -f "$(dirname "$0")/scripts/lib/rutos-lib.sh" ]; then
    . "$(dirname "$0")/scripts/lib/rutos-lib.sh"
    rutos_init_simple "fix-readonly-script-version.sh" "$SCRIPT_VERSION" 2>/dev/null || true
fi

# Fallback logging functions if library not loaded
if ! command -v log_info >/dev/null 2>&1; then
    log_info() { printf "[INFO] %s\n" "$1"; }
    log_error() { printf "[ERROR] %s\n" "$1" >&2; }
    log_warning() { printf "[WARNING] %s\n" "$1"; }
    log_success() { printf "[SUCCESS] %s\n" "$1"; }
    log_debug() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] %s\n" "$1" >&2 || true; }
fi

DRY_RUN="${DRY_RUN:-0}"
DEBUG="${DEBUG:-0}"

log_info "======================================================================"
log_info "RUTOS Script Version Conflict Fix v$SCRIPT_VERSION"
log_info "======================================================================"
log_info "Fixing 'readonly: SCRIPT_VERSION: is read only' errors"
log_info "DRY_RUN: $DRY_RUN (1=preview changes, 0=apply fixes)"
log_info "DEBUG: $DEBUG"
log_info "======================================================================"

# Function to fix a single script file
fix_script_version_conflicts() {
    script_file="$1"

    if [ ! -f "$script_file" ]; then
        log_error "Script not found: $script_file"
        return 1
    fi

    log_info "Processing: $script_file"

    # Create temporary file for processing
    temp_file="/tmp/fix_script_$$.tmp"

    # Extract current version from the script (first occurrence)
    current_version=$(grep '^SCRIPT_VERSION=' "$script_file" | head -1 | sed 's/SCRIPT_VERSION=//; s/"//g; s/'\''//g' 2>/dev/null || echo "2.8.0")
    log_debug "Detected current version: $current_version"

    # Create the fixed version by processing line by line
    {
        found_lib_section=0
        version_added=0
        skip_next_blank=0

        while IFS= read -r line; do
            # Skip any existing SCRIPT_VERSION or readonly SCRIPT_VERSION lines
            case "$line" in
                SCRIPT_VERSION=* | readonly\ SCRIPT_VERSION* | "readonly SCRIPT_VERSION"*)
                    log_debug "Removing line: $line"
                    skip_next_blank=1
                    continue
                    ;;
            esac

            # Skip blank lines immediately after removed version lines
            if [ "$skip_next_blank" = "1" ] && [ -z "$line" ]; then
                skip_next_blank=0
                continue
            fi
            skip_next_blank=0

            # Check for library loading section
            case "$line" in
                *"# CRITICAL: Load RUTOS library system"* | *". \"*rutos-lib.sh"* | *"rutos_init"*)
                    if [ "$found_lib_section" = "0" ] && [ "$version_added" = "0" ]; then
                        # Add version information before the library section
                        echo ""
                        echo "# Version information (auto-updated by update-version.sh)"
                        echo "SCRIPT_VERSION=\"$current_version\""
                        echo ""
                        version_added=1
                        found_lib_section=1
                    fi
                    ;;
            esac

            # Output the current line
            echo "$line"

        done <"$script_file"

        # If we never found a library section, add version at the end of header comments
        if [ "$version_added" = "0" ]; then
            echo ""
            echo "# Version information (auto-updated by update-version.sh)"
            echo "SCRIPT_VERSION=\"$current_version\""
        fi

    } >"$temp_file"

    # Count changes
    original_version_lines=$(grep -c '^SCRIPT_VERSION=\|^readonly SCRIPT_VERSION' "$script_file" 2>/dev/null || echo 0)
    new_version_lines=$(grep -c '^SCRIPT_VERSION=' "$temp_file" 2>/dev/null || echo 0)

    if [ "$original_version_lines" -gt 1 ] || [ "$new_version_lines" -ne 1 ]; then
        if [ "$DRY_RUN" = "1" ]; then
            log_warning "[DRY-RUN] Would fix: $script_file"
            log_warning "  - Original version lines: $original_version_lines"
            log_warning "  - New version lines: $new_version_lines"
            log_warning "  - Current version: $current_version"
        else
            # Apply the fix
            if cp "$temp_file" "$script_file" 2>/dev/null; then
                log_success "Fixed: $script_file (removed $((original_version_lines - 1)) duplicate version lines)"
                log_debug "  - Set version to: $current_version"
                log_debug "  - Removed readonly declarations"
                return 0
            else
                log_error "Failed to update: $script_file"
                rm -f "$temp_file" 2>/dev/null || true
                return 1
            fi
        fi
    else
        log_debug "Skipped: $script_file (already correct)"
    fi

    # Cleanup
    rm -f "$temp_file" 2>/dev/null || true
    return 0
}

# Find all RUTOS scripts that need fixing
log_info "Scanning for RUTOS scripts with version conflicts..."

fixed_count=0
skipped_count=0
error_count=0

# Process scripts in main scripts directory
if [ -d "scripts" ]; then
    log_info "Processing scripts/ directory..."
    find scripts -name "*-rutos.sh" -type f | while IFS= read -r script_file; do
        # Check if script has version conflicts
        version_lines=$(grep -c '^SCRIPT_VERSION=\|^readonly SCRIPT_VERSION' "$script_file" 2>/dev/null || echo 0)
        if [ "$version_lines" -gt 1 ]; then
            if fix_script_version_conflicts "$script_file"; then
                fixed_count=$((fixed_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        else
            skipped_count=$((skipped_count + 1))
            log_debug "Skipped: $script_file (no conflicts detected)"
        fi
    done
fi

# Process scripts in Starlink-RUTOS-Failover directory
if [ -d "Starlink-RUTOS-Failover" ]; then
    log_info "Processing Starlink-RUTOS-Failover/ directory..."
    find Starlink-RUTOS-Failover -name "*-rutos.sh" -type f | while IFS= read -r script_file; do
        # Check if script has version conflicts
        version_lines=$(grep -c '^SCRIPT_VERSION=\|^readonly SCRIPT_VERSION' "$script_file" 2>/dev/null || echo 0)
        if [ "$version_lines" -gt 1 ]; then
            if fix_script_version_conflicts "$script_file"; then
                fixed_count=$((fixed_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        else
            skipped_count=$((skipped_count + 1))
            log_debug "Skipped: $script_file (no conflicts detected)"
        fi
    done
fi

# Get final counts (since subshell variables don't persist)
fixed_count=$(find scripts Starlink-RUTOS-Failover -name "*-rutos.sh" -type f 2>/dev/null | while IFS= read -r script_file; do
    version_lines=$(grep -c '^SCRIPT_VERSION=\|^readonly SCRIPT_VERSION' "$script_file" 2>/dev/null || echo 0)
    if [ "$version_lines" -gt 1 ]; then
        echo "fix_needed"
    fi
done | wc -l)

total_scripts=$(find scripts Starlink-RUTOS-Failover -name "*-rutos.sh" -type f 2>/dev/null | wc -l)
skipped_count=$((total_scripts - fixed_count))

# Summary
log_info "======================================================================"
log_info "RUTOS Script Version Conflict Fix Complete"
log_info "======================================================================"
if [ "$DRY_RUN" = "1" ]; then
    log_info "DRY-RUN SUMMARY (no changes applied):"
else
    log_info "SUMMARY:"
fi
log_info "Total scripts found: $total_scripts"
log_info "Scripts needing fixes: $fixed_count"
log_info "Scripts already correct: $skipped_count"
log_info "======================================================================"

if [ "$DRY_RUN" = "1" ]; then
    if [ "$fixed_count" -gt 0 ]; then
        log_info "To apply fixes, run: DRY_RUN=0 $0"
    else
        log_success "All scripts are already correct - no fixes needed!"
    fi
else
    if [ "$fixed_count" -gt 0 ]; then
        log_success "All $fixed_count script version conflicts have been resolved!"
        log_info "Scripts should now work correctly with the RUTOS library system."
    else
        log_success "All scripts were already correct - no changes needed!"
    fi
fi
