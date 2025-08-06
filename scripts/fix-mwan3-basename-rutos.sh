#!/bin/sh
set -e

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# CRITICAL: Load RUTOS library system (REQUIRED)
. "$(dirname "$0")/lib/rutos-lib.sh" 2>/dev/null || {
    # Fallback if library not available
    log_info() { printf "[INFO] %s\n" "$*"; }
    log_error() { printf "[ERROR] %s\n" "$*"; }
    log_success() { printf "[SUCCESS] %s\n" "$*"; }
    log_warning() { printf "[WARNING] %s\n" "$*"; }
    log_debug() { [ "${DEBUG:-0}" = "1" ] && printf "[DEBUG] %s\n" "$*"; }
}

# CRITICAL: Initialize script with library features (REQUIRED)
if command -v rutos_init >/dev/null 2>&1; then
    rutos_init "fix-mwan3-basename-rutos.sh" "$SCRIPT_VERSION"
else
    log_info "RUTOS library not available - using fallback logging"
fi

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Fix BusyBox basename compatibility issues in MWAN3 hotplug scripts.

This script addresses the common RUTOS issue where MWAN3 hotplug scripts
produce "Usage: basename" errors due to incorrect basename command usage.

OPTIONS:
    --dry-run           Show what would be fixed without making changes
    --backup-suffix     Suffix for backup files (default: backup-YYYYMMDD)
    --check-only        Only check for issues, don't fix them
    --force             Fix issues even in non-interactive mode
    -h, --help          Show this help

WHAT IT FIXES:
    • Incorrect basename usage patterns in MWAN3 scripts
    • Creates robust basename wrapper for future compatibility
    • Backs up original scripts before modification

COMMON SYMPTOMS:
    • "BusyBox v1.34.1 multi-call binary" messages during mwan3 operations
    • "Usage: basename FILE [SUFFIX]" errors in logs
    • Hotplug script failures during interface changes

FILES CHECKED:
    • /etc/hotplug.d/iface/15-mwan3
    • /etc/hotplug.d/iface/16-mwan3-user
    • /usr/sbin/mwan3
    • /lib/mwan3/mwan3.sh

EXAMPLES:
    $0                      # Interactive mode with fixes
    $0 --dry-run            # Show what would be fixed
    $0 --check-only         # Only check for issues
    $0 --force --dry-run    # Non-interactive dry run
EOF
}

# Parse command line arguments
DRY_RUN=0
CHECK_ONLY=0
FORCE=0
BACKUP_SUFFIX="backup-$(date +%Y%m%d)"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1 ;;
        --backup-suffix)
            shift; BACKUP_SUFFIX="${1:-$BACKUP_SUFFIX}" ;;
        --check-only)
            CHECK_ONLY=1 ;;
        --force)
            FORCE=1 ;;
        -h|--help)
            show_usage; exit 0 ;;
        *)
            log_error "Unknown option: $1"
            show_usage; exit 1 ;;
    esac
    shift
done

# Fix basename usage in a single script
fix_basename_in_script() {
    local script_path="$1"
    local backup_file="${script_path}.${BACKUP_SUFFIX}"
    
    # Create backup
    if cp "$script_path" "$backup_file"; then
        log_success "   ✅ Backup created: $backup_file"
        
        # Apply fixes with multiple patterns
        temp_file="/tmp/basename_fix_$$"
        
        # Pattern 1: basename $VAR -> basename "$VAR" 2>/dev/null || echo "unknown"
        # Pattern 2: basename $1 -> basename "$1" 2>/dev/null || echo "unknown"
        # Pattern 3: basename $script -> basename "$script" (TTY hotplug specific)
        sed -e 's|basename \$\([A-Za-z_][A-Za-z0-9_]*\)|basename "$\1"|g' \
            -e 's|basename \$\([0-9]\)|basename "$\1"|g' \
            -e 's|basename \$DEV|basename "$DEV"|g' \
            -e 's|basename \$DEVICE|basename "$DEVICE"|g' \
            -e 's|basename \$script|basename "$script"|g' \
            "$script_path" > "$temp_file"
            
        if [ -s "$temp_file" ]; then
            if mv "$temp_file" "$script_path"; then
                log_success "   ✅ Fixed basename issues in $script_path"
                scripts_fixed=$((scripts_fixed + 1))
            else
                log_error "   ❌ Failed to apply fixes to $script_path"
                rm -f "$temp_file"
            fi
        else
            log_error "   ❌ Failed to process $script_path (empty output)"
            rm -f "$temp_file"
        fi
    else
        log_error "   ❌ Failed to create backup for $script_path"
    fi
}

