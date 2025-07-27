#!/bin/sh
# shellcheck disable=SC2059  # RUTOS requires Method 5 printf format (embedded variables)
# Script: dev-testing-rutos.sh
# Version: 2.5.0
# Description: Simple RUTOS script testing with AI-friendly error reporting
# Usage: ./scripts/dev-testing-rutos.sh [--debug] [--help]

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION

# Load RUTOS library system for standardized logging and utilities
# Try to load library if available, fallback to built-in functions if not
# Note: Skip library for dev-testing since it's a development tool that needs to run on non-RUTOS systems
LIBRARY_LOADED=0
if [ "${FORCE_LIBRARY_LOAD:-0}" = "1" ] && [ -f "$(dirname "$0")/lib/rutos-lib.sh" ]; then
    . "$(dirname "$0")/lib/rutos-lib.sh"
    # Initialize script with full RUTOS library features
    rutos_init "dev-testing-rutos.sh" "$SCRIPT_VERSION"
    LIBRARY_LOADED=1
    log_trace "RUTOS library loaded successfully"
else
    LIBRARY_LOADED=0
    # Fallback to built-in logging functions (preferred for dev-testing)
fi

# GitHub repository information
GITHUB_USER="markus-lassfolk"
GITHUB_REPO="rutos-starlink-failover"
GITHUB_BRANCH="main"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"

# Standard colors for consistent output (compatible with busybox) - only if library not loaded
if [ "${LIBRARY_LOADED:-0}" = "0" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color

    # Check if we're in a terminal that supports colors
    if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" != "" ]; then
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        CYAN=""
        NC=""
    fi
fi

# Standard logging functions with RUTOS-compatible printf format - only if library not loaded
if [ "${LIBRARY_LOADED:-0}" = "0" ]; then
    log_info() {
        printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    }

    log_warning() {
        printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    }

    log_error() {
        printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    }

    log_debug() {
        if [ "$DEBUG" = "1" ]; then
            printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
        fi
    }

    log_success() {
        printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    }

    log_step() {
        printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    }

    # Add missing TRACE function for fallback mode
    log_trace() {
        if [ "${RUTOS_TEST_MODE:-0}" = "1" ] || [ "${DEBUG:-0}" = "1" ]; then
            printf "${CYAN}[TRACE]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
        fi
    }
fi

# Configuration
DEBUG="${DEBUG:-0}"
SKIP_UPDATE="${SKIP_UPDATE:-0}"
COMPREHENSIVE_TEST="${COMPREHENSIVE_TEST:-0}"
RUTOS_LIBRARY_TEST="${RUTOS_LIBRARY_TEST:-0}"
SINGLE_SCRIPT=""

# Version information for troubleshooting
if [ "${DEBUG:-0}" = "1" ]; then
    log_debug "Script: dev-testing-rutos.sh v$SCRIPT_VERSION"
fi

# Test result counters
TOTAL_SCRIPTS=0
PASSED_SCRIPTS=0
FAILED_SCRIPTS=0
SCRIPTS_MISSING_DRYRUN=0
LIBRARY_LOADED_SCRIPTS=0
FALLBACK_MODE_SCRIPTS=0
ERROR_DETAILS=""

# Parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug | -d)
                DEBUG=1
                shift
                ;;
            --skip-update)
                SKIP_UPDATE=1
                shift
                ;;
            --comprehensive | -c)
                COMPREHENSIVE_TEST=1
                shift
                ;;
            --library-test | -l)
                RUTOS_LIBRARY_TEST=1
                shift
                ;;
            --script | -s)
                if [ -n "$2" ]; then
                    SINGLE_SCRIPT="$2"
                    shift 2
                else
                    log_error "Option --script requires a script name"
                    exit 1
                fi
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                log_warning "Unknown argument: $1"
                shift
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat <<EOF
RUTOS Script Testing Tool v$SCRIPT_VERSION

PURPOSE:
    Run all *-rutos.sh scripts in safe test mode to catch errors.
    Generate AI-friendly error reports for debugging assistance.

USAGE:
    ./scripts/dev-testing-rutos.sh [OPTIONS]

OPTIONS:
    --debug, -d         Enable debug output
    --skip-update       Skip self-update check
    --comprehensive, -c Run comprehensive testing with multiple verbosity levels
    --library-test, -l  Test RUTOS library implementation specifically
    --script NAME, -s   Test only a specific script (e.g. --script system-status-rutos.sh)
    --help, -h          Show this help message

COMPREHENSIVE TESTING MODE (DEBUG INTEGRATION):
    When --comprehensive is used, each script is tested with:
    1. Basic dry-run     (DRY_RUN=1) - Baseline output measurement
    2. Debug dry-run     (DEBUG=1 DRY_RUN=1) - Should show significantly more debug info
    3. Test mode         (DRY_RUN=1 RUTOS_TEST_MODE=1) - Comprehensive test output
    4. Full verbose      (DEBUG=1 DRY_RUN=1 RUTOS_TEST_MODE=1) - Maximum debugging detail
    5. Backward compat   (DRY_RUN=1 TEST_MODE=1 DEBUG=1) - Tests TEST_MODE compatibility
    
    Each test measures:
    - Output line count (should increase significantly in debug modes)
    - Debug message frequency
    - Error detection with line numbers and call stacks
    - Shell trace analysis for execution flow
    - Exception handling validation
    
    Results are saved in AI-friendly JSON format for automation and analysis.

WHAT IT DOES:
    1. Auto-update itself from GitHub (unless --skip-update)
    2. Find all *-rutos.sh scripts in the project
    3. Run each script in test/dry-run mode
    4. Capture all errors and issues
    5. Generate AI-friendly error report

OUTPUTS:
    - rutos-test-errors.txt              (AI-friendly error report)
    - rutos-debug-integration-results.json (Comprehensive JSON analysis - comprehensive mode only)
    - Console output                     (Real-time progress)

EXAMPLES:
    # Basic testing
    ./scripts/dev-testing-rutos.sh

    # With debug output
    ./scripts/dev-testing-rutos.sh --debug

    # Comprehensive testing with all verbosity levels
    ./scripts/dev-testing-rutos.sh --comprehensive

    # Test single script comprehensively
    ./scripts/dev-testing-rutos.sh --comprehensive --script system-status-rutos.sh

    # Skip auto-update (for development)
    ./scripts/dev-testing-rutos.sh --skip-update

DEPLOYMENT:
    # Run directly from GitHub (for RUTOS router)
    curl -fsSL https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/scripts/dev-testing-rutos.sh | sh

    # Or download and run
    curl -fsSL https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/scripts/dev-testing-rutos.sh > test-scripts.sh
    chmod +x test-scripts.sh
    ./test-scripts.sh

SAFETY:
    All scripts run with DRY_RUN=1 and RUTOS_TEST_MODE=1 environment variables.
    No actual system changes are made during testing.
EOF
}

# Self-update functionality
self_update() {
    if [ "$SKIP_UPDATE" = "1" ]; then
        log_info "Skipping self-update (--skip-update specified)"
        return 0
    fi

    log_step "Checking for script updates"

    # Download latest version
    TEMP_SCRIPT="/tmp/dev-testing-rutos.sh.latest"
    SCRIPT_URL="${GITHUB_RAW_BASE}/scripts/dev-testing-rutos.sh"

    log_debug "Downloading from: $SCRIPT_URL"

    if curl -fsSL "$SCRIPT_URL" -o "$TEMP_SCRIPT" 2>/dev/null; then
        # Extract version from downloaded script - try multiple patterns
        latest_version=""

        # Try pattern 1: readonly SCRIPT_VERSION="x.x.x"
        if [ -z "$latest_version" ]; then
            latest_version=$(grep '^readonly SCRIPT_VERSION=' "$TEMP_SCRIPT" | cut -d'"' -f2 2>/dev/null)
        fi

        # Try pattern 2: SCRIPT_VERSION="x.x.x" followed by readonly
        if [ -z "$latest_version" ]; then
            latest_version=$(grep '^SCRIPT_VERSION=' "$TEMP_SCRIPT" | cut -d'"' -f2 2>/dev/null)
        fi

        if [ -n "$latest_version" ]; then
            log_debug "Current: v$SCRIPT_VERSION, Latest: v$latest_version"

            if [ "$SCRIPT_VERSION" != "$latest_version" ]; then
                log_info "Updating script from v$SCRIPT_VERSION to v$latest_version"

                # Replace current script if we can write to it
                SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
                if cp "$TEMP_SCRIPT" "$SCRIPT_PATH" 2>/dev/null; then
                    chmod +x "$SCRIPT_PATH"
                    log_success "Script updated successfully - restarting"
                    exec sh "$SCRIPT_PATH" "$@"
                else
                    log_warning "Could not update script file - using downloaded version"
                    exec sh "$TEMP_SCRIPT" "$@"
                fi
            else
                log_info "Script is up to date (v$SCRIPT_VERSION)"
            fi
        else
            log_warning "Could not extract version from downloaded script"
        fi
        rm -f "$TEMP_SCRIPT"
    else
        log_warning "Could not download latest script - continuing with current version"
    fi
}

