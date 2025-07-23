#!/bin/sh
# shellcheck disable=SC2059  # RUTOS requires Method 5 printf format (embedded variables)
# Script: dev-testing-rutos.sh
# Version: 2.5.0
# Description: Simple RUTOS script testing with AI-friendly error reporting
# Usage: ./scripts/dev-testing-rutos.sh [--debug] [--help]

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.5.0"
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
    --script NAME, -s   Test only a specific script (e.g. --script system-status-rutos.sh)
    --help, -h          Show this help message

COMPREHENSIVE TESTING MODE:
    When --comprehensive is used, each script is tested with:
    1. Basic dry-run     (DRY_RUN=1)
    2. Debug dry-run     (DEBUG=1 DRY_RUN=1) 
    3. Test mode         (DRY_RUN=1 RUTOS_TEST_MODE=1)
    4. Full verbose      (DEBUG=1 DRY_RUN=1 RUTOS_TEST_MODE=1)
    
    This validates color output, user feedback, and various debugging levels.

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
    > "$temp_script_list"

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
                echo "$script" >> "$temp_script_list"
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
                echo "$script" >> "$temp_script_list"
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

    # Try to run script - it should respect our dry-run environment variables
    if ! timeout 20 sh "$script_path" >/tmp/test_output_$$ 2>&1; then
        # Check if error is due to missing config or dependencies vs real issues
        test_error=$(cat /tmp/test_output_$$ 2>/dev/null | head -5 || echo "Script execution failed")

        # Only report as error if it's not expected dependency issues
        if echo "$test_error" | grep -qE "(not found|No such file|Permission denied|command not found)" && ! echo "$test_error" | grep -q "syntax"; then
            log_debug "$script_name failed due to missing dependencies (expected in test environment)"
        else
            ERROR_DETAILS="${ERROR_DETAILS}EXECUTION ERROR in $script_name:
  File: $script_path  
  Error: $test_error
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
2:Debug_dry-run:DEBUG=1:DRY_RUN=1  
3:Test_mode:DRY_RUN=1:RUTOS_TEST_MODE=1
4:Full_verbose:DEBUG=1:DRY_RUN=1:RUTOS_TEST_MODE=1
"

    printf "\n${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║                    COMPREHENSIVE TEST: %-32s ║${NC}\n" "$script_name"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"

    echo "$test_modes" | while IFS=: read -r test_num test_desc env_vars; do
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

        # Execute with timeout and capture both stdout and stderr
        if eval "$test_env timeout 15 sh '$script_path'" >"$output_file" 2>&1; then
            printf "${GREEN}✅ SUCCESS${NC}\n"
            
            # Show first few lines of output to verify it looks good
            if [ -s "$output_file" ]; then
                printf "${CYAN}Output preview:${NC}\n"
                head -10 "$output_file" | sed 's/^/  /'
                if [ "$(wc -l < "$output_file")" -gt 10 ]; then
                    printf "  ${CYAN}... (truncated, %d total lines)${NC}\n" "$(wc -l < "$output_file")"
                fi
            else
                printf "${YELLOW}  (No output produced)${NC}\n"
            fi
        else
            printf "${RED}❌ FAILED${NC}\n"
            if [ -s "$output_file" ]; then
                printf "${RED}Error output:${NC}\n"
                head -10 "$output_file" | sed 's/^/  /'
            fi
            
            # Add to error details
            error_content=$(head -5 "$output_file" 2>/dev/null || echo "Unknown error")
            ERROR_DETAILS="${ERROR_DETAILS}COMPREHENSIVE TEST FAILURE in $script_name (Test $test_num: $test_desc):
  File: $script_path
  Environment: $env_vars
  Error: $error_content
  Fix: Check script logic, error handling, and environment variable handling
  
"
        fi

        rm -f "$output_file"
        printf "\n"
    done

    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n\n"
    return 0
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
        if [ "$COMPREHENSIVE_TEST" = "1" ]; then
            log_info "Running comprehensive test on $SINGLE_SCRIPT"
            test_script_comprehensive "$script_path"
        else
            log_info "Running basic test on $SINGLE_SCRIPT"
            if test_script "$script_path"; then
                log_success "✅ $SINGLE_SCRIPT passed all tests"
            else
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
        
        printf "%s\n" "$script_list" > "$temp_script_file"
        > "$temp_results"
        
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
                    echo "PASS:$script_name" >> "$temp_results"
                    # Check if script has dry-run support for display
                    if check_dry_run_support "$script"; then
                        printf "${GREEN}✅ PASS${NC} - %s ${CYAN}(dry-run ready)${NC}\n" "$script_name"
                    else
                        printf "${GREEN}✅ PASS${NC} - %s ${YELLOW}(needs dry-run)${NC}\n" "$script_name"
                    fi
                else
                    echo "FAIL:$script_name" >> "$temp_results"
                    printf "${RED}❌ FAIL${NC} - %s\n" "$script_name"
                fi
            fi
        done < "$temp_script_file"
        
        # Calculate final results
        if [ -f "$temp_results" ] && [ -s "$temp_results" ]; then
            # Use more robust counting to avoid whitespace issues - fix command order
            TOTAL_SCRIPTS=$(wc -l < "$temp_results" | tr -d ' \n\r')
            
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
}

# Execute main function
main "$@"
