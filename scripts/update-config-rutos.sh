#!/bin/sh

# ==============================================================================
# Configuration Update Script
#
# This script merges new configuration options from templates into existing
# configuration files while preserving all user customizations.
#
# Usage: ./update-config.sh [--backup] [--dry-run]
# ==============================================================================

set -eu

# Script version information
# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION
SCRIPT_NAME="update-config.sh"
COMPATIBLE_INSTALL_VERSION="1.0.0"

# Colors for output
# Check if terminal supports colors (simplified for RUTOS compatibility)
# shellcheck disable=SC2034
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

# Configuration paths
INSTALL_DIR="/root/starlink-monitor"
CONFIG_DIR="$INSTALL_DIR/config"
CURRENT_CONFIG="$CONFIG_DIR/config.sh"
TEMPLATE_CONFIG="$CONFIG_DIR/config.template.sh"
ADVANCED_TEMPLATE="$CONFIG_DIR/config.advanced.template.sh"

# Options
DRY_RUN=false
CREATE_BACKUP=false

# RUTOS test mode support
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-0}"
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    DRY_RUN=true
fi

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --backup)
            CREATE_BACKUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--backup] [--dry-run]"
            echo "  --backup    Create backup of current config"
            echo "  --dry-run   Show what would be changed without making changes"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to print colored output
print_status() {
    color="$1"
    message="$2"
    # Use Method 5 format that works in RUTOS (embed variables in format string)
    case "$color" in
        "$RED") printf "${RED}%s${NC}\n" "$message" ;;
        "$GREEN") printf "${GREEN}%s${NC}\n" "$message" ;;
        "$YELLOW") printf "${YELLOW}%s${NC}\n" "$message" ;;
        "$BLUE") printf "${BLUE}%s${NC}\n" "$message" ;;
        "$CYAN") printf "${CYAN}%s${NC}\n" "$message" ;;
        *) printf "%s\n" "$message" ;;
    esac
}

print_error() {
    print_status "$RED" "❌ $1"
}

print_success() {
    print_status "$GREEN" "✅ $1"
}

print_info() {
    print_status "$BLUE" "ℹ $1"
}

# Early exit in test mode to prevent execution errors
if [ "$RUTOS_TEST_MODE" = "1" ]; then
    print_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

print_warning() {
    print_status "$YELLOW" "⚠ $1"
}

# Function to extract all configuration variables from a file
extract_config_vars() {
    file="$1"

    if [ -f "$file" ]; then
        # Extract all lines that look like variable assignments
        grep '^[A-Z_][A-Z0-9_]*=' "$file" | cut -d'=' -f1 | sort -u
    fi
}

# Function to get configuration value
get_config_value() {
    file="$1"
    key="$2"

    if [ -f "$file" ]; then
        # Extract value after = sign, remove quotes and comments
        grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*#.*$//;s/^"//;s/"$//;s/^'\''//;s/'\''$//'
    fi
}

# Function to get the comment/documentation for a setting
get_config_comment() {
    file="$1"
    key="$2"

    if [ -f "$file" ]; then
        # Get the comment lines before the setting
        line_num=$(grep -n "^${key}=" "$file" | head -1 | cut -d: -f1)
        if [ -n "$line_num" ]; then
            # Get previous lines that are comments
            start_line=$((line_num - 10))
            [ $start_line -lt 1 ] && start_line=1

            sed -n "${start_line},$((line_num - 1))p" "$file" | tac | sed '/^[[:space:]]*$/q' | tac | grep '^[[:space:]]*#'
        fi
    fi
}

# Function to backup current config
backup_config() {
    if [ "$CREATE_BACKUP" = true ] && [ -f "$CURRENT_CONFIG" ]; then
        backup_file="$CURRENT_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CURRENT_CONFIG" "$backup_file"
        print_success "Backup created: $backup_file"
    fi
}

# Function to determine which template to use
determine_template() {
    template_file="$TEMPLATE_CONFIG"

    # Check if user has advanced features enabled
    if [ -f "$CURRENT_CONFIG" ] && grep -q "ENABLE_ADVANCED_FEATURES.*1" "$CURRENT_CONFIG" 2>/dev/null; then
        if [ -f "$ADVANCED_TEMPLATE" ]; then
            template_file="$ADVANCED_TEMPLATE"
            print_info "Using advanced template (advanced features detected)"
        else
            print_warning "Advanced features enabled but advanced template not found, using basic template"
        fi
    else
        print_info "Using basic template"
    fi

    echo "$template_file"
}