# Interactive confirmation unless forced
is_interactive() {
    [ -t 0 ] && [ -t 1 ] && [ "${FORCE:-0}" != "1" ]
}

confirm_action() {
    local message="$1"
    if is_interactive; then
        printf "%s (y/N): " "$message"
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    else
        return 0  # Auto-confirm in non-interactive mode
    fi
}

# Main fix function
fix_mwan3_basename_issues() {
    log_info "🔧 MWAN3 BusyBox Basename Compatibility Fix v$SCRIPT_VERSION"
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "🧪 DRY-RUN MODE: No changes will be made"
    fi
    
    if [ "$CHECK_ONLY" = "1" ]; then
        log_info "🔍 CHECK-ONLY MODE: Only checking for issues"
    fi

    # Core MWAN3 script locations
    mwan3_scripts="
        /etc/hotplug.d/iface/15-mwan3
        /etc/hotplug.d/iface/16-mwan3-user
        /etc/hotplug.d/tty/01-serial-symlink.sh
        /usr/sbin/mwan3
        /lib/mwan3/mwan3.sh
        /usr/local/usr/lib/mwan3/common.sh
        /usr/local/usr/lib/mwan3/mwan3.sh
    "
    
    # Additional system scripts with basename issues (found on RUTX50)
    system_scripts="
        /bin/fmt-usb-msd.sh
        /etc/chilli/down.sh
        /etc/chilli/up.sh
        /etc/hotplug.d/tty/01-serial-symlink.sh
        /lib/functions/procd.sh
        /lib/functions.sh
        /usr/local/usr/lib/netifd/proto/wwan.sh
        /usr/sbin/hostblock.sh
    "

    issues_found=0
    scripts_checked=0
    scripts_fixed=0

    log_info "📋 Checking MWAN3 and system scripts for basename compatibility issues..."

    # Check MWAN3 scripts first
    log_info "🎯 Checking MWAN3 scripts..."
    for script_path in $mwan3_scripts; do
        if [ -f "$script_path" ]; then
            scripts_checked=$((scripts_checked + 1))
            log_debug "Checking: $script_path"

            # Look for problematic patterns (catches basename $script, basename $VAR, etc.)
            problematic_patterns="basename \$[A-Za-z_][A-Za-z0-9_]*[^\"']|basename \$[0-9]|basename [^\"'(]"
            if grep -E "$problematic_patterns" "$script_path" >/dev/null 2>&1; then
                issues_found=$((issues_found + 1))
                log_warning "❌ Issues found in: $script_path"
                
                # Show the problematic lines
                problem_lines=$(grep -n -E "$problematic_patterns" "$script_path" | head -3)
                echo "$problem_lines" | while read -r line; do
                    log_info "   Line: $line"
                done
                
                if [ "$CHECK_ONLY" != "1" ]; then
                    if confirm_action "Fix issues in $script_path?"; then
                        if [ "$DRY_RUN" = "1" ]; then
                            log_info "   DRY-RUN: Would fix $script_path"
                            scripts_fixed=$((scripts_fixed + 1))
                        else
                            fix_basename_in_script "$script_path"
                        fi
                    fi
                fi
            else
                log_success "✅ No issues found in: $script_path"
            fi
        else
            log_debug "Not found: $script_path"
        fi
    done
    
    # Check system scripts (with user confirmation for broader changes)
    if [ "$issues_found" -gt 0 ] || confirm_action "Also check system scripts for basename issues?"; then
        log_info "🔧 Checking system scripts..."
        for script_path in $system_scripts; do
            if [ -f "$script_path" ]; then
                scripts_checked=$((scripts_checked + 1))
                log_debug "Checking: $script_path"

                # Look for problematic patterns  
                problematic_patterns="basename \$[A-Za-z_]|basename [^\"'(]"
                if grep -E "$problematic_patterns" "$script_path" >/dev/null 2>&1; then
                    issues_found=$((issues_found + 1))
                    log_warning "❌ Issues found in: $script_path"
                    
                    # Show the problematic lines
                    problem_lines=$(grep -n -E "$problematic_patterns" "$script_path" | head -2)
                    echo "$problem_lines" | while read -r line; do
                        log_info "   Line: $line"
                    done
                    
                    if [ "$CHECK_ONLY" != "1" ]; then
                        if confirm_action "Fix system script $script_path? (CAUTION: System file)"; then
                            if [ "$DRY_RUN" = "1" ]; then
                                log_info "   DRY-RUN: Would fix $script_path"
                                scripts_fixed=$((scripts_fixed + 1))
                            else
                                fix_basename_in_script "$script_path"
                            fi
                        fi
                    fi
                else
                    log_success "✅ No issues found in: $script_path"
                fi
            else
                log_debug "Not found: $script_path"
            fi
        done
    fi

    # Summary
    log_info "📊 Summary:"
    log_info "   Scripts checked: $scripts_checked"
    log_info "   Issues found: $issues_found"
    if [ "$CHECK_ONLY" != "1" ]; then
        log_info "   Scripts fixed: $scripts_fixed"
    fi

    # Create basename wrapper if issues were found
    if [ "$issues_found" -gt 0 ] && [ "$CHECK_ONLY" != "1" ]; then
        log_info "🛠️  Creating robust basename wrapper for future compatibility..."
        
        basename_wrapper="/usr/local/bin/basename"
        
        if [ "$DRY_RUN" = "1" ]; then
            log_info "DRY-RUN: Would create basename wrapper at $basename_wrapper"
        else
            if confirm_action "Create robust basename wrapper?"; then
                mkdir -p "$(dirname "$basename_wrapper")" 2>/dev/null || true
                
                cat > "$basename_wrapper" << 'EOF'
#!/bin/sh
# Robust basename wrapper for BusyBox compatibility
# Prevents "Usage: basename" errors from malformed calls

if [ $# -eq 0 ]; then
    echo "unknown"
    exit 0
fi

# Use the real basename with error handling
/bin/basename "$@" 2>/dev/null || echo "unknown"
EOF
                chmod +x "$basename_wrapper"
                log_success "✅ Created robust basename wrapper: $basename_wrapper"
                log_info "💡 Add /usr/local/bin to PATH to use the wrapper"
            fi
        fi
    fi

    # Final recommendations
    if [ "$issues_found" -gt 0 ]; then
        if [ "$CHECK_ONLY" = "1" ]; then
            log_warning "⚠️  Issues found! Run without --check-only to fix them."
        elif [ "$scripts_fixed" -gt 0 ]; then
            log_success "🎉 Fixes applied! Test MWAN3 operations:"
            log_info "   mwan3 status"
            log_info "   mwan3 restart"
            log_info "   Check for 'Usage: basename' errors in logs"
        fi
        
        log_info "🔧 Monitor for basename errors with:"
        log_info "   ./quick-error-filter.sh /var/log/messages"
        log_info "   ./analyze-deployment-issues-rutos.sh -r /var/log/syslog"
    else
        log_success "🎉 No basename compatibility issues found!"
    fi
}

# Execute main function
fix_mwan3_basename_issues
