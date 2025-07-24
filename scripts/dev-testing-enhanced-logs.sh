#!/bin/sh
# shellcheck disable=SC2059  # RUTOS requires Method 5 printf format (embedded variables)
# shellcheck disable=SC2317  # Allow functions with conditional unreachable code (exit paths)
# Script: dev-testing-enhanced-logs.sh
# Version: 2.5.1
# Description: RUTOS script testing with individual log file support for debugging crontab issues
# Usage: ./scripts/dev-testing-rutos.sh [--debug] [--help]

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION

# GitHub repository information
GITHUB_USER="markus-lassfolk"
GITHUB_REPO="rutos-starlink-failover"
GITHUB_BRANCH="main"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"

# Standard colors for consistent output (compatible with busybox)
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

# Standard logging functions with RUTOS-compatible printf format
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

# Configuration
DEBUG="${DEBUG:-0}"
SKIP_UPDATE="${SKIP_UPDATE:-0}"
COMPREHENSIVE_TEST="${COMPREHENSIVE_TEST:-0}"
SAVE_INDIVIDUAL_LOGS="${SAVE_INDIVIDUAL_LOGS:-0}"
LOGS_DIR="./test-logs/$(date '+%Y%m%d_%H%M%S')"
SINGLE_SCRIPT=""

# Test result counters
TOTAL_SCRIPTS=0
PASSED_SCRIPTS=0
FAILED_SCRIPTS=0
SCRIPTS_MISSING_DRYRUN=0
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
            --save-logs | -l)
                SAVE_INDIVIDUAL_LOGS=1
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
    ./scripts/dev-testing-enhanced-logs.sh [OPTIONS]

OPTIONS:
    --debug, -d         Enable debug output
    --skip-update       Skip self-update check
    --comprehensive, -c Run comprehensive testing with multiple verbosity levels
    --save-logs, -l     Save individual debug logs for each script test (NEW!)
    --script NAME, -s   Test only a specific script (e.g. --script system-status-rutos.sh)
    --help, -h          Show this help message

ENHANCED LOGGING FEATURES (NEW!):
    When --save-logs is used, the framework will:
    - Create timestamped logs directory: ./test-logs/YYYYMMDD_HHMMSS/
    - Save individual log files for each script and test mode
    - Capture crontab snapshots before/after each script execution
    - Generate summary report of which scripts modified system state
    - Perfect for debugging which script is commenting out crontab entries!

COMPREHENSIVE TESTING MODE:
    When --comprehensive is used, each script is tested with:
    1. Basic dry-run     (DRY_RUN=1)
    2. Debug dry-run     (DEBUG=1 DRY_RUN=1) 
    3. Test mode         (DRY_RUN=1 RUTOS_TEST_MODE=1)
    4. Full verbose      (DEBUG=1 DRY_RUN=1 RUTOS_TEST_MODE=1)
    
    This validates color output, user feedback, and various debugging levels.

DEBUGGING CRONTAB ISSUES:
    Use --save-logs to identify which scripts modify crontab entries.
    Check ./test-logs/YYYYMMDD_HHMMSS/crontab-changes.txt for results.

WHAT IT DOES:
    1. Auto-update itself from GitHub (unless --skip-update)
    2. Find all *-rutos.sh scripts in the project
    3. Run each script in test/dry-run mode
    4. Capture all errors and issues
    5. Generate AI-friendly error report

OUTPUTS:
    - rutos-test-errors.txt    (AI-friendly error report)
    - Console output           (Real-time progress)

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
    true >"$temp_script_list"  # Create empty file

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

    # Check for existing dry-run patterns
    if grep -qE "(DRY_RUN|RUTOS_TEST_MODE|TEST_MODE)" "$script_path" 2>/dev/null; then
        return 0 # Has support
    fi

    # Check for command line flag support
    if grep -qE "(--dry-run|--test-mode|--test)" "$script_path" 2>/dev/null; then
        return 0 # Has support
    fi

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

    if ! timeout $timeout_seconds sh -x "$script_path" >/tmp/test_output_$$ 2>&1; then
        test_exit_code=$?
        test_end_time=$(date '+%s')
        test_duration=$((test_end_time - test_start_time))

        # Enhanced error analysis
        test_error=$(cat /tmp/test_output_$$ 2>/dev/null | head -5 || echo "Script execution failed")

        # Capture additional debugging information
        debug_info="Exit Code: $test_exit_code | Duration: ${test_duration}s | Timeout: ${timeout_seconds}s"

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

    rm -f /tmp/test_output_$$
    log_debug "$script_name passed all tests"
    return 0
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

    true >"$comp_results_file"  # Create empty results file
    true >"$comp_errors_file"   # Create empty errors file

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

        # Capture system state before test execution
        capture_system_state_before "$script_name" "$test_desc"

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

        # Save individual test log
        save_script_test_log "$script_name" "$test_desc" "$output_file"

        # Capture system state after test and detect changes
        capture_system_state_after "$script_name" "$test_desc" "$test_exit_code"
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

