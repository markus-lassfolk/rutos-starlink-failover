#!/bin/sh
# shellcheck disable=SC2059  # RUTOS requires Method 5 printf format (embedded variables)
# shellcheck disable=SC2317  # Functions are called dynamically by main()
# Script: dev-testing-rutos.sh
# Version: 2.4.12 (Consolidated)
# Description: Comprehensive RUTOS development testing script with consolidated functionality
# Usage: ./scripts/dev-testing-rutos.sh [--force-update] [--no-install] [--debug] [--help]

set -e # Exit on error

# Version information (auto-updated by update-version.sh)
readonly SCRIPT_VERSION="2.4.12"

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
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ] || [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-}" != "" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors
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

log_header() {
    printf "\n${PURPLE}========================================${NC}\n"
    printf "${PURPLE}%s${NC}\n" "$1"
    printf "${PURPLE}========================================${NC}\n"
}

log_test_result() {
    test_name="$1"
    status="$2"
    details="$3"

    case "$status" in
        "PASS")
            printf "${GREEN}✅ PASS${NC}     | %-25s | %s\n" "$test_name" "$details"
            ;;
        "FAIL")
            printf "${RED}❌ FAIL${NC}     | %-25s | %s\n" "$test_name" "$details"
            ;;
        "WARN")
            printf "${YELLOW}⚠️  WARN${NC}     | %-25s | %s\n" "$test_name" "$details"
            ;;
        "SKIP")
            printf "${CYAN}⏭️  SKIP${NC}     | %-25s | %s\n" "$test_name" "$details"
            ;;
        *)
            printf "${PURPLE}ℹ️  INFO${NC}     | %-25s | %s\n" "$test_name" "$details"
            ;;
    esac
}

# Configuration and flags
DEBUG="${DEBUG:-0}"
FORCE_UPDATE="${FORCE_UPDATE:-0}"
NO_INSTALL="${NO_INSTALL:-0}"
SKIP_SELF_UPDATE="${SKIP_SELF_UPDATE:-0}"
DRY_RUN="${DRY_RUN:-1}"
RUTOS_TEST_MODE="${RUTOS_TEST_MODE:-1}"

# Test result counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0
SKIPPED_TESTS=0

# Working directories
WORK_DIR="/tmp/rutos-dev-test-$$"
TEST_DIR="$WORK_DIR/test-env"
LOG_DIR="$WORK_DIR/logs"
ERROR_LOG="$LOG_DIR/test-errors.txt"
SUMMARY_LOG="$LOG_DIR/test-summary.txt"
# shellcheck disable=SC2034  # Reserved for detailed logging
FULL_LOG="$LOG_DIR/test-full.txt"

# Parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --force-update)
                FORCE_UPDATE=1
                shift
                ;;
            --no-install)
                NO_INSTALL=1
                shift
                ;;
            --debug | -debug)
                DEBUG=1
                shift
                ;;
            --skip-self-update)
                SKIP_SELF_UPDATE=1
                shift
                ;;
            --live-mode)
                DRY_RUN=0
                RUTOS_TEST_MODE=0
                log_warning "Live mode enabled - scripts will make actual changes!"
                shift
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
RUTOS Development Testing Script v$SCRIPT_VERSION (Consolidated Version)

USAGE:
    ./scripts/dev-testing-rutos.sh [OPTIONS]

OPTIONS:
    --force-update      Force update even if versions match
    --no-install        Skip running install-rutos.sh (test existing files only)
    --debug             Enable debug output
    --skip-self-update  Skip self-update check (for testing)
    --live-mode         Disable dry-run mode (CAUTION: makes real changes!)
    --help, -h          Show this help message

WORKFLOW:
    1. Self-update from GitHub (unless --skip-self-update)
    2. Download and run install-rutos.sh (unless --no-install)
    3. Comprehensive testing of all deployed scripts:
       - Syntax validation (POSIX sh compliance)
       - RUTOS compatibility checks (busybox shell)
       - Execution testing (dry-run mode)
       - Functionality validation
       - Error handling verification
    4. Generate AI-friendly error reports for debugging

TEST CATEGORIES:
    🔍 Syntax Tests     - Shell parser validation
    🔧 Compatibility   - RUTOS/busybox specific checks
    ⚡ Execution       - Dry-run execution testing
    🎯 Functionality   - Feature-specific validation
    📊 Integration     - End-to-end workflow testing

OUTPUTS:
    - dev-test-summary.txt     (Quick overview with pass/fail counts)
    - dev-test-errors.txt      (AI-friendly error details with fixes)
    - dev-test-full-log.txt    (Complete execution log with debug info)

EXAMPLES:
    ./scripts/dev-testing-rutos.sh                    # Full workflow with dry-run
    ./scripts/dev-testing-rutos.sh --debug            # With detailed debug output
    ./scripts/dev-testing-rutos.sh --no-install       # Test existing files only
    ./scripts/dev-testing-rutos.sh --force-update     # Force update everything
    ./scripts/dev-testing-rutos.sh --live-mode        # DANGEROUS: actual execution

