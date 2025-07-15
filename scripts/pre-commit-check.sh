#!/bin/sh
# Script: pre-commit-check.sh
# Version: 1.0.0
# Description: Comprehensive pre-commit validation script for RUTOS/Busybox compatibility

set -e  # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.0"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
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

# Debug mode support
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    set -x  # Enable command tracing
fi

# Global counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
TOTAL_SCRIPTS=0

# Configuration
CHECK_LEVEL="comprehensive"  # Default to comprehensive checks

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Comprehensive pre-commit validation script for RUTOS/Busybox compatibility.

OPTIONS:
    --quick            Run quick syntax checks only
    --comprehensive    Run all validation checks (default)
    --help            Show this help message
    --version         Show script version

ENVIRONMENT VARIABLES:
    DEBUG=1           Enable debug mode with verbose output

EXAMPLES:
    $0                      # Run comprehensive checks
    $0 --quick             # Run quick syntax checks only
    DEBUG=1 $0             # Run with debug output
    $0 --comprehensive     # Run all validation checks

EXIT CODES:
    0    All checks passed
    1    Validation failures found
    2    Script error or missing dependencies

EOF
}

# Parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case $1 in
            --quick)
                CHECK_LEVEL="quick"
                log_debug "Set check level to quick"
                shift
                ;;
            --comprehensive)
                CHECK_LEVEL="comprehensive"
                log_debug "Set check level to comprehensive"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            --version)
                printf "pre-commit-check.sh version %s\n" "$SCRIPT_VERSION"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 2
                ;;
        esac
    done
}

