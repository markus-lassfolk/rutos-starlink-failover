#!/bin/sh
# Script: quality-check.sh
# Version: 1.0.2+182.8230f46
# Description: Pre-commit quality checks for shell scripts

set -e

# Colors for output (if supported)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    NC=""
fi

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Run a quality check
run_check() {
    check_name="$1"
    check_command="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    printf "\n=== %s ===\n" "$check_name"
    
    if eval "$check_command"; then
        log_info "✅ $check_name: PASSED"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        log_error "❌ $check_name: FAILED"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# ShellCheck validation
check_shellcheck() {
    if ! command_exists shellcheck; then
        log_warning "ShellCheck not installed. Install with: sudo apt-get install shellcheck"
        return 1
    fi
    
    # Find all shell scripts
    shell_scripts=$(find . -name "*.sh" -type f | grep -v ".git" | head -20)
    
    if [ -z "$shell_scripts" ]; then
        log_warning "No shell scripts found"
        return 1
    fi
    
    shellcheck_failed=0
    
    printf "Checking shell scripts with ShellCheck...\n"
    for script in $shell_scripts; do
        printf "  Checking: %s\n" "$script"
        if ! shellcheck "$script"; then
            log_error "ShellCheck failed for: $script"
            shellcheck_failed=1
        fi
    done
    
    if [ $shellcheck_failed -eq 0 ]; then
        log_info "All shell scripts passed ShellCheck"
        return 0
    else
        log_error "Some shell scripts failed ShellCheck"
        return 1
    fi
}

# Check for bash-specific syntax
check_bash_syntax() {
    bash_issues=0
    
    # Check for common bash-isms
    if grep -r "\[\[" scripts/ Starlink-RUTOS-Failover/ 2>/dev/null; then
        log_error "Found [[ ]] syntax (use [ ] instead)"
        bash_issues=1
    fi
    
    if grep -r "function.*(" scripts/ Starlink-RUTOS-Failover/ 2>/dev/null; then
        log_error "Found function() syntax (use func_name() instead)"
        bash_issues=1
    fi
    
    if grep -r "local " scripts/ Starlink-RUTOS-Failover/ 2>/dev/null; then
        log_error "Found 'local' keyword (not supported in busybox)"
        bash_issues=1
    fi
    
    if grep -r "echo -e" scripts/ Starlink-RUTOS-Failover/ 2>/dev/null; then
        log_error "Found 'echo -e' (use printf instead)"
        bash_issues=1
    fi
    
    if grep -r "source " scripts/ Starlink-RUTOS-Failover/ 2>/dev/null; then
        log_error "Found 'source' command (use . instead)"
        bash_issues=1
    fi
    
    if [ $bash_issues -eq 0 ]; then
        log_info "No bash-specific syntax found"
        return 0
    else
        log_error "Found bash-specific syntax that won't work on busybox"
        return 1
    fi
}

# Check version consistency
check_version_consistency() {
    if [ ! -f "VERSION" ]; then
        log_error "VERSION file not found"
        return 1
    fi
    
    version=$(cat VERSION)
    log_info "Current version: $version"
    
    # Check if scripts contain version information
    scripts_without_version=0
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            if ! grep -q "SCRIPT_VERSION=" "$script"; then
                log_error "Script missing version: $script"
                scripts_without_version=1
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

# Check for function closing braces
check_function_braces() {
    brace_issues=0
    
    # This is a simplified check - in practice, this would be more complex
    for script in scripts/*.sh Starlink-RUTOS-Failover/*.sh; do
        if [ -f "$script" ]; then
            # Check for functions without proper closing
            if awk '/^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/{func=1} /^}$/{if(func) func=0} END{if(func) exit 1}' "$script" 2>/dev/null; then
                : # Function check passed
            else
                log_error "Potential function brace issue in: $script"
                brace_issues=1
            fi
        fi
    done
    
    if [ $brace_issues -eq 0 ]; then
        log_info "Function braces appear correct"
        return 0
    else
        log_error "Potential function brace issues found"
        return 1
    fi
}

# Check template files
check_templates() {
    template_issues=0
    
    # Check for ShellCheck comments in templates
    for template in config/*.template.sh; do
        if [ -f "$template" ]; then
            if grep -q "shellcheck" "$template"; then
                log_error "Template contains ShellCheck comments: $template"
                template_issues=1
            fi
        fi
    done
    
    if [ $template_issues -eq 0 ]; then
        log_info "Templates are clean"
        return 0
    else
        log_error "Template issues found"
        return 1
    fi
}

# Main execution
main() {
    printf "\n"
    printf "==========================================\n"
    printf "    RUTOS Starlink Failover Quality Check\n"
    printf "==========================================\n"
    
    # Run all quality checks
    run_check "ShellCheck Validation" "check_shellcheck"
    run_check "Bash Syntax Check" "check_bash_syntax"
    run_check "Version Consistency" "check_version_consistency"
    run_check "Function Braces" "check_function_braces"
    run_check "Template Validation" "check_templates"
    
    # Summary
    printf "\n"
    printf "==========================================\n"
    printf "                SUMMARY\n"
    printf "==========================================\n"
    printf "Total Checks: %d\n" "$TOTAL_CHECKS"
    printf "${GREEN}Passed: %d${NC}\n" "$PASSED_CHECKS"
    printf "${RED}Failed: %d${NC}\n" "$FAILED_CHECKS"
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        printf "\n${GREEN}🎉 All quality checks passed! Ready to commit.${NC}\n"
        exit 0
    else
        printf "\n${RED}❌ Quality checks failed. Please fix issues before committing.${NC}\n"
        exit 1
    fi
}

# Execute main function
main "$@"