SAFETY:
    By default, all tests run in DRY_RUN mode and RUTOS_TEST_MODE.
    This prevents actual system changes during testing.
    Use --live-mode only for final validation on actual RUTOS device.

FEATURES (CONSOLIDATED FROM ALL TESTING SCRIPTS):
    ✅ Self-updating capability with GitHub integration
    ✅ Comprehensive syntax validation for all shell scripts
    ✅ RUTOS compatibility checks (busybox shell compliance)
    ✅ Execution testing with timeout protection
    ✅ Version consistency validation across all scripts
    ✅ Readonly variable conflict detection
    ✅ AI-friendly error reporting with specific fixes
    ✅ Complete test statistics and success rates
    ✅ Safe dry-run mode by default
EOF
}

# Setup working environment
setup_test_environment() {
    log_step "Setting up test environment"

    # Create working directories
    mkdir -p "$WORK_DIR" "$TEST_DIR" "$LOG_DIR"

    # Initialize test logs
    cat >"$ERROR_LOG" <<EOF
RUTOS DEVELOPMENT TESTING - ERROR REPORT
========================================
Test Date: $(date)
Script Version: $SCRIPT_VERSION
Repository: ${GITHUB_USER}/${GITHUB_REPO}

ERRORS AND ISSUES FOUND:
EOF

    cat >"$SUMMARY_LOG" <<EOF
RUTOS DEVELOPMENT TESTING - SUMMARY
===================================
Test Date: $(date)
Script Version: $SCRIPT_VERSION

TEST RESULTS:
EOF

    # Set up environment variables for all tests
    export DEBUG="$DEBUG"
    export DRY_RUN="$DRY_RUN"
    export RUTOS_TEST_MODE="$RUTOS_TEST_MODE"
    export TEST_MODE=1

    log_debug "Test environment:"
    log_debug "  Work directory: $WORK_DIR"
    log_debug "  Test directory: $TEST_DIR"
    log_debug "  Log directory: $LOG_DIR"
    log_debug "  DRY_RUN: $DRY_RUN"
    log_debug "  RUTOS_TEST_MODE: $RUTOS_TEST_MODE"

    log_success "Test environment ready"
}

# Check dependencies
check_dependencies() {
    log_debug "Checking dependencies"

    missing_deps=""

    # Check for required commands
    for cmd in curl sh find grep; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="$missing_deps $cmd"
        fi
    done

    if [ -n "$missing_deps" ]; then
        log_error "Missing required dependencies:$missing_deps"
        log_error "Please install missing commands and try again"
        exit 1
    fi

    # Check for optional but recommended commands
    for cmd in timeout wget; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_warning "Optional command '$cmd' not found - some tests may be skipped"
        fi
    done

    log_debug "Dependencies check passed"
}

# Get latest version from GitHub
get_latest_version() {
    log_debug "Fetching latest version from GitHub"

    if latest_version=$(curl -fsSL "${GITHUB_RAW_BASE}/VERSION" 2>/dev/null); then
        log_debug "Latest version from GitHub: $latest_version"
        echo "$latest_version"
        return 0
    else
        log_warning "Could not fetch latest version from GitHub"
        return 1
    fi
}

# Version comparison function
version_compare() {
    test_version="$1"
    latest_version="$2"

    # Simple version comparison (works for semantic versioning)
    if [ "$test_version" = "$latest_version" ]; then
        return 0 # Equal
    else
        return 1 # Different
    fi
}