# Run a validation check
run_check() {
    check_name="$1"
    check_function="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    log_step "Running $check_name"
    
    if $check_function; then
        log_success "$check_name: PASSED"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        log_error "$check_name: FAILED"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# Check for required dependencies
check_dependencies() {
    dependencies_ok=1
    
    if ! command_exists shellcheck; then
        log_error "ShellCheck not found. Install with: sudo apt-get install shellcheck"
        dependencies_ok=0
    fi
    
    if ! command_exists find; then
        log_error "find command not found"
        dependencies_ok=0
    fi
    
    if ! command_exists grep; then
        log_error "grep command not found"
        dependencies_ok=0
    fi
    
    if [ $dependencies_ok -eq 0 ]; then
        log_error "Missing required dependencies"
        return 1
    fi
    
    log_debug "All dependencies are available"
    return 0
}

# Find all shell scripts in the repository
find_shell_scripts() {
    log_debug "Finding shell scripts in repository"
    
    # Find all .sh files, excluding .git directory and temporary files
    find . -name "*.sh" -type f ! -path "./.git/*" ! -name "*.tmp" | sort
}

# Check ShellCheck validation
check_shellcheck() {
    log_debug "Running ShellCheck validation"
    
    if ! command_exists shellcheck; then
        log_error "ShellCheck not installed"
        return 1
    fi
    
    shell_scripts=$(find_shell_scripts)
    
    if [ -z "$shell_scripts" ]; then
        log_warning "No shell scripts found"
        return 1
    fi
    
    shellcheck_failed=0
    script_count=0
    
    for script in $shell_scripts; do
        script_count=$((script_count + 1))
        log_debug "Checking script: $script"
        
        if ! shellcheck "$script"; then
            log_error "ShellCheck failed for: $script"
            shellcheck_failed=1
        else
            log_debug "ShellCheck passed for: $script"
        fi
    done
    
    TOTAL_SCRIPTS=$script_count
    log_debug "Checked $script_count scripts"
    
    if [ $shellcheck_failed -eq 0 ]; then
        log_info "All $script_count scripts passed ShellCheck"
        return 0
    else
        log_error "Some scripts failed ShellCheck validation"
        return 1
    fi
}

# Check for POSIX shell compatibility (Critical RUTOS requirements)
check_posix_compatibility() {
    log_debug "Checking POSIX shell compatibility"
    
    shell_scripts=$(find_shell_scripts)
    compatibility_issues=0
    
    for script in $shell_scripts; do
        # Skip validation scripts to avoid false positives from their own pattern matching
        script_basename=$(basename "$script")
        if [ "$script_basename" = "pre-commit-check.sh" ] || [ "$script_basename" = "quality-check.sh" ] || [ "$script_basename" = "audit-rutos-compatibility.sh" ]; then
            log_debug "Skipping validation for $script (validation script)"
            continue
        fi
        
        log_debug "Checking POSIX compatibility for: $script"
        
        # Check for double brackets [[ ]] in actual code (not comments or strings)
        if grep -n "^[[:space:]]*if.*\\[\\[" "$script" > /dev/null 2>&1 || grep -n "^[[:space:]]*elif.*\\[\\[" "$script" > /dev/null 2>&1 || grep -n "^[[:space:]]*while.*\\[\\[" "$script" > /dev/null 2>&1; then
            log_error "CRITICAL: Double brackets found in $script:"
            grep -n "^[[:space:]]*\\(if\\|elif\\|while\\).*\\[\\[" "$script" | while read -r line; do
                log_error "  Line: $line"
            done
            compatibility_issues=1
        fi
        
        # Check for function() syntax (not in comments or strings)
        if grep -n "^[[:space:]]*function.*(" "$script" > /dev/null 2>&1; then
            log_error "CRITICAL: function() syntax found in $script:"
            grep -n "^[[:space:]]*function.*(" "$script" | while read -r line; do
                log_error "  Line: $line"
            done
            compatibility_issues=1
        fi
        
        # Check for local variables (not in comments or strings)
        if grep -n "^[[:space:]]*local " "$script" > /dev/null 2>&1; then
            log_error "CRITICAL: 'local' keyword found in $script:"
            grep -n "^[[:space:]]*local " "$script" | while read -r line; do
                log_error "  Line: $line"
            done
            compatibility_issues=1
        fi
        
        # Check for echo -e usage (not in comments or strings)
        if grep -n "^[[:space:]]*echo -e" "$script" > /dev/null 2>&1; then
            log_error "CRITICAL: 'echo -e' found in $script:"
            grep -n "^[[:space:]]*echo -e" "$script" | while read -r line; do
                log_error "  Line: $line"
            done
            compatibility_issues=1
        fi
        
        # Check for source command (not in comments or strings)
        if grep -n "^[[:space:]]*source " "$script" > /dev/null 2>&1; then
            log_error "CRITICAL: 'source' command found in $script:"
            grep -n "^[[:space:]]*source " "$script" | while read -r line; do
                log_error "  Line: $line"
            done
            compatibility_issues=1
        fi
        
        # Check for bash arrays
        if grep -n "\${.*\[@\].*}" "$script" > /dev/null 2>&1; then
            log_error "CRITICAL: Bash array syntax found in $script:"
            grep -n "\${.*\[@\].*}" "$script" | while read -r line; do
                log_error "  Line: $line"
            done
            compatibility_issues=1
        fi
        
        # Check for $'\n' syntax
        if grep -n "\$'.*\\n.*'" "$script" > /dev/null 2>&1; then
            log_error "CRITICAL: \$'\\n' syntax found in $script:"
            grep -n "\$'.*\\n.*'" "$script" | while read -r line; do
                log_error "  Line: $line"
            done
            compatibility_issues=1
        fi
    done
    
    if [ $compatibility_issues -eq 0 ]; then
        log_info "All scripts are POSIX compatible"
        return 0
    else
        log_error "POSIX compatibility issues found"
        return 1
    fi
}

# Check shell script syntax
check_syntax() {
    log_debug "Checking shell script syntax"
    
    shell_scripts=$(find_shell_scripts)
    syntax_errors=0
    
    for script in $shell_scripts; do
        log_debug "Checking syntax for: $script"
        
        # Check with sh -n
        if ! sh -n "$script" 2>/dev/null; then
            log_error "Syntax error in $script:"
            sh -n "$script" 2>&1 | while read -r line; do
                log_error "  $line"
            done
            syntax_errors=1
        else
            log_debug "Syntax OK for: $script"
        fi
    done
    
    if [ $syntax_errors -eq 0 ]; then
        log_info "All scripts have valid syntax"
        return 0
    else
        log_error "Syntax errors found in scripts"
        return 1
    fi
}

# Check configuration template format
check_template_format() {
    log_debug "Checking configuration template format"
    
    template_issues=0
    
    # Check for template files
    for template in config/*.template.sh; do
        if [ -f "$template" ]; then
            log_debug "Checking template: $template"
            
            # Check for ShellCheck comments in templates
            if grep -n "shellcheck" "$template" > /dev/null 2>&1; then
                log_error "ShellCheck comments found in template: $template"
                grep -n "shellcheck" "$template" | while read -r line; do
                    log_error "  Line: $line"
                done
                template_issues=1
            fi
            
            # Check for proper variable format
            if grep -n "^[A-Z_][A-Z0-9_]*=" "$template" > /dev/null 2>&1; then
                # Check if variables use default syntax
                grep -n "^[A-Z_][A-Z0-9_]*=" "$template" | while read -r line; do
                    var_line=$(printf "%s" "$line" | cut -d: -f2-)
                    if ! printf "%s" "$var_line" | grep -q "\${.*:-.*}"; then
                        log_warning "Variable without default in $template: $var_line"
                    fi
                done
            fi
        fi
    done
    
    if [ $template_issues -eq 0 ]; then
        log_info "Configuration templates are properly formatted"
        return 0
    else
        log_error "Template format issues found"
        return 1
    fi
}

# Check version consistency
check_version_consistency() {
    log_debug "Checking version consistency"
    
    if [ ! -f "VERSION" ]; then
        log_error "VERSION file not found"
        return 1
    fi
    
    version=$(cat VERSION)
    log_debug "Current version: $version"
    
    # Check if scripts contain version information
    scripts_without_version=0
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            if ! grep -q "SCRIPT_VERSION=" "$script"; then
                log_error "Script missing version: $script"
                scripts_without_version=1
            else
                log_debug "Version found in: $script"
            fi
        fi
    done
    
    if [ $scripts_without_version -eq 0 ]; then
        log_info "All scripts have version information"
        return 0
    else
        log_error "Some scripts missing version information"
        return 1
    fi
}

# Check function structure and braces
check_function_structure() {
    log_debug "Checking function structure and braces"
    
    shell_scripts=$(find_shell_scripts)
    function_issues=0
    
    for script in $shell_scripts; do
        log_debug "Checking function structure in: $script"
        
        # Check for proper function definition format
        if grep -n "^[a-zA-Z_][a-zA-Z0-9_]*() {" "$script" > /dev/null 2>&1; then
            log_debug "Found properly formatted functions in: $script"
        fi
        
        # Check for potential unclosed functions (simplified check)
        # This is a basic check - more sophisticated parsing would be needed for complete validation
        function_count=$(grep -c "^[a-zA-Z_][a-zA-Z0-9_]*() {" "$script" 2>/dev/null || echo "0")
        brace_count=$(grep -c "^}" "$script" 2>/dev/null || echo "0")
        
        if [ "$function_count" -gt 0 ] && [ "$brace_count" -lt "$function_count" ]; then
            log_warning "Potential unclosed function in $script (functions: $function_count, closing braces: $brace_count)"
        fi
    done
    
    if [ $function_issues -eq 0 ]; then
        log_info "Function structures appear correct"
        return 0
    else
        log_error "Function structure issues found"
        return 1
    fi
}

# Check for required logging functions
check_logging_functions() {
    log_debug "Checking for required logging functions"
    
    shell_scripts=$(find_shell_scripts)
    logging_issues=0
    
    for script in $shell_scripts; do
        # Skip this script itself
        if [ "$script" = "./scripts/pre-commit-check.sh" ]; then
            continue
        fi
        
        log_debug "Checking logging functions in: $script"
        
        # Check if script has logging functions (if it's a main script)
        if [ -f "$script" ] && head -10 "$script" | grep -q "#!/bin/sh"; then
            if grep -q "log_info\|log_error\|log_warning" "$script"; then
                log_debug "Logging functions found in: $script"
            elif grep -q "printf.*INFO\|printf.*ERROR\|printf.*WARNING" "$script"; then
                log_debug "Basic logging found in: $script"
            else
                # Only warn for main scripts (not test scripts)
                if ! printf "%s" "$script" | grep -q "test-"; then
                    log_warning "No logging functions found in: $script"
                fi
            fi
        fi
    done
    
    if [ $logging_issues -eq 0 ]; then
        log_info "Logging function check completed"
        return 0
    else
        log_error "Logging function issues found"
        return 1
    fi
}

# Check file naming conventions
check_naming_conventions() {
    log_debug "Checking file naming conventions"
    
    shell_scripts=$(find_shell_scripts)
    naming_issues=0
    
    for script in $shell_scripts; do
        script_name=$(basename "$script")
        
        # Check for kebab-case naming in scripts directory
        if printf "%s" "$script" | grep -q "^./scripts/"; then
            if ! printf "%s" "$script_name" | grep -q "^[a-z0-9-]*\.sh$"; then
                log_warning "Script not in kebab-case: $script"
                naming_issues=1
            else
                log_debug "Proper naming: $script"
            fi
        fi
    done
    
    if [ "$naming_issues" -eq 0 ]; then
        log_info "File naming conventions are correct"
        return 0
    else
        log_warning "File naming convention issues found"
        return 0  # Don't fail on naming issues, just warn
    fi
}

# Print summary
print_summary() {
    printf "\n"
    printf "${PURPLE}==========================================\n"
    printf "           VALIDATION SUMMARY\n"
    printf "==========================================${NC}\n"
    printf "Check Level: %s\n" "$CHECK_LEVEL"
    printf "Total Scripts: %s\n" "$TOTAL_SCRIPTS"
    printf "Total Checks: %s\n" "$TOTAL_CHECKS"
    printf "${GREEN}Passed: %s${NC}\n" "$PASSED_CHECKS"
    printf "${RED}Failed: %s${NC}\n" "$FAILED_CHECKS"
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        printf "\n${GREEN}🎉 All validation checks passed! Ready to commit.${NC}\n"
        printf "${GREEN}Your code is compatible with RUTOS/Busybox systems.${NC}\n"
    else
        printf "\n${RED}❌ Validation checks failed. Please fix issues before committing.${NC}\n"
        printf "${YELLOW}Focus on CRITICAL issues first - they will prevent RUTOS compatibility.${NC}\n"
        printf "${BLUE}Run with DEBUG=1 for more detailed output.${NC}\n"
    fi
}

# Main execution function
main() {
    log_info "Starting pre-commit-check.sh v$SCRIPT_VERSION"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate environment
    if [ ! -f ".git/config" ]; then
        log_error "This script must be run from the repository root"
        exit 2
    fi
    
    log_step "Validating environment"
    if ! check_dependencies; then
        log_error "Dependency check failed"
        exit 2
    fi
    
    printf "\n${PURPLE}==========================================\n"
    printf "    RUTOS Pre-Commit Validation\n"
    printf "==========================================${NC}\n"
    printf "Mode: %s\n" "$CHECK_LEVEL"
    printf "Debug: %s\n" "$DEBUG"
    printf "\n"
    
    # Always run critical checks
    run_check "Shell Script Syntax" "check_syntax"
    run_check "POSIX Compatibility (CRITICAL)" "check_posix_compatibility"
    
    if [ "$CHECK_LEVEL" = "quick" ]; then
        log_info "Quick check completed"
    else
        # Comprehensive checks
        run_check "ShellCheck Validation" "check_shellcheck"
        run_check "Configuration Template Format" "check_template_format"
        run_check "Version Consistency" "check_version_consistency"
        run_check "Function Structure" "check_function_structure"
        run_check "Logging Functions" "check_logging_functions"
        run_check "File Naming Conventions" "check_naming_conventions"
    fi
    
    # Print summary
    print_summary
    
    # Exit with appropriate code
    if [ $FAILED_CHECKS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"