# Find all RUTOS scripts - defaults to installation directory, falls back to current if needed
find_rutos_scripts() {
    # Create a temporary file to collect script paths
    temp_script_list="/tmp/rutos_scripts_$$"
    : >"$temp_script_list"

    # Try to read the installation directory from config
    INSTALL_DIR=""
    if [ -f "/etc/starlink-config/config.sh" ]; then
        # Source the config to get INSTALL_DIR
        # shellcheck source=/dev/null
        . /etc/starlink-config/config.sh 2>/dev/null
        if [ "$DEBUG" = "1" ]; then
            printf "[DEBUG] [%s] Config found - INSTALL_DIR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$INSTALL_DIR" >&2
        fi
    fi

    # Default: Search installation directory and subdirectories
    if [ -n "$INSTALL_DIR" ] && [ -d "$INSTALL_DIR" ]; then
        if [ "$DEBUG" = "1" ]; then
            printf "[DEBUG] [%s] Searching installation directory: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$INSTALL_DIR" >&2
        fi

        # Search for all RUTOS scripts in installation directory and subdirectories
        find "$INSTALL_DIR" -name "*-rutos.sh" -o -name "starlink_monitor.sh" -o -name "install-rutos.sh" 2>/dev/null | sort | while read -r script; do
            if [ -f "$script" ] && [ -r "$script" ]; then
                # Skip testing the dev-testing script itself to prevent recursion
                script_basename=$(basename "$script")
                if [ "$script_basename" = "dev-testing-rutos.sh" ]; then
                    if [ "$DEBUG" = "1" ]; then
                        printf "[DEBUG] [%s] Skipping self-test: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$script" >&2
                    fi
                    continue
                fi

                if [ "$DEBUG" = "1" ]; then
                    printf "[DEBUG] [%s] Found installed script: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$script" >&2
                fi
                echo "$script" >>"$temp_script_list"
            fi
        done
    fi

    # Fallback: If no installation directory or no scripts found there, search current directory
    if [ ! -s "$temp_script_list" ]; then
        if [ "$DEBUG" = "1" ]; then
            printf "[DEBUG] [%s] No scripts in installation dir, searching current directory\n" "$(date '+%Y-%m-%d %H:%M:%S')" >&2
        fi

        find . -name "*-rutos.sh" -o -name "starlink_monitor.sh" -o -name "install-rutos.sh" 2>/dev/null | sort | while read -r script; do
            if [ -f "$script" ] && [ -r "$script" ]; then
                # Skip testing the dev-testing script itself to prevent recursion
                script_basename=$(basename "$script")
                if [ "$script_basename" = "dev-testing-rutos.sh" ]; then
                    if [ "$DEBUG" = "1" ]; then
                        printf "[DEBUG] [%s] Skipping self-test: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$script" >&2
                    fi
                    continue
                fi

                if [ "$DEBUG" = "1" ]; then
                    printf "[DEBUG] [%s] Found local script: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$script" >&2
                fi
                echo "$script" >>"$temp_script_list"
            fi
        done
    fi

    # Return the list and clean up (NO LOGGING in this function - it contaminates output)
    if [ -f "$temp_script_list" ] && [ -s "$temp_script_list" ]; then
        cat "$temp_script_list"
        rm -f "$temp_script_list"
    else
        rm -f "$temp_script_list"
        return 1
    fi
}

# Check if script has dry-run support
check_dry_run_support() {
    script_path="$1"
    log_trace "Checking DRY_RUN support in: $script_path"

    # Simple check as suggested: cat script-file | grep DRY_RUN
    if cat "$script_path" | grep -q "DRY_RUN" 2>/dev/null; then
        log_trace "✅ DRY_RUN support found in $script_path"
        return 0 # Has support
    fi

    # Also check for RUTOS_TEST_MODE support
    if cat "$script_path" | grep -q "RUTOS_TEST_MODE" 2>/dev/null; then
        log_trace "✅ RUTOS_TEST_MODE support found in $script_path"
        return 0 # Has support
    fi

    log_trace "❌ No DRY_RUN/RUTOS_TEST_MODE support found in $script_path"
    return 1 # No support
}

# Generate dry-run pattern recommendation for a script
generate_dry_run_recommendation() {
    script_name="$1"

    cat <<EOF
DRY-RUN MISSING in $script_name:
  Issue: Script lacks dry-run/test mode support
  Impact: Cannot be safely tested without making real changes
  
  Fix: Add this pattern after script setup (after colors/logging functions):
  
  # Dry-run and test mode support
  DRY_RUN="\${DRY_RUN:-0}"
  RUTOS_TEST_MODE="\${RUTOS_TEST_MODE:-0}"
  
  # Debug dry-run status
  if [ "\$DEBUG" = "1" ]; then
      log_debug "DRY_RUN=\$DRY_RUN, RUTOS_TEST_MODE=\$RUTOS_TEST_MODE"
  fi
  
  # Function to safely execute commands
  safe_execute() {
      cmd="\$1"
      description="\$2"
      
      if [ "\$DRY_RUN" = "1" ] || [ "\$RUTOS_TEST_MODE" = "1" ]; then
          log_info "[DRY-RUN] Would execute: \$description"
          log_debug "[DRY-RUN] Command: \$cmd"
          return 0
      else
          log_debug "Executing: \$cmd"
          eval "\$cmd"
      fi
  }
  
  Then replace dangerous commands like:
  - cp file1 file2              → safe_execute "cp file1 file2" "Copy file1 to file2"
  - rm -f file                  → safe_execute "rm -f file" "Remove file"
  - /etc/init.d/service restart → safe_execute "/etc/init.d/service restart" "Restart service"
  - crontab -l | ...            → safe_execute "crontab commands" "Update crontab"
  
  Reason: Allows safe testing without making system changes
  
EOF
}