# Function to merge configurations
merge_configs() {
    current_config="$1"
    template_config="$2"
    output_file="$3"

    print_info "Merging configuration updates..."

    # Get all variables from both files
    current_vars=$(extract_config_vars "$current_config")
    template_vars=$(extract_config_vars "$template_config")

    # Find new variables in template
    new_vars=""
    for var in $template_vars; do
        if ! echo "$current_vars" | grep -q "^$var$"; then
            new_vars="$new_vars $var"
        fi
    done

    # Find obsolete variables in current config
    obsolete_vars=""
    for var in $current_vars; do
        if ! echo "$template_vars" | grep -q "^$var$"; then
            obsolete_vars="$obsolete_vars $var"
        fi
    done

    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN - Changes that would be made:"

        if [ -n "$new_vars" ]; then
            print_info "New configuration options to add:"
            for var in $new_vars; do
                value=$(get_config_value "$template_config" "$var")
                print_info "  + $var=\"$value\""
            done
        fi

        if [ -n "$obsolete_vars" ]; then
            print_warning "Obsolete configuration options (will be commented out):"
            for var in $obsolete_vars; do
                value=$(get_config_value "$current_config" "$var")
                print_warning "  # $var=\"$value\""
            done
        fi

        if [ -z "$new_vars" ] && [ -z "$obsolete_vars" ]; then
            print_success "No configuration changes needed"
        fi

        return 0
    fi

    # Create the merged configuration
    temp_file=$(mktemp)

    # Start with template structure
    cp "$template_config" "$temp_file"

    # Preserve all existing user values
    for var in $current_vars; do
        current_value=$(get_config_value "$current_config" "$var")

        if [ -n "$current_value" ]; then
            if grep -q "^${var}=" "$temp_file"; then
                # Update existing variable with user's value (properly escape special characters)
                # Escape backslashes and quotes in the value for sed
                escaped_value=$(printf '%s' "$current_value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/|/\\|/g')
                sed -i "s|^${var}=.*|${var}=\"${escaped_value}\"|" "$temp_file"
                print_success "Preserved $var: $current_value"
            else
                # Variable no longer exists in template, comment it out at the end
                # Properly escape the value for printf
                escaped_value=$(printf '%s' "$current_value" | sed 's/\\/\\\\/g; s/"/\\"/g')
                {
                    printf "\n"
                    printf "# Obsolete setting (kept for reference):\n"
                    printf "# %s=\"%s\"\n" "$var" "$escaped_value"
                } >>"$temp_file"
                print_warning "Obsolete setting commented out: $var"
            fi
        fi
    done

    # Add header comment about the merge
    header="# Configuration merged on $(date) by update-config.sh"
    sed -i "2i\\$header" "$temp_file"

    # Move temp file to output
    mv "$temp_file" "$output_file"

    # Report new settings
    if [ -n "$new_vars" ]; then
        print_info "New configuration options added:"
        for var in $new_vars; do
            value=$(get_config_value "$output_file" "$var")
            print_info "  + $var=\"$value\""
        done

        print_warning "Please review and customize the new settings in $output_file"
    fi

    if [ -z "$new_vars" ] && [ -z "$obsolete_vars" ]; then
        print_success "No configuration changes needed"
    fi
}

# Main function
main() {
    print_info "Configuration Update Tool"
    print_info "========================="
    print_info "Script: $SCRIPT_NAME"
    print_info "Version: $SCRIPT_VERSION"
    print_info "Compatible with install.sh: $COMPATIBLE_INSTALL_VERSION"
    echo ""

    # Check if current config exists
    if [ ! -f "$CURRENT_CONFIG" ]; then
        print_error "Current configuration not found: $CURRENT_CONFIG"
        print_info "Please run the install script first"
        exit 1
    fi

    # Determine which template to use
    template_file=$(determine_template)

    if [ ! -f "$template_file" ]; then
        print_error "Template not found: $template_file"
        print_info "Please run the install script to update templates"
        exit 1
    fi

    # Create backup if requested
    backup_config

    # Merge configurations
    merge_configs "$CURRENT_CONFIG" "$template_file" "$CURRENT_CONFIG"

    # Automatically validate and repair configuration formatting after merge
    if [ "$DRY_RUN" = false ]; then
        print_info "Validating and repairing configuration formatting..."
        validate_script="$INSTALL_DIR/scripts/validate-config-rutos.sh"
        if [ -f "$validate_script" ]; then
            if "$validate_script" "$CURRENT_CONFIG" --repair; then
                print_success "✓ Configuration validation and repair completed"
            else
                print_warning "Configuration validation completed with warnings"
            fi
        else
            print_warning "Validation script not found, skipping automatic repair"
        fi
    fi

    print_success "Configuration update complete!"

    if [ "$DRY_RUN" = false ]; then
        print_info "Next steps:"
        print_info "1. Review your configuration: vi $CURRENT_CONFIG"
        print_info "2. Test the system: systemctl restart starlink-monitor"
        print_info ""
        print_info "Configuration has been automatically validated and repaired."
        print_info "To re-run validation manually: $INSTALL_DIR/scripts/validate-config-rutos.sh"
    fi
}

# Run main function
main "$@"