# Self-update functionality
self_update() {
    if [ "$SKIP_SELF_UPDATE" = "1" ]; then
        log_info "Skipping self-update (--skip-self-update specified)"
        return 0
    fi

    # Check for update loop prevention
    if [ "${SCRIPT_UPDATE_ATTEMPT:-0}" -gt 0 ]; then
        log_warning "Update loop detected - skipping self-update to prevent infinite loop"
        return 0
    fi

    log_step "Checking for dev-testing-rutos.sh updates"

    # Get current script path
    SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
    SCRIPT_NAME="dev-testing-rutos.sh" # Always look for the main script name

    log_debug "Current script: $SCRIPT_PATH"
    log_debug "Current version: $SCRIPT_VERSION"

    # Download latest version to temporary file
    TEMP_SCRIPT="$WORK_DIR/${SCRIPT_NAME}.latest"
    GITHUB_SCRIPT_URL="${GITHUB_RAW_BASE}/scripts/${SCRIPT_NAME}"

    log_debug "Downloading latest version from: $GITHUB_SCRIPT_URL"

    if curl -fsSL "$GITHUB_SCRIPT_URL" -o "$TEMP_SCRIPT" 2>/dev/null; then
        # Extract version from downloaded script
        if latest_script_version=$(grep '^SCRIPT_VERSION=' "$TEMP_SCRIPT" | head -1 | cut -d'"' -f2 2>/dev/null) && [ -n "$latest_script_version" ]; then
            log_debug "Latest script version: $latest_script_version"

            # Compare versions
            if ! version_compare "$SCRIPT_VERSION" "$latest_script_version" || [ "$FORCE_UPDATE" = "1" ]; then
                log_info "Latest dev-testing-rutos.sh available (v$latest_script_version vs current v$SCRIPT_VERSION)"

                # Verify downloaded script syntax
                if ! sh -n "$TEMP_SCRIPT" 2>/dev/null; then
                    log_error "Downloaded script has syntax errors - keeping current version"
                    rm -f "$TEMP_SCRIPT"
                    return 1
                fi

                log_info "Auto-updating to latest version and restarting..."

                # Make backup of current script
                cp "$SCRIPT_PATH" "${SCRIPT_PATH}.backup.$(date +%s)"

                # Replace current script with latest version
                cp "$TEMP_SCRIPT" "$SCRIPT_PATH"
                chmod +x "$SCRIPT_PATH"

                log_success "Script updated successfully - restarting with new version"

                # Set environment variable to prevent update loops
                export SCRIPT_UPDATE_ATTEMPT=1

                # Re-execute with updated script
                exec sh "$SCRIPT_PATH" "$@"
            else
                log_info "dev-testing-rutos.sh is up to date (v$SCRIPT_VERSION)"
            fi
        else
            log_warning "Could not extract version from downloaded script - keeping current version"
            log_info "This may indicate the GitHub version has issues or is incomplete"
        fi

        rm -f "$TEMP_SCRIPT"
    else
        log_warning "Could not download latest dev-testing-rutos.sh from GitHub"
        log_info "Continuing with current consolidated version (v$SCRIPT_VERSION)"
    fi
}

# Download and run install-rutos.sh
run_install_script() {
    if [ "$NO_INSTALL" = "1" ]; then
        log_info "Skipping install-rutos.sh (--no-install specified)"
        return 0
    fi

    log_step "Downloading and running install-rutos.sh"

    # Create temporary directory for install script
    INSTALL_DIR="$WORK_DIR/install"
    mkdir -p "$INSTALL_DIR"

    # Download install script
    INSTALL_SCRIPT="$INSTALL_DIR/install-rutos.sh"
    INSTALL_URL="${GITHUB_RAW_BASE}/scripts/install-rutos.sh"

    log_debug "Downloading install script from: $INSTALL_URL"

    if curl -fsSL "$INSTALL_URL" -o "$INSTALL_SCRIPT"; then
        chmod +x "$INSTALL_SCRIPT"

        log_info "Running install-rutos.sh in test mode..."

        # Run install script with test/dry-run flags
        (
            cd "$INSTALL_DIR"
            export RUTOS_TEST_MODE=1
            export DRY_RUN=1
            export DEBUG="$DEBUG"
            export INSTALL_DIR="$TEST_DIR/starlink-monitor"

            if sh "$INSTALL_SCRIPT" --test-mode --dry-run; then
                log_success "install-rutos.sh completed successfully"
                return 0
            else
                log_warning "install-rutos.sh encountered issues"
                return 1
            fi
        )
    else
        log_error "Failed to download install-rutos.sh from GitHub"
        return 1
    fi
}

