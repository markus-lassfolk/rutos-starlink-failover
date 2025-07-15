#!/bin/bash
# Pre-commit validation script for RUTOS Starlink Failover Project
# Version: [AUTO-GENERATED]
# Description: Comprehensive validation of all shell scripts for RUTOS/busybox compatibility
# 
# NOTE: This script runs in the development environment (WSL/Linux), NOT on RUTOS,
# so it can use modern bash features for efficiency. It validates OTHER scripts
# for RUTOS compatibility but is excluded from its own validation checks.

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
# Allow colors unless explicitly disabled or in very limited environments
if [ "$NO_COLOR" = "1" ] || [ "$TERM" = "dumb" ] || [ -z "$TERM" ]; then
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

# Debug function for tracking operations (cleaner than set -x)
debug_exec() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "EXECUTING: $*"
    fi
    "$@"
}

# Debug function for tracking variable assignments
debug_var() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "VARIABLE: $1 = $2"
    fi
}

# Debug function for tracking function entry/exit
debug_func() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "FUNCTION: $1"
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
    log_debug "Script version: $SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    # Note: Using clean debug logging instead of set -x for better readability
fi

# Validation counters
TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
TOTAL_ISSUES=0

# Track different types of issues
CRITICAL_ISSUES=0
MAJOR_ISSUES=0
MINOR_ISSUES=0

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to report an issue
report_issue() {
    severity="$1"
    file="$2"
    line="$3"
    message="$4"
    
    case "$severity" in
        "CRITICAL")
            printf "${RED}[CRITICAL]${NC} %s:%s %s\n" "$file" "$line" "$message"
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
            ;;
        "MAJOR")
            printf "${YELLOW}[MAJOR]${NC} %s:%s %s\n" "$file" "$line" "$message"
            MAJOR_ISSUES=$((MAJOR_ISSUES + 1))
            ;;
        "MINOR")
            printf "${BLUE}[MINOR]${NC} %s:%s %s\n" "$file" "$line" "$message"
            MINOR_ISSUES=$((MINOR_ISSUES + 1))
            ;;
    esac
    
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
}

# Function to check shebang compatibility
check_shebang() {
    file="$1"
    shebang=$(head -1 "$file")
    
    case "$shebang" in
        "#!/bin/sh")
            log_debug "✓ $file: Uses POSIX shell shebang"
            return 0
            ;;
        "#!/bin/bash")
            report_issue "MAJOR" "$file" "1" "Uses bash shebang - should use #!/bin/sh for RUTOS compatibility"
            return 1
            ;;
        *)
            if [ -n "$shebang" ]; then
                report_issue "CRITICAL" "$file" "1" "Unknown shebang: $shebang"
            else
                report_issue "CRITICAL" "$file" "1" "Missing shebang"
            fi
            return 1
            ;;
    esac
}

# Function to check bash-specific syntax
check_bash_syntax() {
    local file="$1"
    
    # Array of patterns to check for bash-specific syntax
    declare -A bash_patterns=(
        ["< <("]="CRITICAL:Uses process substitution < <(...) - not supported in busybox, use pipe instead"
        ["\$([^)]*\$([^)]*)"]="MINOR:Nested command substitution - may cause issues in some busybox versions"
        ["\[\["]="CRITICAL:Uses double brackets [[ ]] - use single brackets [ ] for busybox"
        ["declare -[aA]"]="CRITICAL:Uses arrays (declare -a) - not supported in busybox"
        ["\${.*\[@\].*}"]="CRITICAL:Uses array syntax (\${array[@]}) - not supported in busybox"
        ["function.*("]="MAJOR:Uses function() syntax - use function_name() { } for busybox"
        ["^[[:space:]]*local "]="CRITICAL:Uses 'local' keyword - not supported in busybox"
        ["source "]="MAJOR:Uses 'source' command - use '.' (dot) for busybox"
        ["echo -e"]="MAJOR:Uses 'echo -e' - use printf for busybox compatibility"
        ["\$'"]="CRITICAL:Uses \$'...' syntax - not supported in busybox"
        ["<<<"]="CRITICAL:Uses here strings (<<<) - not supported in busybox"
        ["{[0-9]*\.\.[0-9]*}"]="CRITICAL:Uses brace expansion {1..10} - not supported in busybox"
        ["\[\[.*\]\]"]="CRITICAL:Uses [[ ]] conditional expression - not supported in busybox"
        ["\[ .* == .* \]"]="MINOR:Uses == comparison - prefer = for POSIX compliance"
    )
    
    # Check each pattern
    for pattern in "${!bash_patterns[@]}"; do
        local severity="${bash_patterns[$pattern]%%:*}"
        local message="${bash_patterns[$pattern]#*:}"
        
        if grep -n "$pattern" "$file" >/dev/null 2>&1; then
            while IFS=: read -r line_num line_content; do
                report_issue "$severity" "$file" "$line_num" "$message"
            done < <(grep -n "$pattern" "$file" 2>/dev/null)
        fi
    done
    
    return 0
}

