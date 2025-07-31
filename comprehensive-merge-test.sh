#!/bin/sh
# Comprehensive test script for configuration merge functionality
# This script extracts and tests the intelligent_config_merge function from install-rutos.sh

set -e

# Version information
SCRIPT_VERSION="2.7.1"

# Enable debug mode by default for testing
DEBUG="${DEBUG:-1}"
CONFIG_DEBUG="${CONFIG_DEBUG:-1}"

# Color setup for output
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

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} %s\n" "$1" >&2
    fi
}

config_debug() {
    if [ "${CONFIG_DEBUG:-0}" = "1" ] || [ "${DEBUG:-0}" = "1" ]; then
        printf "${CYAN}[CONFIG]${NC} %s\n" "$1" >&2
    fi
}

# Extract the intelligent_config_merge function from install-rutos.sh
extract_merge_function() {
    install_script="scripts/install-rutos.sh"

    if [ ! -f "$install_script" ]; then
        log_error "Cannot find install-rutos.sh at: $install_script"
        return 1
    fi

    log_info "Extracting intelligent_config_merge function from: $install_script"

    # Extract the function using awk
    temp_func="/tmp/merge_function_$$.sh"

    awk '
    /^intelligent_config_merge\(\) \{/ { 
        print_func = 1
        brace_count = 1
        print $0
        next
    }
    print_func == 1 {
        # Count braces to find the end of the function
        for (i = 1; i <= length($0); i++) {
            char = substr($0, i, 1)
            if (char == "{") brace_count++
            if (char == "}") brace_count--
        }
        print $0
        if (brace_count == 0) {
            print_func = 0
            exit 0
        }
    }
    ' "$install_script" >"$temp_func"

    if [ ! -s "$temp_func" ]; then
        log_error "Failed to extract intelligent_config_merge function"
        rm -f "$temp_func"
        return 1
    fi

    log_debug "Function extracted to: $temp_func"

    # Source the extracted function
    . "$temp_func"

    # Clean up
    rm -f "$temp_func"

    log_debug "intelligent_config_merge function loaded successfully"
    return 0
}

# Function to run the merge test
test_config_merge() {
    template_file="$1"
    current_config="$2"
    output_config="$3"

    log_info "=== CONFIGURATION MERGE TEST ==="
    log_info "Template file: $template_file"
    log_info "Current config: $current_config"
    log_info "Output file: $output_config"
    echo

    # Validate input files
    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    if [ ! -f "$current_config" ]; then
        log_error "Current config file not found: $current_config"
        return 1
    fi

    # Show file info
    template_size=$(wc -c <"$template_file" 2>/dev/null || echo "unknown")
    current_size=$(wc -c <"$current_config" 2>/dev/null || echo "unknown")

    log_info "Template file size: $template_size bytes"
    log_info "Current config size: $current_size bytes"

    # Create backup of current config
    backup_file="${current_config}.test.backup.$(date +%Y%m%d_%H%M%S)"
    if cp "$current_config" "$backup_file"; then
        log_info "✓ Created backup: $backup_file"
    else
        log_error "✗ Failed to create backup"
        return 1
    fi

    # Run the merge
    log_info "Running intelligent_config_merge with full debug output..."
    echo "================================="

    if intelligent_config_merge "$template_file" "$current_config" "$output_config"; then
        echo "================================="
        log_info "✓ Configuration merge completed successfully!"
        echo

        # Show results
        log_info "=== MERGE RESULTS ==="
        if [ -f "$output_config" ]; then
            output_size=$(wc -c <"$output_config" 2>/dev/null || echo "unknown")
            log_info "Output file size: $output_size bytes"
            log_info "Output file location: $output_config"

            # Show variable counts
            template_vars=$(grep -c "^export " "$template_file" 2>/dev/null || echo "0")
            current_vars=$(grep -c "^export " "$current_config" 2>/dev/null || echo "0")
            output_vars=$(grep -c "^export " "$output_config" 2>/dev/null || echo "0")

            log_info "Variable counts:"
            log_info "  Template: $template_vars variables"
            log_info "  Current:  $current_vars variables"
            log_info "  Output:   $output_vars variables"

            # Show some key preserved values
            echo
            log_info "=== KEY SETTINGS VERIFICATION ==="

            # Check notification settings
            for var in "PUSHOVER_TOKEN" "PUSHOVER_USER" "NOTIFY_ON_CRITICAL"; do
                if current_val=$(grep "^export $var=" "$current_config" 2>/dev/null); then
                    output_val=$(grep "^export $var=" "$output_config" 2>/dev/null || echo "NOT_FOUND")
                    if [ "$current_val" = "$output_val" ]; then
                        log_info "✓ $var: preserved correctly"
                    else
                        log_error "✗ $var: value changed!"
                        log_error "  Current: $current_val"
                        log_error "  Output:  $output_val"
                    fi
                fi
            done

        else
            log_error "Output file was not created!"
            return 1
        fi

        return 0
    else
        echo "================================="
        log_error "✗ Configuration merge failed!"
        return 1
    fi
}

# Main function
main() {
    log_info "Configuration Merge Test Script v$SCRIPT_VERSION"
    echo

    # Default file paths
    template_file="config/config.template.sh"
    current_config=""
    output_config=""

    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -t | --template)
                template_file="$2"
                shift 2
                ;;
            -c | --current)
                current_config="$2"
                shift 2
                ;;
            -o | --output)
                output_config="$2"
                shift 2
                ;;
            -h | --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -t, --template FILE    Template config file (default: config/config.template.sh)"
                echo "  -c, --current FILE     Current config file (your saved config)"
                echo "  -o, --output FILE      Output merged config file"
                echo "  -h, --help            Show this help"
                echo
                echo "Environment variables:"
                echo "  DEBUG=1               Enable debug output"
                echo "  CONFIG_DEBUG=1        Enable config merge debug output"
                echo
                echo "Example:"
                echo "  $0 -c /path/to/your/saved/config.sh -o /tmp/merged_config.sh"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use -h for help"
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$current_config" ]; then
        log_error "Current config file is required! Use -c to specify it."
        echo "Example: $0 -c /path/to/your/saved/config.sh -o /tmp/merged_config.sh"
        exit 1
    fi

    if [ -z "$output_config" ]; then
        output_config="/tmp/merged_config_$(date +%Y%m%d_%H%M%S).sh"
        log_info "No output file specified, using: $output_config"
    fi

    # Extract the merge function
    if ! extract_merge_function; then
        log_error "Failed to extract merge function"
        exit 1
    fi

    # Run the test
    if test_config_merge "$template_file" "$current_config" "$output_config"; then
        echo
        log_info "=== TEST COMPLETED SUCCESSFULLY ==="
        log_info "Your merged config is available at: $output_config"
        log_info "You can review it and copy it to the appropriate location if satisfied."
        echo
        log_info "To compare with your original:"
        log_info "  diff \"$current_config\" \"$output_config\""
        echo
        log_info "To see what would be preserved in a real installation:"
        log_info "  grep '^export' \"$output_config\" | head -20"

        exit 0
    else
        echo
        log_error "=== TEST FAILED ==="
        exit 1
    fi
}

# Run main function
main "$@"