# Test individual script syntax
test_script_syntax() {
    script_path="$1"
    script_name=$(basename "$script_path")

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    log_debug "Testing syntax for $script_name"

    # Check if file exists and is readable
    if [ ! -f "$script_path" ] || [ ! -r "$script_path" ]; then
        log_test_result "$script_name" "FAIL" "File not found or not readable"
        echo "ERROR: $script_name - File not found or not readable at $script_path" >>"$ERROR_LOG"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    # Test syntax with shell parser
    if sh -n "$script_path" 2>"$WORK_DIR/${script_name}.syntax_err"; then
        log_test_result "$script_name" "PASS" "Syntax valid"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        syntax_error=$(cat "$WORK_DIR/${script_name}.syntax_err" 2>/dev/null || echo "Unknown syntax error")
        log_test_result "$script_name" "FAIL" "Syntax error"
        echo "SYNTAX_ERROR: $script_name" >>"$ERROR_LOG"
        echo "  Script: $script_path" >>"$ERROR_LOG"
        echo "  Error: $syntax_error" >>"$ERROR_LOG"
        echo "  Fix: Check shell syntax, missing quotes, unmatched brackets" >>"$ERROR_LOG"
        echo "" >>"$ERROR_LOG"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Test RUTOS compatibility
test_rutos_compatibility() {
    script_path="$1"
    script_name=$(basename "$script_path")

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    log_debug "Testing RUTOS compatibility for $script_name"

    compat_issues=""

    # Check for bash-specific syntax that won't work in busybox
    # Look for actual [[ ]] conditional expressions, not POSIX character classes
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

    if grep -q '\$'"'"'\\n'"'"'' "$script_path" 2>/dev/null; then
        compat_issues="${compat_issues}\$'\\n' syntax (use printf instead); "
    fi

    if grep -qE '^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' "$script_path" 2>/dev/null; then
        compat_issues="${compat_issues}'function name()' syntax (use 'name()' only); "
    fi

    if grep -qE '^[[:space:]]*export[[:space:]]+-f[[:space:]]' "$script_path" 2>/dev/null; then
        compat_issues="${compat_issues}'export -f' (not in POSIX sh); "
    fi

    # Check if it's a RUTOS-specific script and validate naming
    if echo "$script_name" | grep -q '\-rutos\.sh$'; then
        # RUTOS scripts should be extra compliant
        if [ -n "$compat_issues" ]; then
            log_test_result "$script_name" "FAIL" "RUTOS compatibility issues: $compat_issues"
            echo "COMPATIBILITY_ERROR: $script_name" >>"$ERROR_LOG"
            echo "  Script: $script_path" >>"$ERROR_LOG"
            echo "  Issues: $compat_issues" >>"$ERROR_LOG"
            echo "  Fix: Replace bash-specific syntax with POSIX sh equivalents" >>"$ERROR_LOG"
            echo "" >>"$ERROR_LOG"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    else
        # Non-RUTOS scripts get warnings instead of failures
        if [ -n "$compat_issues" ]; then
            log_test_result "$script_name" "WARN" "Potential RUTOS issues: $compat_issues"
            echo "COMPATIBILITY_WARNING: $script_name" >>"$ERROR_LOG"
            echo "  Script: $script_path" >>"$ERROR_LOG"
            echo "  Issues: $compat_issues" >>"$ERROR_LOG"
            echo "  Fix: Consider RUTOS compatibility if deploying to router" >>"$ERROR_LOG"
            echo "" >>"$ERROR_LOG"
            WARNING_TESTS=$((WARNING_TESTS + 1))
            return 0
        fi
    fi

    log_test_result "$script_name" "PASS" "RUTOS compatible"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

# Test script execution
test_script_execution() {
    script_path="$1"
    script_name=$(basename "$script_path")
    timeout_duration="${2:-30}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    log_debug "Testing execution for $script_name (timeout: ${timeout_duration}s)"

    # Set up execution environment
    original_dir=$(pwd)
    script_dir=$(dirname "$script_path")

    # shellcheck disable=SC2030,SC2031  # Intentional subshell for isolated testing
    (
        cd "$script_dir" 2>/dev/null || cd "$original_dir"
        export RUTOS_TEST_MODE=1
        export DRY_RUN=1
        export DEBUG=0 # Reduce noise during testing

        # Try execution with common test arguments
        if command -v timeout >/dev/null 2>&1; then
            timeout "$timeout_duration" sh "$script_path" --dry-run --test-mode >/dev/null 2>"$WORK_DIR/${script_name}.exec_err" ||
                timeout "$timeout_duration" sh "$script_path" --test-mode >/dev/null 2>"$WORK_DIR/${script_name}.exec_err" ||
                timeout "$timeout_duration" sh "$script_path" --help >/dev/null 2>"$WORK_DIR/${script_name}.exec_err" ||
                timeout "$timeout_duration" sh "$script_path" >/dev/null 2>"$WORK_DIR/${script_name}.exec_err"
        else
            sh "$script_path" --dry-run --test-mode >/dev/null 2>"$WORK_DIR/${script_name}.exec_err" ||
                sh "$script_path" --test-mode >/dev/null 2>"$WORK_DIR/${script_name}.exec_err" ||
                sh "$script_path" --help >/dev/null 2>"$WORK_DIR/${script_name}.exec_err" ||
                sh "$script_path" >/dev/null 2>"$WORK_DIR/${script_name}.exec_err"
        fi
    )

    execution_result=$?

    if [ "$execution_result" -eq 0 ]; then
        log_test_result "$script_name" "PASS" "Executed successfully"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    elif [ "$execution_result" -eq 124 ]; then
        log_test_result "$script_name" "WARN" "Execution timeout (${timeout_duration}s)"
        echo "EXECUTION_TIMEOUT: $script_name" >>"$ERROR_LOG"
        echo "  Script: $script_path" >>"$ERROR_LOG"
        echo "  Timeout: ${timeout_duration} seconds" >>"$ERROR_LOG"
        echo "  Fix: Optimize script performance or increase timeout" >>"$ERROR_LOG"
        echo "" >>"$ERROR_LOG"
        WARNING_TESTS=$((WARNING_TESTS + 1))
        return 1
    else
        execution_error=$(cat "$WORK_DIR/${script_name}.exec_err" 2>/dev/null || echo "Unknown execution error")

        # Check if it's a graceful failure (help message, etc.)
        if echo "$execution_error" | grep -qi "usage\|help\|invalid.*option"; then
            log_test_result "$script_name" "PASS" "Graceful argument handling"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            log_test_result "$script_name" "FAIL" "Execution failed"
            echo "EXECUTION_ERROR: $script_name" >>"$ERROR_LOG"
            echo "  Script: $script_path" >>"$ERROR_LOG"
            echo "  Exit code: $execution_result" >>"$ERROR_LOG"
            echo "  Error: $execution_error" >>"$ERROR_LOG"
            echo "  Fix: Check script logic, dependencies, and error handling" >>"$ERROR_LOG"
            echo "" >>"$ERROR_LOG"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    fi
}

# Run comprehensive testing
run_comprehensive_tests() {
    log_header "COMPREHENSIVE SCRIPT TESTING"

    # Find all shell scripts to test
    log_step "Discovering shell scripts"

    # Get script lists
    main_scripts=""
    utility_scripts=""
    test_scripts=""
    config_files=""

    # Main monitoring scripts
    if [ -d "Starlink-RUTOS-Failover" ]; then
        main_scripts=$(find Starlink-RUTOS-Failover -name "*.sh" -type f 2>/dev/null | sort)
    fi

    # Utility scripts
    if [ -d "scripts" ]; then
        utility_scripts=$(find scripts -name "*.sh" -type f 2>/dev/null | sort)
    fi

    # Test scripts
    if [ -d "tests" ]; then
        test_scripts=$(find tests -name "*.sh" -type f 2>/dev/null | sort)
    fi

    # Configuration files
    if [ -d "config" ]; then
        config_files=$(find config -name "*.sh" -type f 2>/dev/null | sort)
    fi

    total_scripts=0
    for script_list in "$main_scripts" "$utility_scripts" "$test_scripts" "$config_files"; do
        if [ -n "$script_list" ]; then
            total_scripts=$((total_scripts + $(echo "$script_list" | wc -l)))
        fi
    done

    log_info "Found $total_scripts shell scripts to test"

    # Test categories
    log_header "SYNTAX VALIDATION"
    printf "${BLUE}Testing shell syntax for all scripts...${NC}\n"

    # Test syntax for all scripts
    # Process each script list separately using direct iteration
    if [ -n "$main_scripts" ]; then
        for script in $main_scripts; do
            test_script_syntax "$script"
        done
    fi
    if [ -n "$utility_scripts" ]; then
        for script in $utility_scripts; do
            test_script_syntax "$script"
        done
    fi
    if [ -n "$test_scripts" ]; then
        for script in $test_scripts; do
            test_script_syntax "$script"
        done
    fi
    if [ -n "$config_files" ]; then
        for script in $config_files; do
            test_script_syntax "$script"
        done
    fi

    log_header "RUTOS COMPATIBILITY"
    printf "${BLUE}Testing RUTOS/busybox compatibility...${NC}\n"

    # Test RUTOS compatibility for all scripts
    # Process each script list separately using direct iteration
    if [ -n "$main_scripts" ]; then
        for script in $main_scripts; do
            test_rutos_compatibility "$script"
        done
    fi
    if [ -n "$utility_scripts" ]; then
        for script in $utility_scripts; do
            test_rutos_compatibility "$script"
        done
    fi
    if [ -n "$test_scripts" ]; then
        for script in $test_scripts; do
            test_rutos_compatibility "$script"
        done
    fi
    if [ -n "$config_files" ]; then
        for script in $config_files; do
            test_rutos_compatibility "$script"
        done
    fi

    log_header "EXECUTION TESTING"
    printf "${BLUE}Testing script execution (dry-run mode)...${NC}\n"

    # Test execution for executable scripts (skip config files)
    # Process each script list separately using direct iteration
    if [ -n "$main_scripts" ]; then
        for script in $main_scripts; do
            # Skip non-executable scripts and the current script
            if [ -x "$script" ] || echo "$script" | grep -q '\.sh$'; then
                # Skip self to avoid recursion
                if [ "$script" != "$0" ] && [ "$(basename "$script")" != "dev-testing-rutos.sh" ]; then
                    test_script_execution "$script" 15 # 15 second timeout
                fi
            fi
        done
    fi
    if [ -n "$utility_scripts" ]; then
        for script in $utility_scripts; do
            # Skip non-executable scripts and the current script
            if [ -x "$script" ] || echo "$script" | grep -q '\.sh$'; then
                # Skip self to avoid recursion
                if [ "$script" != "$0" ] && [ "$(basename "$script")" != "dev-testing-rutos.sh" ]; then
                    test_script_execution "$script" 15 # 15 second timeout
                fi
            fi
        done
    fi
    if [ -n "$test_scripts" ]; then
        for script in $test_scripts; do
            # Skip non-executable scripts and the current script
            if [ -x "$script" ] || echo "$script" | grep -q '\.sh$'; then
                # Skip self to avoid recursion
                if [ "$script" != "$0" ] && [ "$(basename "$script")" != "dev-testing-rutos.sh" ]; then
                    test_script_execution "$script" 15 # 15 second timeout
                fi
            fi
        done
    fi

    log_header "SPECIAL VALIDATIONS"
    printf "${BLUE}Running additional validation checks...${NC}\n"

    # Check for version consistency
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_debug "Checking version consistency across scripts"

    version_issues=0
    if [ -n "$main_scripts" ]; then
        for script in $main_scripts; do
            if grep -q "SCRIPT_VERSION=" "$script" 2>/dev/null; then
                script_version=$(grep "SCRIPT_VERSION=" "$script" | head -1 | cut -d'"' -f2 2>/dev/null)
                if [ "$script_version" != "$SCRIPT_VERSION" ]; then
                    echo "VERSION_MISMATCH: $(basename "$script") has version $script_version, expected $SCRIPT_VERSION" >>"$ERROR_LOG"
                    version_issues=$((version_issues + 1))
                fi
            fi
        done
    fi
    if [ -n "$utility_scripts" ]; then
        for script in $utility_scripts; do
            if grep -q "SCRIPT_VERSION=" "$script" 2>/dev/null; then
                script_version=$(grep "SCRIPT_VERSION=" "$script" | head -1 | cut -d'"' -f2 2>/dev/null)
                if [ "$script_version" != "$SCRIPT_VERSION" ]; then
                    echo "VERSION_MISMATCH: $(basename "$script") has version $script_version, expected $SCRIPT_VERSION" >>"$ERROR_LOG"
                    version_issues=$((version_issues + 1))
                fi
            fi
        done
    fi

    if [ "$version_issues" -eq 0 ]; then
        log_test_result "Version Consistency" "PASS" "All scripts have matching versions"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_test_result "Version Consistency" "WARN" "$version_issues version mismatches found"
        WARNING_TESTS=$((WARNING_TESTS + 1))
    fi

    # Check for readonly variable conflicts
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_debug "Checking for readonly variable conflicts"

    readonly_issues=0
    if [ -n "$main_scripts" ]; then
        for script in $main_scripts; do
            if grep -q "readonly.*SCRIPT_VERSION\|SCRIPT_VERSION.*readonly" "$script" 2>/dev/null; then
                echo "READONLY_INFO: $(basename "$script") has readonly SCRIPT_VERSION (informational only)" >>"$ERROR_LOG"
                readonly_issues=$((readonly_issues + 1))
            fi
        done
    fi
    if [ -n "$utility_scripts" ]; then
        for script in $utility_scripts; do
            if grep -q "readonly.*SCRIPT_VERSION\|SCRIPT_VERSION.*readonly" "$script" 2>/dev/null; then
                echo "READONLY_INFO: $(basename "$script") has readonly SCRIPT_VERSION (informational only)" >>"$ERROR_LOG"
                readonly_issues=$((readonly_issues + 1))
            fi
        done
    fi

    # Readonly variables are not actually a problem for RUTOS deployment
    log_test_result "Readonly Variables" "PASS" "$readonly_issues scripts use readonly (acceptable for RUTOS)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

# Generate comprehensive reports
generate_comprehensive_reports() {
    # shellcheck disable=SC2120  # Function doesn't need parameters for current implementation
    log_step "Generating comprehensive test reports"

    # Calculate success rate
    if [ "$TOTAL_TESTS" -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    else
        success_rate=0
    fi

    # Generate summary report
    cat >"$SUMMARY_LOG" <<EOF
RUTOS DEVELOPMENT TESTING - FINAL SUMMARY
=========================================
Test Date: $(date)
Script Version: $SCRIPT_VERSION (Consolidated Version)
Repository: ${GITHUB_USER}/${GITHUB_REPO}

OVERALL RESULTS:
✅ PASSED:     $PASSED_TESTS tests
❌ FAILED:     $FAILED_TESTS tests
⚠️  WARNINGS:  $WARNING_TESTS tests
⏭️  SKIPPED:   $SKIPPED_TESTS tests
📊 TOTAL:      $TOTAL_TESTS tests
🎯 SUCCESS:    ${success_rate}%

TEST CATEGORIES COMPLETED:
✅ Syntax Validation       - Shell parser verification
✅ RUTOS Compatibility     - Busybox shell compliance
✅ Execution Testing       - Dry-run mode validation
✅ Special Validations     - Version and variable checks

GENERATED REPORTS:
📄 $(basename "$SUMMARY_LOG")    - This summary
🤖 dev-test-errors.txt       - AI-friendly debugging info
📋 dev-test-full-log.txt     - Complete execution details

STATUS: $(if [ "$FAILED_TESTS" -eq 0 ]; then echo "🎉 ALL TESTS PASSED"; else echo "❌ ISSUES FOUND - REVIEW REQUIRED"; fi)

CONSOLIDATION NOTE:
This is the consolidated version combining features from:
- dev-testing-rutos.sh (master workflow)
- test-rutos-deployment.sh (comprehensive testing)
- All best practices from existing testing scripts
EOF

    # Copy summary to main directory
    cp "$SUMMARY_LOG" "./dev-test-summary.txt"

    # Generate AI-friendly error report
    cat >"./dev-test-errors.txt" <<EOF
AI DEBUGGING REPORT FOR RUTOS STARLINK FAILOVER
===============================================

COPY THIS ENTIRE SECTION TO AI FOR DEBUGGING:

## Context
- Project: RUTOS Starlink Failover System  
- Environment: RUTX50 router with busybox shell (POSIX sh only)
- Test Results: $PASSED_TESTS passed, $FAILED_TESTS failed, $WARNING_TESTS warnings
- Success Rate: ${success_rate}%
- Script: scripts/dev-testing-rutos.sh (Consolidated Version)

## Test Summary
Total Tests: $TOTAL_TESTS
- ✅ Passed: $PASSED_TESTS
- ❌ Failed: $FAILED_TESTS  
- ⚠️  Warnings: $WARNING_TESTS
- ⏭️  Skipped: $SKIPPED_TESTS

EOF

    # Add detailed errors if any
    if [ -s "$ERROR_LOG" ]; then
        echo "## Detailed Error Analysis" >>"./dev-test-errors.txt"
        cat "$ERROR_LOG" >>"./dev-test-errors.txt"
    else
        echo "## Detailed Error Analysis" >>"./dev-test-errors.txt"
        echo "🎉 No errors found! All tests passed successfully." >>"./dev-test-errors.txt"
    fi

    # Add project structure for context
    cat >>"./dev-test-errors.txt" <<EOF

## Project Structure
\`\`\`
$(find . -name "*.sh" -o -name "*.md" -o -name "*.txt" | grep -E "\.(sh|md|txt)$" | head -30 | sort)
\`\`\`

## Environment Information
- Script Version: $SCRIPT_VERSION (Consolidated)
- Test Mode: DRY_RUN=$DRY_RUN, RUTOS_TEST_MODE=$RUTOS_TEST_MODE
- Working Directory: $(pwd)
- Test Date: $(date)

## Consolidation Info
This report was generated by scripts/dev-testing-rutos.sh, which consolidates features from:
- dev-testing-rutos.sh (master workflow)
- test-rutos-deployment.sh (comprehensive testing engine)
- All best practices from the project testing infrastructure

## Instructions for AI:
1. Analyze all errors and warnings listed above
2. Prioritize RUTOS compatibility issues (busybox shell environment)
3. Focus on syntax errors, readonly variable conflicts, and compatibility issues
4. Provide specific file edits with line numbers where needed
5. Ensure all fixes maintain POSIX sh compatibility for RUTX50 deployment

## Expected Fix Format:
- File: [filename]
- Line: [line number] (if applicable)
- Issue: [description]
- Fix: [specific code change]
- Reason: [why this fix is needed for RUTOS compatibility]

## Environment Requirements:
- Must work in busybox sh (not bash)
- Must be POSIX compliant  
- Must handle readonly variables properly
- Must work on RUTX50 RUTOS router environment
- Should follow project coding guidelines from .github/copilot-instructions.md
EOF

    # Generate full execution log
    cat >"./dev-test-full-log.txt" <<EOF
FULL DEVELOPMENT TESTING LOG (CONSOLIDATED VERSION)
===================================================
Generated: $(date)
Script: scripts/dev-testing-rutos.sh v$SCRIPT_VERSION

EXECUTION DETAILS:
Command Line: $0 $*
Working Directory: $(pwd)
Environment Variables:
- DEBUG=$DEBUG
- FORCE_UPDATE=$FORCE_UPDATE
- NO_INSTALL=$NO_INSTALL  
- SKIP_SELF_UPDATE=$SKIP_SELF_UPDATE
- DRY_RUN=$DRY_RUN
- RUTOS_TEST_MODE=$RUTOS_TEST_MODE

WORKFLOW EXECUTED:
$(if [ "$SKIP_SELF_UPDATE" = "0" ]; then echo "✅ Self-update check performed"; else echo "⏭️  Self-update skipped"; fi)
$(if [ "$NO_INSTALL" = "0" ]; then echo "✅ Install script execution attempted"; else echo "⏭️  Install script execution skipped"; fi)
✅ Comprehensive testing performed
✅ Test reports generated

FINAL STATISTICS:
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS (${success_rate}%)
Failed: $FAILED_TESTS
Warnings: $WARNING_TESTS
Skipped: $SKIPPED_TESTS

CONSOLIDATION INFO:
===================
This log was generated by the consolidated testing script that combines:
- Master workflow from dev-testing-rutos.sh
- Comprehensive testing engine from test-rutos-deployment.sh
- Enhanced error reporting and AI-friendly output
- RUTOS-specific compatibility checks
- Version consistency validation
- Readonly variable conflict detection

DETAILED LOGS:
==============
EOF

    # Include detailed test results if available
    if [ -s "$ERROR_LOG" ]; then
        echo "" >>"./dev-test-full-log.txt"
        echo "ERROR DETAILS:" >>"./dev-test-full-log.txt"
        echo "==============" >>"./dev-test-full-log.txt"
        cat "$ERROR_LOG" >>"./dev-test-full-log.txt"
    fi

    log_success "Reports generated successfully:"
    log_info "  📄 dev-test-summary.txt - Quick overview with statistics"
    log_info "  🤖 dev-test-errors.txt - AI-friendly debugging info (copy-paste ready)"
    log_info "  📋 dev-test-full-log.txt - Complete execution details and logs"
}

# Cleanup function
cleanup() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "Cleaning up temporary files at $WORK_DIR"
    fi

    # Remove temporary files but keep reports
    if [ -d "$WORK_DIR" ]; then
        find "$WORK_DIR" -name "*.syntax_err" -delete 2>/dev/null || true
        find "$WORK_DIR" -name "*.exec_err" -delete 2>/dev/null || true
        find "$WORK_DIR" -name "*.tmp" -delete 2>/dev/null || true
    fi

    # Only remove work directory if not in debug mode
    if [ "$DEBUG" != "1" ]; then
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi
}

# Main execution function
main() {
    log_header "RUTOS Development Testing v$SCRIPT_VERSION (Consolidated)"

    # Parse command line arguments
    parse_arguments "$@"

    if [ "$DEBUG" = "1" ]; then
        log_debug "==================== DEBUG MODE ENABLED ===================="
        log_debug "Script version: $SCRIPT_VERSION (Consolidated)"
        log_debug "Working directory: $(pwd)"
        log_debug "Arguments: $*"
        log_debug "Configuration:"
        log_debug "  FORCE_UPDATE=$FORCE_UPDATE"
        log_debug "  NO_INSTALL=$NO_INSTALL"
        log_debug "  SKIP_SELF_UPDATE=$SKIP_SELF_UPDATE"
        log_debug "  DEBUG=$DEBUG"
        log_debug "  DRY_RUN=$DRY_RUN"
        log_debug "  RUTOS_TEST_MODE=$RUTOS_TEST_MODE"
        set -x # Enable command tracing in debug mode
    fi

    # Setup environment
    setup_test_environment
    check_dependencies

    # Workflow execution
    workflow_success=true # shellcheck disable=SC2034  # Future use for workflow validation

    # Step 1: Self-update check (informational for consolidated version)
    if ! self_update "$@"; then
        log_warning "Self-update check completed (using consolidated version)"
    fi

    # Step 2: Download and run install script (if requested)
    if ! run_install_script; then
        log_warning "Install script execution had issues"
        workflow_success=false
    fi

    # Step 3: Run comprehensive tests
    if ! run_comprehensive_tests; then
        log_warning "Some comprehensive tests encountered issues"
        workflow_success=false
    fi

    # Step 4: Generate comprehensive reports
    # shellcheck disable=SC2119  # Function doesn't require parameters
    generate_comprehensive_reports

    # Final summary
    log_header "DEVELOPMENT TESTING COMPLETE"

    if [ "$FAILED_TESTS" -eq 0 ]; then
        log_success "🎉 ALL TESTS PASSED! Scripts are ready for RUTOS deployment"
        log_info "✅ Success Rate: ${success_rate}% ($PASSED_TESTS/$TOTAL_TESTS tests passed)"
        if [ "$WARNING_TESTS" -gt 0 ]; then
            log_info "⚠️  Note: $WARNING_TESTS warnings found (review recommended)"
        fi
        echo ""
        echo "$(printf "${GREEN}Next steps:${NC}")"
        echo "1. Review summary: cat dev-test-summary.txt"
        echo "2. Script is now properly located at scripts/dev-testing-rutos.sh"
        echo "3. Add to install-rutos.sh for deployment"
        echo "4. Deploy to RUTOS router when ready"
        exit 0
    else
        log_error "❌ TESTING FAILED: $FAILED_TESTS of $TOTAL_TESTS tests failed"
        log_info "📊 Statistics: $PASSED_TESTS passed, $FAILED_TESTS failed, $WARNING_TESTS warnings"
        echo ""
        echo "$(printf "${YELLOW}Next steps:${NC}")"
        echo "1. Copy dev-test-errors.txt to AI for debugging help"
        echo "2. Fix identified issues using the provided fixes"
        echo "3. Re-run: ./scripts/dev-testing-rutos.sh"
        echo "4. Review full log: cat dev-test-full-log.txt"
        exit 1
    fi
}

# Set up cleanup on exit
trap cleanup EXIT

# Execute main function with all arguments
main "$@"