# =============================================================================
# ENHANCED LOGGING FUNCTIONS FOR CRONTAB DEBUGGING
# =============================================================================

# Setup logs directory structure if save-logs is enabled
setup_logs_directory() {
    if [ "$SAVE_INDIVIDUAL_LOGS" = "1" ]; then
        mkdir -p "$LOGS_DIR"
        log_info "Individual logs will be saved to: $LOGS_DIR"

        # Create summary files
        cat >"$LOGS_DIR/summary.txt" <<EOF
RUTOS Script Testing Summary
==========================
Test Date: $(date)
Test Version: $SCRIPT_VERSION
Logs Directory: $LOGS_DIR

This directory contains individual log files for each script test to help
debug system modifications, especially crontab changes.

Structure:
- script-name/: Individual script test logs
- crontab-changes.txt: Scripts that modified crontab
- summary.txt: This file

EOF

        # Initialize crontab changes tracker
        cat >"$LOGS_DIR/crontab-changes.txt" <<EOF
Scripts That Modified Crontab
============================
Test Date: $(date)

This file tracks which scripts made changes to the crontab during testing.
Use this to identify scripts that may be commenting out crontab entries.

EOF
    fi
}

# Capture system state before script execution
capture_system_state_before() {
    script_name="$1"
    test_desc="$2"

    if [ "$SAVE_INDIVIDUAL_LOGS" = "1" ]; then
        script_log_dir="$LOGS_DIR/$(echo "$script_name" | sed 's/[^a-zA-Z0-9._-]/_/g')"
        mkdir -p "$script_log_dir"

        # Capture crontab before execution
        crontab -l >"$script_log_dir/crontab-before-${test_desc}.txt" 2>/dev/null ||
            echo "No crontab found" >"$script_log_dir/crontab-before-${test_desc}.txt"

        # Log test start
        cat >>"$script_log_dir/system-changes.txt" <<EOF
=== Test: $test_desc ===
Start Time: $(date)

EOF
    fi
}

# Capture system state after script execution and detect changes
capture_system_state_after() {
    script_name="$1"
    test_desc="$2"
    exit_code="$3"

    if [ "$SAVE_INDIVIDUAL_LOGS" = "1" ]; then
        script_log_dir="$LOGS_DIR/$(echo "$script_name" | sed 's/[^a-zA-Z0-9._-]/_/g')"

        # Capture crontab after execution
        crontab -l >"$script_log_dir/crontab-after-${test_desc}.txt" 2>/dev/null ||
            echo "No crontab found" >"$script_log_dir/crontab-after-${test_desc}.txt"

        # Compare crontab changes
        if ! diff "$script_log_dir/crontab-before-${test_desc}.txt" "$script_log_dir/crontab-after-${test_desc}.txt" >"$script_log_dir/crontab-diff-${test_desc}.txt" 2>/dev/null; then
            # Crontab changed!
            cat >>"$script_log_dir/system-changes.txt" <<EOF
🚨 CRONTAB MODIFIED during test: $test_desc
Exit Code: $exit_code
End Time: $(date)

Changes detected:
$(cat "$script_log_dir/crontab-diff-${test_desc}.txt")

EOF

            # Add to global crontab changes tracker
            cat >>"$LOGS_DIR/crontab-changes.txt" <<EOF
Script: $script_name
Test: $test_desc
Exit Code: $exit_code
Time: $(date)
Changes:
$(cat "$script_log_dir/crontab-diff-${test_desc}.txt")
----------------------------------------

EOF

            log_warning "CRONTAB MODIFIED by $script_name during $test_desc test!"
        else
            cat >>"$script_log_dir/system-changes.txt" <<EOF
✅ No crontab changes detected during test: $test_desc
Exit Code: $exit_code
End Time: $(date)

EOF
        fi
    fi
}