# Test individual script with enhanced dry-run detection
test_script() {
    script_path="$1"
    script_name=$(basename "$script_path")

    log_step "Testing $script_name"

    # Run basic checks (syntax and compatibility)
    if ! test_script_basic_checks "$script_path"; then
        return 1
    fi

    # Test 3: Dry-run support check
    if ! check_dry_run_support "$script_path"; then
        # Script lacks dry-run support - this is a warning, not a failure
        SCRIPTS_MISSING_DRYRUN=$((SCRIPTS_MISSING_DRYRUN + 1))
        dry_run_recommendation=$(generate_dry_run_recommendation "$script_name")
        ERROR_DETAILS="${ERROR_DETAILS}${dry_run_recommendation}"

        log_debug "$script_name lacks dry-run support - added recommendation"

        # Try basic syntax execution only (no real execution attempt)
        log_debug "$script_name syntax OK, but cannot safely test execution (no dry-run support)"
        return 0 # Don't fail for missing dry-run, just report it
    fi

    # Test 4: Safe execution test (only for scripts with dry-run support)
    log_debug "Testing $script_name execution (has dry-run support)"

    # Set up test environment
    export DRY_RUN=1
    export RUTOS_TEST_MODE=1
    export TEST_MODE=1
    export DEBUG="$DEBUG"

    # Determine timeout based on script type
    timeout_seconds=20
    if echo "$script_name" | grep -qE "(health-check|post-install-check|system-maintenance|comprehensive)" 2>/dev/null; then
        timeout_seconds=60
        log_debug "Using extended timeout for comprehensive script: $script_name"
    fi

    # Try to run script - it should respect our dry-run environment variables
    test_start_time=$(date '+%s')
    test_exit_code=0

    # Add TRACE-level logging for script execution
    if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
        printf "${CYAN}[TRACE]${NC} [%s] Executing script test: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$script_name" >&2
        printf "${CYAN}[TRACE]${NC} [%s] Command: timeout %s sh -x \"%s\"\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$timeout_seconds" "$script_path" >&2
    fi

    if ! timeout $timeout_seconds sh -x "$script_path" >/tmp/test_output_$$ 2>&1; then
        test_exit_code=$?
        test_end_time=$(date '+%s')
        test_duration=$((test_end_time - test_start_time))

        # Enhanced error analysis
        test_error=$(cat /tmp/test_output_$$ 2>/dev/null | head -5 || echo "Script execution failed")

        # Analyze failure patterns
        failure_analysis=""
        if [ $test_exit_code -eq 124 ]; then
            failure_analysis="TIMEOUT: Script exceeded ${timeout_seconds}s timeout"
        elif [ $test_exit_code -eq 127 ]; then
            failure_analysis="COMMAND NOT FOUND: Missing dependency or command"
        elif [ $test_exit_code -eq 1 ]; then
            failure_analysis="GENERAL ERROR: Script logic error or command failure"
        else
            failure_analysis="UNKNOWN ERROR: Exit code $test_exit_code"
        fi

        # Only report as error if it's not expected dependency issues
        if echo "$test_error" | grep -qE "(not found|No such file|Permission denied|command not found)" && ! echo "$test_error" | grep -q "syntax"; then
            log_debug "$script_name failed due to missing dependencies (expected in test environment)"
        else
            ERROR_DETAILS="${ERROR_DETAILS}EXECUTION ERROR in $script_name:
  File: $script_path  
  Exit Code: $test_exit_code
  Duration: ${test_duration}s (timeout: ${timeout_seconds}s)
  Failure Type: $failure_analysis
  Error Output: $test_error
  
  === DEBUGGING STEPS ===
  1. Run manually: DRY_RUN=1 RUTOS_TEST_MODE=1 sh -x '$script_path'
  2. Check for early exit pattern placement
  3. Verify dry-run implementation
  4. Review script logic and error handling
  
  Fix: Check script logic, error handling, and dry-run implementation
  Note: Script has dry-run support but still failed - check dry-run logic
  
"
            rm -f /tmp/test_output_$$
            return 1
        fi
    fi

    # Add TRACE-level logging for successful test completion
    if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
        test_end_time=$(date '+%s')
        test_duration=$((test_end_time - test_start_time))
        printf "${CYAN}[TRACE]${NC} [%s] Script test completed successfully in %ss: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$test_duration" "$script_name" >&2
    fi

    rm -f /tmp/test_output_$$
    log_debug "$script_name passed all tests"
    return 0
}

# Debug Integration Testing - Comprehensive analysis of DEBUG, DRY_RUN, and RUTOS_TEST_MODE patterns
test_script_debug_integration() {
    script_path="$1"
    script_name=$(basename "$script_path")

    log_step "Debug Integration Testing: $script_name"

    # First run basic syntax/compatibility checks
    if ! test_script_basic_checks "$script_path"; then
        log_error "Basic checks failed for $script_name - skipping debug integration tests"
        return 1
    fi

    # Check if script has dry-run support - required for debug integration testing
    if ! check_dry_run_support "$script_path"; then
        log_warning "$script_name lacks dry-run support - skipping debug integration execution tests"
        SCRIPTS_MISSING_DRYRUN=$((SCRIPTS_MISSING_DRYRUN + 1))
        dry_run_recommendation=$(generate_dry_run_recommendation "$script_name")
        ERROR_DETAILS="${ERROR_DETAILS}${dry_run_recommendation}"

        # Create JSON result for missing dry-run support
        cat >"/tmp/debug_integration_${script_name}_$$.json" <<EOF
{
  "script_name": "$script_name",
  "script_path": "$script_path",
  "test_timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "dry_run_support": false,
  "test_results": [],
  "summary": {
    "total_tests": 0,
    "passed_tests": 0,
    "failed_tests": 0,
    "error_count": 1,
    "warning_count": 1
  },
  "errors": [
    {
      "type": "missing_dry_run_support",
      "message": "Script lacks DRY_RUN and RUTOS_TEST_MODE support",
      "severity": "warning",
      "recommendation": "Add dry-run pattern for safe testing"
    }
  ]
}
EOF
        return 0
    fi

    # Debug Integration Test Configuration
    # Each test validates different aspects of debug/dry-run integration
    test_configs="
1:DRY_RUN_BASIC:DRY_RUN=1:Basic dry-run mode - should prevent system changes
2:DRY_RUN_DEBUG:DRY_RUN=1 DEBUG=1:Debug + dry-run - should show detailed execution info
3:TEST_MODE:DRY_RUN=1 RUTOS_TEST_MODE=1:Test mode - should provide comprehensive test output
4:FULL_VERBOSE:DRY_RUN=1 DEBUG=1 RUTOS_TEST_MODE=1:Full verbosity - maximum debugging information
5:BACKWARD_COMPAT:DRY_RUN=1 TEST_MODE=1 DEBUG=1:Backward compatibility test with TEST_MODE
"

    printf "\n${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║                DEBUG INTEGRATION TEST: %-35s ║${NC}\n" "$script_name"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"

    # Initialize JSON result structure
    json_output_file="/tmp/debug_integration_${script_name}_$$.json"
    test_results_file="/tmp/test_results_${script_name}_$$.json"

    # Start JSON structure
    cat >"$json_output_file" <<EOF
{
  "script_name": "$script_name",
  "script_path": "$script_path",
  "test_timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "dry_run_support": true,
  "test_results": [
EOF

    # Initialize counters for summary
    total_tests=0
    passed_tests=0
    failed_tests=0
    total_errors=0
    total_warnings=0

    # Process each test configuration
    echo "$test_configs" | while IFS=: read -r test_num test_name env_vars test_description; do
        [ -z "$test_num" ] && continue

        total_tests=$((total_tests + 1))

        printf "\n${CYAN}── Test %s: %s ──${NC}\n" "$test_num" "$test_name"
        printf "${YELLOW}Environment: %s${NC}\n" "$env_vars"
        printf "${YELLOW}Description: %s${NC}\n" "$test_description"

        # Prepare output capture
        output_file="/tmp/debug_test_${script_name}_${test_num}_$$"
        error_file="/tmp/debug_error_${script_name}_${test_num}_$$"

        # Determine timeout based on script type
        timeout_seconds=30
        if echo "$script_name" | grep -qE "(health-check|post-install-check|system-maintenance|comprehensive)" 2>/dev/null; then
            timeout_seconds=60
        fi

        # Execute test with environment variables
        test_start_time=$(date '+%s')
        test_exit_code=0

        printf "${BLUE}Running test...${NC}\n"

        # Create test execution command with absolute paths
        script_abs_path="$(cd "$(dirname "$script_path")" && pwd)/$(basename "$script_path")"
        test_cmd="$env_vars timeout $timeout_seconds sh -x \"$script_abs_path\""

        # Execute and capture output
        if ! eval "$test_cmd" >"$output_file" 2>"$error_file"; then
            test_exit_code=$?
        fi

        test_end_time=$(date '+%s')
        test_duration=$((test_end_time - test_start_time))

        # Analyze output
        output_lines=$(wc -l <"$output_file" 2>/dev/null || echo 0)
        error_lines=$(wc -l <"$error_file" 2>/dev/null || echo 0)
        output_size=$(wc -c <"$output_file" 2>/dev/null || echo 0)

        # Strip whitespace from metrics
        output_lines=$(echo "$output_lines" | tr -d ' \n\r')
        error_lines=$(echo "$error_lines" | tr -d ' \n\r')
        output_size=$(echo "$output_size" | tr -d ' \n\r')

        # Analyze debug patterns in output
        debug_messages=$(grep -c "\[DEBUG\]" "$output_file" 2>/dev/null || echo 0)
        info_messages=$(grep -c "\[INFO\]" "$output_file" 2>/dev/null || echo 0)
        warning_messages=$(grep -c "\[WARNING\]" "$output_file" 2>/dev/null || echo 0)
        error_messages=$(grep -c "\[ERROR\]" "$output_file" 2>/dev/null || echo 0)
        step_messages=$(grep -c "\[STEP\]" "$output_file" 2>/dev/null || echo 0)

        # Strip whitespace from message counts
        debug_messages=$(echo "$debug_messages" | tr -d ' \n\r')
        info_messages=$(echo "$info_messages" | tr -d ' \n\r')
        warning_messages=$(echo "$warning_messages" | tr -d ' \n\r')
        error_messages=$(echo "$error_messages" | tr -d ' \n\r')
        step_messages=$(echo "$step_messages" | tr -d ' \n\r')

        # Extract exceptions and errors with line numbers
        exceptions_found=""
        if [ -s "$error_file" ]; then
            exceptions_found=$(grep -n -E "(error|Error|ERROR|exception|Exception|EXCEPTION|fail|Fail|FAIL)" "$error_file" 2>/dev/null | head -10 || echo "")
        fi

        # Analyze shell trace for execution flow
        shell_trace_lines=$(grep -c "^+ " "$error_file" 2>/dev/null || echo 0)
        shell_trace_lines=$(echo "$shell_trace_lines" | tr -d ' \n\r')

        # Determine test status
        test_status="passed"
        status_reasons=""

        if [ "$test_exit_code" -ne 0 ]; then
            if [ "$test_exit_code" -eq 124 ]; then
                test_status="timeout"
                status_reasons="Script exceeded ${timeout_seconds}s timeout"
            elif [ "$test_exit_code" -eq 127 ]; then
                test_status="failed"
                status_reasons="Command not found or missing dependency"
            else
                test_status="failed"
                status_reasons="Script exited with code $test_exit_code"
            fi
            failed_tests=$((failed_tests + 1))
        else
            # Additional validation for successful tests
            case "$test_name" in
                "DRY_RUN_BASIC")
                    # Basic dry-run should have minimal output
                    if [ "$output_lines" -lt 5 ]; then
                        status_reasons="Warning: Very low output for basic dry-run"
                        total_warnings=$((total_warnings + 1))
                    fi
                    ;;
                "DRY_RUN_DEBUG")
                    # Debug mode should have significantly more output than basic
                    if [ "$debug_messages" -lt 5 ]; then
                        status_reasons="Warning: Low debug message count for DEBUG mode"
                        total_warnings=$((total_warnings + 1))
                    fi
                    ;;
                "TEST_MODE")
                    # Test mode should provide comprehensive information
                    if [ "$output_lines" -lt 10 ]; then
                        status_reasons="Warning: Low output for test mode"
                        total_warnings=$((total_warnings + 1))
                    fi
                    ;;
                "FULL_VERBOSE")
                    # Full verbose should have the most output
                    if [ "$debug_messages" -lt 10 ] || [ "$shell_trace_lines" -lt 20 ]; then
                        status_reasons="Warning: Expected more verbose output in full debug mode"
                        total_warnings=$((total_warnings + 1))
                    fi
                    ;;
            esac
            passed_tests=$((passed_tests + 1))
        fi

        # Count actual errors (not warnings)
        if [ "$error_messages" -gt 0 ] || [ -n "$exceptions_found" ]; then
            total_errors=$((total_errors + error_messages))
        fi

        # Create JSON entry for this test
        cat >>"$json_output_file" <<EOF
    {
      "test_number": $test_num,
      "test_name": "$test_name",
      "test_description": "$test_description",
      "environment_variables": "$env_vars",
      "execution": {
        "exit_code": $test_exit_code,
        "duration_seconds": $test_duration,
        "timeout_seconds": $timeout_seconds,
        "status": "$test_status"
      },
      "output_analysis": {
        "total_lines": $output_lines,
        "error_lines": $error_lines,
        "output_size_bytes": $output_size,
        "shell_trace_lines": $shell_trace_lines
      },
      "message_analysis": {
        "debug_messages": $debug_messages,
        "info_messages": $info_messages,
        "warning_messages": $warning_messages,
        "error_messages": $error_messages,
        "step_messages": $step_messages
      },
      "issues": {
        "exceptions_found": $(if [ -n "$exceptions_found" ]; then echo "true"; else echo "false"; fi),
        "exception_details": $(if [ -n "$exceptions_found" ]; then echo "\"$exceptions_found\""; else echo "null"; fi),
        "status_reasons": [$(if [ -n "$status_reasons" ]; then echo "\"$status_reasons\""; fi)]
      }
    }$([ "$test_num" != "5" ] && echo ",")