# Function to check for RUTOS-specific compatibility issues
check_rutos_compatibility() {
    local file="$1"
    
    # Array of RUTOS-specific compatibility patterns
    declare -A rutos_patterns=(
        ["curl.*-L"]="CRITICAL:Uses curl -L flag - not supported on RUTOS"
        ["stat -[cf]"]="CRITICAL:Uses stat with -c/-f flags - not supported on RUTOS"
        ["trap.* ERR"]="CRITICAL:Uses trap ERR - not supported in busybox, use trap INT TERM"
        ["find.*-maxdepth"]="MINOR:Uses find -maxdepth - may not be supported on all busybox versions"
        ["readlink -f"]="MAJOR:Uses readlink -f - may not be available on RUTOS"
        ["mktemp$"]="MINOR:mktemp without template - may behave differently on busybox"
    )
    
    # Check each pattern
    for pattern in "${!rutos_patterns[@]}"; do
        local severity="${rutos_patterns[$pattern]%%:*}"
        local message="${rutos_patterns[$pattern]#*:}"
        
        if grep -n "$pattern" "$file" >/dev/null 2>&1; then
            while IFS=: read -r line_num line_content; do
                report_issue "$severity" "$file" "$line_num" "$message"
            done < <(grep -n "$pattern" "$file" 2>/dev/null)
        fi
    done
    
    # Special check for bc usage without fallbacks
    if grep -n " bc " "$file" >/dev/null 2>&1; then
        if ! grep -q "bc.*2>/dev/null.*echo" "$file"; then
            while IFS=: read -r line_num line_content; do
                report_issue "MAJOR" "$file" "$line_num" "Uses bc without fallback - may not be available on RUTOS"
            done < <(grep -n " bc " "$file" 2>/dev/null)
        fi
    fi
    
    # Check for dirname/basename without proper quoting
    if grep -n "dirname\|basename" "$file" >/dev/null 2>&1; then
        while IFS=: read -r line_num line_content; do
            if [[ ! "$line_content" =~ \"\$ ]]; then
                report_issue "MINOR" "$file" "$line_num" "dirname/basename should quote variables: dirname \"\$var\""
            fi
        done < <(grep -n "dirname\|basename" "$file" 2>/dev/null)
    fi
    
    # Check for printf format string variables (security issue)
    if grep -n 'printf.*".*\$.*"' "$file" >/dev/null 2>&1; then
        while IFS=: read -r line_num line_content; do
            # Skip if it's our own logging functions that are safe
            if [[ ! "$line_content" =~ printf.*%s.*\$ ]]; then
                report_issue "MAJOR" "$file" "$line_num" "printf with variable in format string - use printf '%s' \"\$var\""
            fi
        done < <(grep -n 'printf.*".*\$.*"' "$file" 2>/dev/null)
    fi
    
    return 0
}

# Function to check for required patterns
check_required_patterns() {
    file="$1"
    
    # Check for version information
    if ! grep -q "SCRIPT_VERSION=" "$file"; then
        report_issue "MINOR" "$file" "0" "Missing SCRIPT_VERSION variable"
    fi
    
    # Check for error handling (set -e)
    if ! grep -q "set -e" "$file"; then
        report_issue "MINOR" "$file" "0" "Missing 'set -e' for error handling"
    fi
    
    # Check for proper function closing braces
    if grep -n "^[a-zA-Z_][a-zA-Z0-9_]*() {" "$file" >/dev/null 2>&1; then
        # For each function definition, check if it has proper closing
        grep -n "^[a-zA-Z_][a-zA-Z0-9_]*() {" "$file" | while IFS=: read -r line_num line_content; do
            function_name=$(echo "$line_content" | sed 's/() {.*//')
            # This is a basic check - could be enhanced with proper brace matching
            if ! grep -A 50 "^$function_name() {" "$file" | grep -q "^}"; then
                report_issue "MAJOR" "$file" "$line_num" "Function $function_name may be missing closing brace"
            fi
        done
    fi
    
    return 0
}

# Function to run ShellCheck if available
run_shellcheck() {
    file="$1"
    
    if ! command_exists shellcheck; then
        log_warning "ShellCheck not available - skipping syntax validation"
        return 0
    fi
    
    # Run shellcheck with POSIX mode
    if shellcheck -s sh "$file" >/dev/null 2>&1; then
        log_debug "✓ $file: Passes ShellCheck validation"
        return 0
    else
        log_warning "$file: ShellCheck found issues"
        return 1
    fi
}

# Function to check formatting with shfmt
check_formatting_with_shfmt() {
    file="$1"
    
    if ! command_exists shfmt; then
        log_debug "shfmt not available - skipping formatting validation"
        return 0
    fi
    
    # Check if file has formatting issues
    if shfmt -d "$file" >/dev/null 2>&1; then
        log_debug "✓ $file: Passes shfmt formatting check"
        return 0
    else
        log_warning "$file: shfmt found formatting issues"
        report_issue "MINOR" "$file" "0" "Code formatting issues found - run 'shfmt -w $file' to fix"
        return 1
    fi
}

# Function to check critical whitespace issues (beyond shfmt)
check_critical_whitespace() {
    file="$1"
    
    # Check for CRLF line endings (Windows line endings) - critical for RUTOS
    if grep -q $'\r' "$file" 2>/dev/null; then
        report_issue "MAJOR" "$file" "0" "Contains CRLF line endings - should use LF for RUTOS compatibility"
    fi
    
    # Check for missing final newline - required by POSIX
    if [ -n "$(tail -c1 "$file" 2>/dev/null)" ]; then
        report_issue "MINOR" "$file" "0" "Missing final newline - files should end with newline"
    fi
}

# Function to validate a single file
validate_file() {
    file="$1"
    debug_func "validate_file($file)"
    
    log_step "Validating: $file"
    
    initial_issues=$TOTAL_ISSUES
    debug_var "initial_issues" "$initial_issues"
    
    # Check shebang
    debug_exec check_shebang "$file"
    
    # Check bash-specific syntax
    debug_exec check_bash_syntax "$file"
    
    # Check RUTOS compatibility
    debug_exec check_rutos_compatibility "$file"
    
    # Check required patterns
    debug_exec check_required_patterns "$file"
    
    # Check whitespace and formatting
    debug_exec check_formatting_with_shfmt "$file"
    debug_exec check_critical_whitespace "$file"
    
    # Run ShellCheck
    if ! debug_exec run_shellcheck "$file"; then
        report_issue "MAJOR" "$file" "0" "ShellCheck found issues"
    fi
    
    # Calculate issues for this file
    file_issues=$((TOTAL_ISSUES - initial_issues))
    debug_var "file_issues" "$file_issues"
    debug_var "TOTAL_ISSUES" "$TOTAL_ISSUES"
    
    if [ $file_issues -eq 0 ]; then
        log_success "✓ $file: All checks passed"
        PASSED_FILES=$((PASSED_FILES + 1))
        debug_var "PASSED_FILES" "$PASSED_FILES"
    else
        log_error "✗ $file: $file_issues issues found"
        FAILED_FILES=$((FAILED_FILES + 1))
        debug_var "FAILED_FILES" "$FAILED_FILES"
    fi
    
    return $file_issues
}

# Function to get staged files for pre-commit
get_staged_files() {
    local files=()
    
    if [[ "$1" == "--staged" ]]; then
        # Get staged shell files, excluding this validation script
        mapfile -t files < <(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' | grep -v "pre-commit-validation.sh" || true)
    else
        # Get all shell files, excluding this validation script
        mapfile -t files < <(find . -type f -name "*.sh" | grep -v ".git" | grep -v "pre-commit-validation.sh" | sort)
    fi
    
    printf '%s\n' "${files[@]}"
}

# Function to display summary
display_summary() {
    debug_func "display_summary()"
    debug_var "TOTAL_FILES" "$TOTAL_FILES"
    debug_var "PASSED_FILES" "$PASSED_FILES"
    debug_var "FAILED_FILES" "$FAILED_FILES"
    debug_var "TOTAL_ISSUES" "$TOTAL_ISSUES"
    debug_var "CRITICAL_ISSUES" "$CRITICAL_ISSUES"
    debug_var "MAJOR_ISSUES" "$MAJOR_ISSUES"
    debug_var "MINOR_ISSUES" "$MINOR_ISSUES"
    
    echo ""
    log_step "==================== VALIDATION SUMMARY ===================="
    
    printf "${BLUE}📊 Files Processed:${NC} %d\n" "$TOTAL_FILES"
    printf "${GREEN}✅ Passed:${NC} %d\n" "$PASSED_FILES"
    printf "${RED}❌ Failed:${NC} %d\n" "$FAILED_FILES"
    
    echo ""
    printf "${PURPLE}🔍 Issues Found:${NC} %d\n" "$TOTAL_ISSUES"
    printf "${RED}🚨 Critical:${NC} %d\n" "$CRITICAL_ISSUES"
    printf "${YELLOW}⚠️  Major:${NC} %d\n" "$MAJOR_ISSUES"
    printf "${BLUE}📝 Minor:${NC} %d\n" "$MINOR_ISSUES"
    
    echo ""
    
    if [ $TOTAL_ISSUES -eq 0 ]; then
        log_success "🎉 All files passed validation! Ready for commit."
        return 0
    else
        if [ $CRITICAL_ISSUES -gt 0 ]; then
            log_error "❌ Critical issues found. These MUST be fixed before committing."
            return 1
        elif [ $MAJOR_ISSUES -gt 0 ]; then
            log_warning "⚠️ Major issues found. Consider fixing before committing."
            return 1
        else
            log_info "ℹ️ Minor issues found. Consider fixing for better code quality."
            return 0
        fi
    fi
}

# Main function
main() {
    debug_func "main()"
    log_info "Starting RUTOS busybox compatibility validation v$SCRIPT_VERSION"
    
    # Self-validation is skipped since this script is excluded from checks
    log_step "Self-validation: Skipped - this script is excluded from validation"
    local self_issues=0
    debug_var "self_issues" "$self_issues"
    
    # Check if running as pre-commit hook or with specific files
    local files
    
    if [[ "$1" == "--staged" ]]; then
        log_info "Running in pre-commit mode (staged files only)"
        debug_exec mapfile -t files < <(get_staged_files --staged)
    elif [[ $# -gt 0 ]]; then
        log_info "Running in specific file mode"
        files=("$@")
        debug_var "files" "${files[*]}"
    else
        log_info "Running in full validation mode (all files)"
        debug_exec mapfile -t files < <(get_staged_files)
    fi
    
    debug_var "files_found" "${#files[@]}"
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warning "No shell files found to validate"
        return $self_issues
    fi
    
    # Validate each file
    log_step "Processing ${#files[@]} files"
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            ((TOTAL_FILES++))
            debug_var "current_file" "$file"
            debug_var "TOTAL_FILES" "$TOTAL_FILES"
            validate_file "$file"
        else
            log_debug "Skipping non-existent file: $file"
        fi
    done
    
    # Display summary
    log_step "Generating validation summary"
    if ! display_summary; then
        return 1
    fi
    
    return $self_issues
}

# Execute main function
main "$@"