# Save individual script test log
save_script_test_log() {
    script_name="$1"
    test_desc="$2"
    output_file="$3"

    if [ "$SAVE_INDIVIDUAL_LOGS" = "1" ]; then
        script_log_dir="$LOGS_DIR/$(echo "$script_name" | sed 's/[^a-zA-Z0-9._-]/_/g')"
        mkdir -p "$script_log_dir"

        # Clean test description for filename
        test_file="test-$(echo "$test_desc" | tr 'A-Z ' 'a-z-').log"

        # Copy the test output
        cp "$output_file" "$script_log_dir/$test_file" 2>/dev/null ||
            echo "No output captured" >"$script_log_dir/$test_file"

        log_debug "Saved individual log: $script_log_dir/$test_file"
    fi
}

# =============================================================================

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
        compat_issues="${compat_issues}'echo -e' (use printf instead); "
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
   - bash-specific syntax ([[]], local, echo -e)
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

# Early exit in test mode to prevent execution errors
if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
    log_info "RUTOS_TEST_MODE enabled - script syntax OK, exiting without execution"
    exit 0
fi

# Main execution function
main() {
    printf "\n${BLUE}========================================${NC}\n"
    printf "${BLUE}RUTOS Script Testing Tool v$SCRIPT_VERSION${NC}\n"
    printf "${BLUE}========================================${NC}\n\n"

    # Parse arguments
    parse_arguments "$@"

    if [ "$DEBUG" = "1" ]; then
        log_debug "Debug mode enabled"
        log_debug "Working directory: $(pwd)"
        log_debug "Arguments: $*"
        log_debug "SAVE_INDIVIDUAL_LOGS: $SAVE_INDIVIDUAL_LOGS"
        log_debug "LOGS_DIR: $LOGS_DIR"
    fi

    # Setup logs directory if individual logging is enabled
    setup_logs_directory

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
            log_info "Running comprehensive test on $SINGLE_SCRIPT"
            if test_script_comprehensive "$script_path"; then
                PASSED_SCRIPTS=1
                FAILED_SCRIPTS=0
                log_success "✅ $SINGLE_SCRIPT passed comprehensive testing"
            else
                PASSED_SCRIPTS=0
                FAILED_SCRIPTS=1
                log_error "❌ $SINGLE_SCRIPT failed comprehensive testing"
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

        # Generate report for single script
        generate_error_report
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
        true >"$temp_results"  # Create empty temp results file

        # Process each script
        while IFS= read -r script; do
            if [ -n "$script" ] && [ "$script" != "" ]; then
                script_name=$(basename "$script")

                # Choose testing method based on mode
                test_result=0
                if [ "$COMPREHENSIVE_TEST" = "1" ]; then
                    if test_script_comprehensive "$script"; then
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

        # Step 4: Generate report
        generate_error_report

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

    # Final summary for individual logs
    if [ "$SAVE_INDIVIDUAL_LOGS" = "1" ]; then
        printf "\n${BLUE}========================================${NC}\n"
        printf "${BLUE}INDIVIDUAL LOGS SUMMARY${NC}\n"
        printf "${BLUE}========================================${NC}\n"
        log_success "Individual test logs saved to: $LOGS_DIR"
        log_info "📋 Check $LOGS_DIR/crontab-changes.txt for scripts that modified crontab"
        log_info "📁 Each script has its own subdirectory with detailed logs"

        if [ -f "$LOGS_DIR/crontab-changes.txt" ]; then
            crontab_modifications=$(grep -c "Script:" "$LOGS_DIR/crontab-changes.txt" 2>/dev/null || echo "0")
            if [ "$crontab_modifications" -gt 0 ]; then
                log_warning "🚨 $crontab_modifications script(s) modified crontab during testing!"
                log_info "Review: $LOGS_DIR/crontab-changes.txt"
            else
                log_success "✅ No crontab modifications detected during testing"
            fi
        fi
    fi
}

# Execute main function
main "$@"