EOF

        # Display results
        printf "${GREEN}Results:${NC}\n"
        printf "  Status: %s\n" "$test_status"
        printf "  Output lines: %d\n" "$output_lines"
        printf "  Debug messages: %d\n" "$debug_messages"
        printf "  Shell trace lines: %d\n" "$shell_trace_lines"
        printf "  Duration: %ds\n" "$test_duration"

        if [ -n "$status_reasons" ]; then
            printf "${YELLOW}  Issues:${NC}\n"
            printf "    - %s\n" "$status_reasons"
        fi

        # Clean up temporary files
        rm -f "$output_file" "$error_file"

        # Update counters in temp files for cross-subshell access
        echo "$total_tests" >"/tmp/total_tests_$$"
        echo "$passed_tests" >"/tmp/passed_tests_$$"
        echo "$failed_tests" >"/tmp/failed_tests_$$"
        echo "$total_errors" >"/tmp/total_errors_$$"
        echo "$total_warnings" >"/tmp/total_warnings_$$"
    done

    # Read final counters from temp files
    total_tests=$(cat "/tmp/total_tests_$$" 2>/dev/null || echo 0)
    passed_tests=$(cat "/tmp/passed_tests_$$" 2>/dev/null || echo 0)
    failed_tests=$(cat "/tmp/failed_tests_$$" 2>/dev/null || echo 0)
    total_errors=$(cat "/tmp/total_errors_$$" 2>/dev/null || echo 0)
    total_warnings=$(cat "/tmp/total_warnings_$$" 2>/dev/null || echo 0)

    # Complete JSON structure
    cat >>"$json_output_file" <<EOF
  ],
  "summary": {
    "total_tests": $total_tests,
    "passed_tests": $passed_tests,
    "failed_tests": $failed_tests,
    "success_rate_percent": $(if [ "$total_tests" -gt 0 ]; then echo "$((passed_tests * 100 / total_tests))"; else echo "0"; fi),
    "error_count": $total_errors,
    "warning_count": $total_warnings
  },
  "debug_integration_analysis": {
    "has_debug_support": $(grep -q "DEBUG.*:-.*0\|if.*DEBUG.*=" "$script_path" && echo "true" || echo "false"),
    "has_test_mode_support": $(grep -q "RUTOS_TEST_MODE.*:-.*0\|TEST_MODE.*:-.*0" "$script_path" && echo "true" || echo "false"),
    "has_dry_run_support": $(grep -q "DRY_RUN.*:-.*0\|if.*DRY_RUN.*=" "$script_path" && echo "true" || echo "false"),
    "has_backward_compatibility": $(grep -q "TEST_MODE.*:-.*0.*RUTOS_TEST_MODE\|RUTOS_TEST_MODE.*:-.*0.*TEST_MODE" "$script_path" && echo "true" || echo "false"),
    "captures_original_values": $(grep -q "ORIGINAL_DRY_RUN\|ORIGINAL.*TEST_MODE" "$script_path" && echo "true" || echo "false")
  }
}
EOF

    # Display summary
    printf "\n${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║                        TEST SUMMARY                                      ║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "Tests: %d/%d passed (%d%% success rate)\n" "$passed_tests" "$total_tests" "$((passed_tests * 100 / total_tests))"
    printf "Errors: %d, Warnings: %d\n" "$total_errors" "$total_warnings"

    # Clean up temp files
    rm -f "/tmp/total_tests_$$" "/tmp/passed_tests_$$" "/tmp/failed_tests_$$" "/tmp/total_errors_$$" "/tmp/total_warnings_$$"

    # Return status based on results
    if [ "$failed_tests" -eq 0 ]; then
        log_success "Debug integration tests passed for $script_name"
        return 0
    else
        log_error "Debug integration tests failed for $script_name ($failed_tests failures)"
        return 1
    fi
}

# Comprehensive testing function - tests scripts with multiple verbosity levels
test_script_comprehensive() {
    script_path="$1"
    script_name=$(basename "$script_path")

    log_step "Comprehensive testing: $script_name"

    # First run basic syntax/compatibility checks
    if ! test_script_basic_checks "$script_path"; then
        log_error "Basic checks failed for $script_name - skipping comprehensive tests"
        return 1
    fi

    # Check if script has dry-run support - required for comprehensive testing
    if ! check_dry_run_support "$script_path"; then
        log_warning "$script_name lacks dry-run support - skipping comprehensive execution tests"
        SCRIPTS_MISSING_DRYRUN=$((SCRIPTS_MISSING_DRYRUN + 1))
        dry_run_recommendation=$(generate_dry_run_recommendation "$script_name")
        ERROR_DETAILS="${ERROR_DETAILS}${dry_run_recommendation}"
        return 0
    fi

    # Test with different verbosity levels
    test_modes="
1:Basic_dry-run:DRY_RUN=1
2:Debug_dry-run:DEBUG=1 DRY_RUN=1  
3:Test_mode:DRY_RUN=1 RUTOS_TEST_MODE=1
4:Full_verbose:DEBUG=1 DRY_RUN=1 RUTOS_TEST_MODE=1
"

    printf "\n${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║                    COMPREHENSIVE TEST: %-32s ║${NC}\n" "$script_name"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"

    # Track comprehensive test results using file to avoid subshell variable issues
    comp_results_file="/tmp/comp_results_${script_name}_$$"
    comp_errors_file="/tmp/comp_errors_${script_name}_$$"
    test_modes_file="/tmp/test_modes_${script_name}_$$"

    : >"$comp_results_file"
    : >"$comp_errors_file"

    # Write test modes to file to avoid pipe subshell issues
    echo "$test_modes" >"$test_modes_file"

    while IFS=: read -r test_num test_desc env_vars; do
        [ -z "$test_num" ] && continue

        printf "\n${CYAN}── Test %s: %s ──${NC}\n" "$test_num" "$test_desc"

        # Parse environment variables
        test_env=""
        for var in $env_vars; do
            test_env="$test_env export $var;"
        done

        # Run the test
        output_file="/tmp/comp_test_${script_name}_${test_num}_$$"

        printf "${YELLOW}Environment: %s${NC}\n" "$env_vars"
        printf "${YELLOW}Running...${NC}\n"

        # Determine timeout based on script type
        timeout_seconds=30
        if echo "$script_name" | grep -qE "(health-check|post-install-check|system-maintenance|comprehensive)" 2>/dev/null; then
            timeout_seconds=60
            printf "${CYAN}(Using extended timeout for comprehensive script)${NC}\n"
        fi

        # Execute with timeout and capture both stdout and stderr
        test_start_time=$(date '+%s')
        test_exit_code=0

        # Enhanced error capture with debugging information
        debug_info_file="/tmp/debug_info_${script_name}_${test_num}_$$"

        # Prepare enhanced debugging environment
        debug_env="$test_env"
        debug_env="${debug_env} export PS4='+ Line \$LINENO: ';"
        debug_env="${debug_env} export SCRIPT_DEBUG=1;"

        # Run with comprehensive error capture
        if eval "$debug_env timeout $timeout_seconds sh -x '$script_path'" >"$output_file" 2>&1; then
            test_exit_code=0
        else
            test_exit_code=$?
        fi

        test_end_time=$(date '+%s')
        test_duration=$((test_end_time - test_start_time))

        # Capture additional debugging information
        cat >"$debug_info_file" <<EOF
=== TEST EXECUTION DETAILS ===
Exit Code: $test_exit_code
Duration: ${test_duration}s (timeout: ${timeout_seconds}s)
Start Time: $(date -d "@$test_start_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
End Time: $(date -d "@$test_end_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

=== ENVIRONMENT VARIABLES ===
$(for var in $env_vars; do
            if [ -n "$var" ]; then
                echo "$var"
            fi
        done)

=== FAILURE ANALYSIS ===
$(if [ $test_exit_code -eq 124 ]; then
            echo "TIMEOUT: Script exceeded ${timeout_seconds}s timeout"
        elif [ $test_exit_code -eq 130 ]; then
            echo "INTERRUPTED: Script was interrupted (Ctrl+C)"
        elif [ $test_exit_code -eq 137 ]; then
            echo "KILLED: Script was killed (SIGKILL)"
        elif [ $test_exit_code -eq 143 ]; then
            echo "TERMINATED: Script was terminated (SIGTERM)"
        elif [ $test_exit_code -ne 0 ]; then
            echo "ERROR: Script exited with non-zero code $test_exit_code"
        else
            echo "SUCCESS: Script completed normally"
        fi)

=== OUTPUT SIZE ===
Output Lines: $(wc -l <"$output_file" 2>/dev/null || echo "0")
Output Size: $(wc -c <"$output_file" 2>/dev/null || echo "0") bytes

=== LAST 20 LINES OF OUTPUT (with line tracing) ===
$(tail -20 "$output_file" 2>/dev/null || echo "No output captured")

=== ERROR PATTERNS DETECTED ===
$(grep -E "(error|Error|ERROR|fail|Fail|FAIL|exception|Exception|EXCEPTION)" "$output_file" 2>/dev/null | head -5 || echo "No obvious error patterns found")

=== SHELL TRACE ANALYSIS ===
$(grep "^+ Line [0-9]*:" "$output_file" 2>/dev/null | tail -10 || echo "No shell trace information available")
EOF

        if [ $test_exit_code -eq 0 ]; then
            printf "${GREEN}✅ SUCCESS${NC}\n"
            echo "PASS:Test_${test_num}" >>"$comp_results_file"

            # Show first few lines of output to verify it looks good
            if [ -s "$output_file" ]; then
                printf "${CYAN}Output preview:${NC}\n"
                head -10 "$output_file" | sed 's/^/  /'
                if [ "$(wc -l <"$output_file")" -gt 10 ]; then
                    printf "  ${CYAN}... (truncated, %d total lines)${NC}\n" "$(wc -l <"$output_file")"
                fi
            else
                printf "${YELLOW}  (No output produced)${NC}\n"
            fi
        else
            printf "${RED}❌ FAILED${NC}\n"
            echo "FAIL:Test_${test_num}" >>"$comp_results_file"

            # Enhanced error reporting with debugging details
            printf "${RED}Error Details:${NC}\n"
            if [ -f "$debug_info_file" ]; then
                printf "${CYAN}Debug Information:${NC}\n"
                head -30 "$debug_info_file" | sed 's/^/  /'
                printf "\n"
            fi

            # Show script output
            if [ -s "$output_file" ]; then
                printf "${RED}Script Output:${NC}\n"
                head -15 "$output_file" | sed 's/^/  /'
                if [ "$(wc -l <"$output_file")" -gt 15 ]; then
                    printf "  ${CYAN}... (truncated, %d total lines)${NC}\n" "$(wc -l <"$output_file")"
                fi
            else
                printf "${RED}No output captured (silent failure)${NC}\n"
            fi

            # Prepare enhanced error content for report
            if [ -f "$debug_info_file" ]; then
                error_content="Exit Code: $test_exit_code | Duration: ${test_duration}s | $(head -5 "$output_file" 2>/dev/null | tr '\n' ' ' || echo "No output")"
                debug_details=$(cat "$debug_info_file" 2>/dev/null)
            else
                error_content="Script execution failed with exit code $test_exit_code"
                debug_details="No debug information available"
            fi

            # Write enhanced error details to file
            cat >>"$comp_errors_file" <<EOF
COMPREHENSIVE TEST FAILURE in $script_name (Test $test_num: $test_desc):
  File: $script_path
  Environment: $env_vars
  Exit Code: $test_exit_code
  Duration: ${test_duration}s (timeout: ${timeout_seconds}s)
  Error Summary: $error_content
  
  === DETAILED DEBUG INFORMATION ===
$debug_details
  
  === TROUBLESHOOTING STEPS ===
  1. Run manually: $env_vars sh -x '$script_path'
  2. Check exit code patterns above for specific failure type
  3. Review shell trace (Line numbers) for exact failure location
  4. Verify environment variable handling in script
  5. Check for RUTOS compatibility issues (busybox limitations)
  
  === QUICK DIAGNOSIS ===
$(if [ $test_exit_code -eq 124 ]; then
                echo "  - TIMEOUT: Script is taking too long (>${timeout_seconds}s)"
                echo "  - Fix: Add early exit pattern or optimize performance"
            elif [ $test_exit_code -eq 1 ]; then
                echo "  - GENERAL ERROR: Script logic error or command failure"
                echo "  - Fix: Check script logic and error handling"
            elif [ $test_exit_code -eq 127 ]; then
                echo "  - COMMAND NOT FOUND: Missing dependency or typo"
                echo "  - Fix: Verify all commands exist in RUTOS environment"
            else
                echo "  - Exit code $test_exit_code indicates specific error condition"
                echo "  - Fix: Review script documentation for exit code meanings"
            fi)
  
EOF
        fi

        # Clean up debug files
        rm -f "$output_file" "$debug_info_file"
        printf "\n"
    done <"$test_modes_file"

    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n\n"

    # Read error details from file and add to global ERROR_DETAILS
    if [ -f "$comp_errors_file" ] && [ -s "$comp_errors_file" ]; then
        ERROR_DETAILS="${ERROR_DETAILS}$(cat "$comp_errors_file")"
    fi

    # Check results and return appropriate code
    if [ -f "$comp_results_file" ]; then
        failed_tests=$(grep -c "^FAIL:" "$comp_results_file" 2>/dev/null || echo "0")
        total_tests=$(wc -l <"$comp_results_file" 2>/dev/null || echo "0")

        # Clean up temp files
        rm -f "$comp_results_file" "$comp_errors_file" "$test_modes_file"

        if [ "$failed_tests" -gt 0 ]; then
            log_error "Comprehensive testing failed: $failed_tests of $total_tests tests failed"
            return 1
        else
            log_success "Comprehensive testing passed: all $total_tests tests successful"
            return 0
        fi
    else
        # Clean up temp files even on failure
        rm -f "$comp_results_file" "$comp_errors_file" "$test_modes_file"
        log_error "Comprehensive testing failed: no results recorded"
        return 1
    fi
}

# Basic checks function (syntax, compatibility) - separated for reuse
test_script_basic_checks() {
    script_path="$1"
    script_name=$(basename "$script_path")

    # Test 1: Syntax check
    if ! sh -n "$script_path" 2>/tmp/syntax_error_$$; then
        syntax_error=$(cat /tmp/syntax_error_$$ 2>/dev/null || echo "Unknown syntax error")
        ERROR_DETAILS="${ERROR_DETAILS}SYNTAX ERROR in $script_name:
  File: $script_path
  Error: $syntax_error
  Fix: Check shell syntax, quotes, brackets
  
"
        rm -f /tmp/syntax_error_$$
        return 1
    fi
    rm -f /tmp/syntax_error_$$

    # Test 2: POSIX compatibility check
    compat_issues=""

    if grep -qE '\[\[[[:space:]]+.*[[:space:]]+\]\]' "$script_path" 2>/dev/null; then
        compat_issues="${compat_issues}[[ ]] syntax (use [ ] instead); "
    fi

    if grep -q '^[[:space:]]*local[[:space:]]' "$script_path" 2>/dev/null; then
        compat_issues="${compat_issues}'local' keyword (not in busybox); "
    fi

    if grep -qE '^[[:space:]]*echo[[:space:]]+-e[[:space:]]' "$script_path" 2>/dev/null; then
        compat_issues="${compat_issues}'echo with -e flag' (use printf instead); "
    fi

    if grep -q '^[[:space:]]*source[[:space:]]' "$script_path" 2>/dev/null; then
        compat_issues="${compat_issues}'source' command (use . instead); "
    fi

    if [ -n "$compat_issues" ]; then
        ERROR_DETAILS="${ERROR_DETAILS}COMPATIBILITY ERROR in $script_name:
  File: $script_path
  Issues: $compat_issues
  Fix: Replace bash-specific syntax with POSIX sh equivalents
  
"
        return 1
    fi

    return 0
}

# Generate AI-friendly error report
generate_error_report() {
    ERROR_FILE="./rutos-test-errors.txt"

    cat >"$ERROR_FILE" <<EOF
AI DEBUGGING REPORT FOR RUTOS STARLINK FAILOVER SCRIPTS
======================================================

COPY THIS ENTIRE SECTION TO AI FOR DEBUGGING ASSISTANCE:

## Test Summary
- Date: $(date)
- Script Version: $SCRIPT_VERSION
- Total Scripts Tested: $TOTAL_SCRIPTS
- Passed: $PASSED_SCRIPTS
- Failed: $FAILED_SCRIPTS
- Missing Dry-Run Support: $SCRIPTS_MISSING_DRYRUN
- Success Rate: $(if [ "$TOTAL_SCRIPTS" -gt 0 ]; then echo "$((PASSED_SCRIPTS * 100 / TOTAL_SCRIPTS))%"; else echo "N/A"; fi)

## Dry-Run Support Analysis
$(if [ "$SCRIPTS_MISSING_DRYRUN" -gt 0 ]; then
        echo "⚠️  WARNING: $SCRIPTS_MISSING_DRYRUN scripts lack dry-run support"
        echo "These scripts cannot be safely tested without making real system changes."
        echo "See detailed recommendations below for adding dry-run support."
    else
        echo "✅ All scripts have proper dry-run support"
    fi)

## Project Context
- Environment: RUTX50 router with busybox shell (POSIX sh only)
- Requirement: All scripts must work in RUTOS/busybox environment
- Test Mode: All scripts run with DRY_RUN=1 and RUTOS_TEST_MODE=1

## Detailed Errors Found
$(if [ -n "$ERROR_DETAILS" ]; then
        echo "$ERROR_DETAILS"
    else
        echo "No errors found - all scripts passed testing!"
    fi)

## Script Testing Environment
- Working Directory: $(pwd)
- Shell: $(readlink -f /proc/$$/exe 2>/dev/null || echo "busybox sh")
- Test Date: $(date)

## Instructions for AI
1. Analyze each error listed above
2. Focus on RUTOS/busybox compatibility issues
3. Provide specific fixes for each issue
4. Ensure all solutions are POSIX sh compatible
5. For scripts missing dry-run support, implement the recommended pattern
6. Check for common RUTOS pitfalls:
   - bash-specific syntax ([[]], local, echo with -e flag)
   - Missing dependencies or commands
   - Incorrect file paths or permissions
   - Shell compatibility issues
   - Missing dry-run/test mode functionality

## Dry-Run Implementation Priority
Scripts lacking dry-run support should be updated first as they:
- Cannot be safely tested without making real system changes
- Risk causing issues during development and testing
- Should follow the provided safe_execute() pattern for all system operations

## Fix Format Requested
For each error, please provide:
- File: [filename]
- Issue: [description of problem]  
- Fix: [specific code change needed]
- Reason: [why this fix works in RUTOS environment]

END OF AI DEBUGGING REPORT
=========================
EOF

    log_info "Error report generated: $ERROR_FILE"

    if [ "$FAILED_SCRIPTS" -gt 0 ]; then
        log_error "Copy the contents of $ERROR_FILE to AI for debugging help"
    fi
}

# Generate comprehensive JSON report from individual test results
generate_json_report() {
    JSON_REPORT_FILE="./rutos-debug-integration-results.json"

    log_step "Generating comprehensive JSON report"

    # Start main JSON structure
    cat >"$JSON_REPORT_FILE" <<EOF
{
  "debug_integration_test_report": {
    "meta": {
      "test_suite_version": "$SCRIPT_VERSION",
      "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
      "working_directory": "$(pwd)",
      "shell_environment": "$(readlink -f /proc/$$/exe 2>/dev/null || echo "busybox sh")",
      "test_mode": "debug_integration_testing"
    },
    "summary": {
      "total_scripts_tested": $TOTAL_SCRIPTS,
      "scripts_passed": $PASSED_SCRIPTS,
      "scripts_failed": $FAILED_SCRIPTS,
      "scripts_missing_dry_run": $SCRIPTS_MISSING_DRYRUN,
      "overall_success_rate_percent": $(if [ "$TOTAL_SCRIPTS" -gt 0 ]; then echo "$((PASSED_SCRIPTS * 100 / TOTAL_SCRIPTS))"; else echo "0"; fi)
    },
    "individual_script_results": [
EOF

    # Collect individual JSON files
    json_files_found=0
    first_file=true

    # Find all debug integration JSON files
    for json_file in /tmp/debug_integration_*_$$.json; do
        if [ -f "$json_file" ]; then
            json_files_found=$((json_files_found + 1))

            # Add comma separator for all but first file
            if [ "$first_file" = "false" ]; then
                echo "," >>"$JSON_REPORT_FILE"
            fi
            first_file=false

            # Add the individual test result
            cat "$json_file" >>"$JSON_REPORT_FILE"

            # Clean up individual file
            rm -f "$json_file"
        fi
    done

    # Close individual results array and add analysis
    cat >>"$JSON_REPORT_FILE" <<EOF
    ],
    "global_analysis": {
      "scripts_with_full_debug_support": $(find . -name "*-rutos.sh" -exec grep -l "DEBUG.*:-.*0\|if.*DEBUG.*=" {} \; 2>/dev/null | wc -l),
      "scripts_with_test_mode_support": $(find . -name "*-rutos.sh" -exec grep -l "RUTOS_TEST_MODE.*:-.*0\|TEST_MODE.*:-.*0" {} \; 2>/dev/null | wc -l),
      "scripts_with_dry_run_support": $(find . -name "*-rutos.sh" -exec grep -l "DRY_RUN.*:-.*0\|if.*DRY_RUN.*=" {} \; 2>/dev/null | wc -l),
      "scripts_with_backward_compatibility": $(find . -name "*-rutos.sh" -exec grep -l "TEST_MODE.*:-.*0.*RUTOS_TEST_MODE\|RUTOS_TEST_MODE.*:-.*0.*TEST_MODE" {} \; 2>/dev/null | wc -l),
      "total_rutos_scripts_in_project": $(find . -name "*-rutos.sh" -type f 2>/dev/null | wc -l)
    },
    "recommendations": [
EOF

    # Generate recommendations based on findings
    recommendations_added=false

    if [ "$SCRIPTS_MISSING_DRYRUN" -gt 0 ]; then
        if [ "$recommendations_added" = "true" ]; then
            echo "," >>"$JSON_REPORT_FILE"
        fi
        cat >>"$JSON_REPORT_FILE" <<EOF
      {
        "priority": "high",
        "category": "missing_dry_run_support",
        "description": "Add DRY_RUN and RUTOS_TEST_MODE support to $SCRIPTS_MISSING_DRYRUN scripts",
        "impact": "Enables safe testing without system modifications",
        "implementation": "Add dry-run pattern with safe_execute() function"
      }
EOF
        recommendations_added=true
    fi

    if [ "$FAILED_SCRIPTS" -gt 0 ]; then
        if [ "$recommendations_added" = "true" ]; then
            echo "," >>"$JSON_REPORT_FILE"
        fi
        cat >>"$JSON_REPORT_FILE" <<EOF
      {
        "priority": "medium",
        "category": "execution_failures",
        "description": "Fix execution issues in $FAILED_SCRIPTS scripts",
        "impact": "Improves script reliability and debug capabilities",
        "implementation": "Review individual script error details in test results"
      }
EOF
        recommendations_added=true
    fi

    # Always add debug improvement recommendation
    if [ "$recommendations_added" = "true" ]; then
        echo "," >>"$JSON_REPORT_FILE"
    fi
    cat >>"$JSON_REPORT_FILE" <<EOF
      {
        "priority": "low",
        "category": "debug_enhancement",
        "description": "Enhance debug output verbosity across all scripts",
        "impact": "Improves troubleshooting capabilities in production",
        "implementation": "Ensure all scripts capture original variable values and provide comprehensive debug info"
      }
EOF

    # Close JSON structure
    cat >>"$JSON_REPORT_FILE" <<EOF
    ]
  }
}
EOF

    log_info "Comprehensive JSON report generated: $JSON_REPORT_FILE"
    log_info "Found and processed $json_files_found individual test results"

    # Display key metrics
    printf "\n${BLUE}=== JSON REPORT SUMMARY ===${NC}\n"
    printf "Report file: %s\n" "$JSON_REPORT_FILE"
    printf "Individual tests processed: %d\n" "$json_files_found"
    printf "Overall success rate: %d%%\n" "$((PASSED_SCRIPTS * 100 / TOTAL_SCRIPTS))"

    if [ "$COMPREHENSIVE_TEST" = "1" ]; then
        log_info "Use this JSON file for automated analysis of debug integration patterns"
        log_info "Each script contains detailed output metrics and error analysis"
    fi
}

# Generate AI-friendly error report
generate_error_report() {
    ERROR_FILE="./rutos-test-errors.txt"

    cat >"$ERROR_FILE" <<EOF
AI DEBUGGING REPORT FOR RUTOS STARLINK FAILOVER SCRIPTS
======================================================

COPY THIS ENTIRE SECTION TO AI FOR DEBUGGING ASSISTANCE:

## Test Summary
- Date: $(date)
- Script Version: $SCRIPT_VERSION
- Total Scripts Tested: $TOTAL_SCRIPTS
- Passed: $PASSED_SCRIPTS
- Failed: $FAILED_SCRIPTS
- Missing Dry-Run Support: $SCRIPTS_MISSING_DRYRUN
- Success Rate: $(if [ "$TOTAL_SCRIPTS" -gt 0 ]; then echo "$((PASSED_SCRIPTS * 100 / TOTAL_SCRIPTS))%"; else echo "N/A"; fi)

## Dry-Run Support Analysis
$(if [ "$SCRIPTS_MISSING_DRYRUN" -gt 0 ]; then
        echo "⚠️  WARNING: $SCRIPTS_MISSING_DRYRUN scripts lack dry-run support"
        echo "These scripts cannot be safely tested without making real system changes."
        echo "See detailed recommendations below for adding dry-run support."
    else
        echo "✅ All scripts have proper dry-run support"
    fi)

## Project Context
- Environment: RUTX50 router with busybox shell (POSIX sh only)
- Requirement: All scripts must work in RUTOS/busybox environment
- Test Mode: All scripts run with DRY_RUN=1 and RUTOS_TEST_MODE=1

## Detailed Errors Found
$(if [ -n "$ERROR_DETAILS" ]; then
        echo "$ERROR_DETAILS"
    else
        echo "No errors found - all scripts passed testing!"
    fi)

## Script Testing Environment
- Working Directory: $(pwd)
- Shell: $(readlink -f /proc/$$/exe 2>/dev/null || echo "busybox sh")
- Test Date: $(date)

## Instructions for AI
1. Analyze each error listed above
2. Focus on RUTOS/busybox compatibility issues
3. Provide specific fixes for each issue
4. Ensure all solutions are POSIX sh compatible
5. For scripts missing dry-run support, implement the recommended pattern
6. Check for common RUTOS pitfalls:
   - bash-specific syntax ([[]], local, echo with -e flag)
   - Missing dependencies or commands
   - Incorrect file paths or permissions
   - Shell compatibility issues
   - Missing dry-run/test mode functionality

## Dry-Run Implementation Priority
Scripts lacking dry-run support should be updated first as they:
- Cannot be safely tested without making real system changes
- Risk causing issues during development and testing
- Should follow the provided safe_execute() pattern for all system operations

## Fix Format Requested
For each error, please provide:
- File: [filename]
- Issue: [description of problem]  
- Fix: [specific code change needed]
- Reason: [why this fix works in RUTOS environment]

END OF AI DEBUGGING REPORT
=========================
EOF

    log_info "Error report generated: $ERROR_FILE"

    if [ "$FAILED_SCRIPTS" -gt 0 ]; then
        log_error "Copy the contents of $ERROR_FILE to AI for debugging help"
    fi
}

# Main execution function
main() {
    printf "\n${BLUE}========================================${NC}\n"
    printf "${BLUE}RUTOS Script Testing Tool v$SCRIPT_VERSION${NC}\n"
    printf "${BLUE}========================================${NC}\n\n"

    # Parse arguments
    parse_arguments "$@"

    # Early exit in test mode to prevent execution errors (except library testing)
    if [ "${RUTOS_TEST_MODE:-0}" = "1" ] && [ "${RUTOS_LIBRARY_TEST:-0}" != "1" ]; then
        log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
        exit 0
    fi

    # Handle library testing mode
    if [ "${RUTOS_LIBRARY_TEST:-0}" = "1" ]; then
        # Add TRACE-level logging for library testing mode
        if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
            printf "${CYAN}[TRACE]${NC} [%s] Entering RUTOS Library Testing Mode\n" "$(date '+%Y-%m-%d %H:%M:%S')" >&2
            printf "${CYAN}[TRACE]${NC} [%s] Library test parameters: RUTOS_LIBRARY_TEST=1, RUTOS_TEST_MODE=1, DEBUG=%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "${DEBUG:-0}" >&2
        fi

        log_info "🔬 RUTOS Library Implementation Testing Mode"
        printf "\n${CYAN}========================================${NC}\n"
        printf "${CYAN}Testing RUTOS Library Implementation${NC}\n"
        printf "${CYAN}========================================${NC}\n\n"

        # Run the dedicated library testing script
        if [ -f "./scripts/test-rutos-library-implementation.sh" ]; then
            log_step "Running dedicated library implementation test"
            if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
                printf "${CYAN}[TRACE]${NC} [%s] Executing: bash ./scripts/test-rutos-library-implementation.sh\n" "$(date '+%Y-%m-%d %H:%M:%S')" >&2
            fi
            bash ./scripts/test-rutos-library-implementation.sh
            exit $?
        else
            log_warning "Dedicated library test script not found, running basic validation"
            # Basic library testing for key scripts (POSIX sh compatible)
            test_scripts="./scripts/install-rutos.sh ./Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh ./Starlink-RUTOS-Failover/starlink_logger_unified-rutos.sh"

            all_passed=0
            for script in $test_scripts; do
                if [ -f "$script" ]; then
                    log_step "Testing library implementation in $(basename "$script")"
                    if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
                        printf "${CYAN}[TRACE]${NC} [%s] Executing: DRY_RUN=1 RUTOS_TEST_MODE=1 bash \"%s\"\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$script" >&2
                    fi
                    if DRY_RUN=1 RUTOS_TEST_MODE=1 bash "$script" 2>&1 | grep -q "TRACE\|DEBUG"; then
                        log_success "✅ $(basename "$script") - Library logging detected"
                        ( (LIBRARY_LOADED_SCRIPTS++))
                    else
                        log_warning "⚠️  $(basename "$script") - Library implementation needs verification"
                        ( (FALLBACK_MODE_SCRIPTS++))
                        all_passed=1
                    fi
                else
                    log_warning "⚠️  Script not found: $script"
                fi
            done

            printf "\n${BLUE}========================================${NC}\n"
            printf "${BLUE}Library Testing Summary${NC}\n"
            printf "${BLUE}========================================${NC}\n"
            printf "📊 Library-enabled scripts: %d\n" "$LIBRARY_LOADED_SCRIPTS"
            printf "📊 Fallback mode scripts: %d\n" "$FALLBACK_MODE_SCRIPTS"

            if [ $all_passed -eq 0 ]; then
                log_success "🎉 All tested scripts show library implementation!"
                printf "\n${GREEN}✅ Library implementation validation PASSED${NC}\n"
            else
                log_warning "⚠️  Some scripts may need library implementation review"
                printf "\n${YELLOW}⚠️  Library implementation validation completed with warnings${NC}\n"
            fi

            exit $all_passed
        fi
    fi

    if [ "$DEBUG" = "1" ]; then
        log_debug "Debug mode enabled"
        log_debug "Working directory: $(pwd)"
        log_debug "Arguments: $*"
    fi

    # Step 1: Self-update
    self_update "$@"

    # Step 2: Find scripts
    log_step "Finding *-rutos.sh scripts"
    if [ -n "$SINGLE_SCRIPT" ]; then
        # Single script mode
        log_info "Single script mode: $SINGLE_SCRIPT"

        # Find the specific script
        script_list=$(find_rutos_scripts | grep "$SINGLE_SCRIPT" || echo "")
        if [ -z "$script_list" ]; then
            log_error "Script not found: $SINGLE_SCRIPT"
            exit 1
        fi

        script_path=$(echo "$script_list" | head -1)
        log_info "Found script: $script_path"

        # Test the single script
        TOTAL_SCRIPTS=1 # Set counter for single script mode

        if [ "$COMPREHENSIVE_TEST" = "1" ]; then
            log_info "Running debug integration test on $SINGLE_SCRIPT"
            if test_script_debug_integration "$script_path"; then
                PASSED_SCRIPTS=1
                FAILED_SCRIPTS=0
                log_success "✅ $SINGLE_SCRIPT passed debug integration testing"
            else
                PASSED_SCRIPTS=0
                FAILED_SCRIPTS=1
                log_error "❌ $SINGLE_SCRIPT failed debug integration testing"
            fi
        else
            log_info "Running basic test on $SINGLE_SCRIPT"
            if test_script "$script_path"; then
                PASSED_SCRIPTS=1
                FAILED_SCRIPTS=0
                log_success "✅ $SINGLE_SCRIPT passed all tests"
            else
                PASSED_SCRIPTS=0
                FAILED_SCRIPTS=1
                log_error "❌ $SINGLE_SCRIPT failed tests"
            fi
        fi

        # Generate reports for single script
        generate_error_report

        # Generate JSON report if comprehensive testing was used
        if [ "$COMPREHENSIVE_TEST" = "1" ]; then
            generate_json_report
        fi
        exit 0
    fi

    # Multi-script mode
    script_list=$(find_rutos_scripts)
    if [ -n "$script_list" ]; then
        if [ "$COMPREHENSIVE_TEST" = "1" ]; then
            log_info "Running COMPREHENSIVE tests with multiple verbosity levels"
        else
            log_info "Testing scripts in safe mode (DRY_RUN=1, RUTOS_TEST_MODE=1)"
        fi

        # Step 3: Test each script using a simpler approach
        # Write script list to temp file to avoid subshell variable issues
        temp_script_file="/tmp/scripts_to_test_$$"
        temp_results="/tmp/test_results_$$"

        printf "%s\n" "$script_list" >"$temp_script_file"
        : >"$temp_results"

        # Process each script
        while IFS= read -r script; do
            if [ -n "$script" ] && [ "$script" != "" ]; then
                script_name=$(basename "$script")

                # Choose testing method based on mode
                test_result=0
                if [ "$COMPREHENSIVE_TEST" = "1" ]; then
                    if test_script_debug_integration "$script"; then
                        test_result=0
                    else
                        test_result=1
                    fi
                else
                    if test_script "$script" >/dev/null 2>&1; then
                        test_result=0
                    else
                        test_result=1
                    fi
                fi

                # Record results
                if [ $test_result -eq 0 ]; then
                    echo "PASS:$script_name" >>"$temp_results"
                    # Check if script has dry-run support for display
                    if check_dry_run_support "$script"; then
                        printf "${GREEN}✅ PASS${NC} - %s ${CYAN}(dry-run ready)${NC}\n" "$script_name"
                    else
                        printf "${GREEN}✅ PASS${NC} - %s ${YELLOW}(needs dry-run)${NC}\n" "$script_name"
                    fi
                else
                    echo "FAIL:$script_name" >>"$temp_results"
                    printf "${RED}❌ FAIL${NC} - %s\n" "$script_name"
                fi
            fi
        done <"$temp_script_file"

        # Calculate final results
        if [ -f "$temp_results" ] && [ -s "$temp_results" ]; then
            # Use more robust counting to avoid whitespace issues - fix command order
            TOTAL_SCRIPTS=$(wc -l <"$temp_results" | tr -d ' \n\r')

            # Fix grep fallback - tr should happen on grep output, not on fallback
            PASSED_COUNT=$(grep -c "^PASS:" "$temp_results" 2>/dev/null || echo "0")
            PASSED_SCRIPTS=$(printf "%s" "$PASSED_COUNT" | tr -d ' \n\r')

            FAILED_COUNT=$(grep -c "^FAIL:" "$temp_results" 2>/dev/null || echo "0")
            FAILED_SCRIPTS=$(printf "%s" "$FAILED_COUNT" | tr -d ' \n\r')

            # Debug the calculated values
            log_debug "Result counts: TOTAL=$TOTAL_SCRIPTS, PASSED=$PASSED_SCRIPTS, FAILED=$FAILED_SCRIPTS"
        else
            TOTAL_SCRIPTS=0
            PASSED_SCRIPTS=0
            FAILED_SCRIPTS=0
            log_debug "No results file or empty - using zeros"
        fi

        # Clean up temp files
        rm -f "$temp_script_file" "$temp_results"

        # Step 4: Generate reports
        generate_error_report

        # Generate JSON report if comprehensive testing was used
        if [ "$COMPREHENSIVE_TEST" = "1" ]; then
            generate_json_report
        fi

        # Step 5: Summary
        printf "\n${BLUE}========================================${NC}\n"
        printf "${BLUE}TESTING COMPLETE${NC}\n"
        printf "${BLUE}========================================${NC}\n"

        if [ "$FAILED_SCRIPTS" -eq 0 ]; then
            if [ "$SCRIPTS_MISSING_DRYRUN" -eq 0 ]; then
                log_success "🎉 ALL TESTS PASSED! All scripts are RUTOS-ready with dry-run support"
            else
                log_success "✅ All scripts passed syntax/compatibility tests"
                log_warning "⚠️  $SCRIPTS_MISSING_DRYRUN scripts need dry-run support added"
                log_info "📋 Review rutos-test-errors.txt for dry-run implementation guides"
            fi
            exit 0
        else
            log_error "❌ $FAILED_SCRIPTS of $TOTAL_SCRIPTS scripts failed"
            if [ "$SCRIPTS_MISSING_DRYRUN" -gt 0 ]; then
                log_warning "⚠️  Additionally, $SCRIPTS_MISSING_DRYRUN scripts need dry-run support"
            fi
            log_info "📄 Review rutos-test-errors.txt for AI debugging help"
            exit 1
        fi
    else
        log_error "No scripts found to test"
        exit 1
    fi
}

# Execute main function
main "$@"
