#!/bin/bash
# Comprehensive Code Quality Validation Script
# Version: 2.4.12
# Description: Multi-language code quality validation for RUTOS Starlink Failover Project
#              Includes all RUTOS/busybox compatibility checks from pre-commit-validation.sh
#
# This script validates code quality across multiple languages:
# - Shell scripts (ShellCheck, shfmt, RUTOS/busybox compatibility)
# - Python files (black, flake8, pylint, mypy, isort, bandit)
# - PowerShell files (PSScriptAnalyzer)
# - Markdown files (markdownlint)
# - JSON/YAML files (jq, yamllint, prettier)
# - Bicep files (bicep lint)

set -e

# Version information
# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.6.0"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.4.11"

# Standard colors for consistent output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
# shellcheck disable=SC2034  # PURPLE is part of standard color palette
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ "$NO_COLOR" = "1" ] || [ "$TERM" = "dumb" ] || [ -z "$TERM" ] || { [ ! -t 1 ] && [ ! -t 2 ]; }; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    # shellcheck disable=SC2034  # PURPLE is part of standard color palette
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

# Global counters
TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
SKIPPED_FILES=0

# Tool availability tracking
declare -A TOOLS_AVAILABLE

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check tool availability
check_tool_availability() {
    local tool_name="$1"
    local command_name="$2"
    local install_info="$3"

    if command_exists "$command_name"; then
        TOOLS_AVAILABLE["$tool_name"]=true
        log_debug "✅ $tool_name is available"
        return 0
    else
        TOOLS_AVAILABLE["$tool_name"]=false
        log_warning "❌ $tool_name not found. Install: $install_info"
        return 1
    fi
}

# Function to initialize tool availability
initialize_tools() {
    log_step "Checking tool availability"

    # Shell tools
    check_tool_availability "shellcheck" "shellcheck" "apt-get install shellcheck || brew install shellcheck" || true
    check_tool_availability "shfmt" "shfmt" "apt-get install shfmt || go install mvdan.cc/sh/v3/cmd/shfmt@latest" || true

    # Python tools
    check_tool_availability "black" "black" "pip install black" || true
    check_tool_availability "flake8" "flake8" "pip install flake8" || true
    check_tool_availability "pylint" "pylint" "pip install pylint" || true
    check_tool_availability "mypy" "mypy" "pip install mypy" || true
    check_tool_availability "isort" "isort" "pip install isort" || true
    check_tool_availability "bandit" "bandit" "pip install bandit" || true

    # PowerShell tools (check if pwsh is available)
    check_tool_availability "pwsh" "pwsh" "Install PowerShell Core" || true

    # Markdown tools
    check_tool_availability "markdownlint" "markdownlint" "npm install -g markdownlint-cli" || true

    # JSON/YAML tools
    check_tool_availability "jq" "jq" "apt-get install jq || brew install jq" || true
    check_tool_availability "yamllint" "yamllint" "pip install yamllint" || true
    check_tool_availability "prettier" "prettier" "npm install -g prettier" || true

    # Bicep tools
    check_tool_availability "bicep" "bicep" "Install Azure Bicep CLI" || true

    log_info "Tool availability check completed"
}

# Function to check RUTOS/busybox compatibility for shell scripts
check_rutos_compatibility() {
    local file="$1"
    local issues=0

    # Check shebang compatibility
    local shebang
    shebang=$(head -1 "$file")
    case "$shebang" in
        "#!/bin/sh")
            log_debug "✓ $file: Uses POSIX shell shebang"
            ;;
        "#!/bin/bash")
            log_error "Uses bash shebang - should use #!/bin/sh for RUTOS compatibility"
            issues=$((issues + 1))
            ;;
        *)
            if [ -n "$shebang" ]; then
                log_error "Unknown shebang: $shebang"
            else
                log_error "Missing shebang"
            fi
            issues=$((issues + 1))
            ;;
    esac

    # Check for double brackets (bash-style conditions)
    if grep -n "if[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
        log_error "Uses double brackets [[ ]] - use single brackets [ ] for busybox"
        issues=$((issues + 1))
    fi

    if grep -n "while[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
        log_error "Uses double brackets [[ ]] in while loop - use single brackets [ ] for busybox"
        issues=$((issues + 1))
    fi

    # Check for standalone double bracket conditions
    if grep -n "^[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
        while IFS=: read -r line_num line_content; do
            # Skip if it's a POSIX character class like [[:space:]]
            if ! echo "$line_content" | grep -q "\[\[:[a-z]*:\]\]"; then
                log_error "Line $line_num: Uses double brackets [[ ]] - use single brackets [ ] for busybox"
                issues=$((issues + 1))
            fi
        done < <(grep -n "^[[:space:]]*\[\[.*\]\]" "$file" 2>/dev/null)
    fi

    # Check for local keyword
    if grep -n "^[[:space:]]*local " "$file" >/dev/null 2>&1; then
        log_error "Uses 'local' keyword - not supported in busybox"
        issues=$((issues + 1))
    fi

    # Check for echo -e
    if grep -n "echo -e" "$file" >/dev/null 2>&1; then
        log_error "Uses 'echo -e' - use printf for busybox compatibility"
        issues=$((issues + 1))
    fi

    # Check for source command (but not in echo statements)
    if grep -n "source " "$file" >/dev/null 2>&1; then
        while IFS=: read -r line_num line_content; do
            # Skip if it's within an echo statement (documentation)
            if ! echo "$line_content" | grep -q "echo.*source"; then
                log_error "Line $line_num: Uses 'source' command - use '.' (dot) for busybox"
                issues=$((issues + 1))
            fi
        done < <(grep -n "source " "$file" 2>/dev/null)
    fi

    # Check for arrays
    if grep -n "declare -[aA]" "$file" >/dev/null 2>&1; then
        log_error "Uses arrays (declare -a) - not supported in busybox"
        issues=$((issues + 1))
    fi

    # Check for function() syntax
    if grep -n "^[[:space:]]*function[[:space:]]\+[[:alnum:]_]\+[[:space:]]*(" "$file" >/dev/null 2>&1; then
        log_error "Uses function() syntax - use function_name() { } for busybox"
        issues=$((issues + 1))
    fi

    # Check for hardcoded color codes in printf statements
    if grep -n "printf.*\\\\033\[" "$file" >/dev/null 2>&1; then
        log_warning "Uses hardcoded color codes in printf - use color variables instead"
        issues=$((issues + 1))
    fi

    # Check for echo with color codes
    if grep -n "echo.*\\\\033\[" "$file" >/dev/null 2>&1; then
        log_warning "Uses echo with color codes - use printf for better compatibility"
        issues=$((issues + 1))
    fi

    # Check for proper color detection logic
    if grep -n "RED=\|GREEN=\|YELLOW=" "$file" >/dev/null 2>&1; then
        if ! grep -q "if.*-t.*1\|NO_COLOR\|TERM.*dumb" "$file"; then
            log_warning "Defines colors but missing color detection logic - add terminal/NO_COLOR checks"
            issues=$((issues + 1))
        fi
    fi

    return $issues
}

# Function to validate shell scripts with RUTOS compatibility
validate_shell_scripts() {
    local files=("$@")
    local shell_issues=0

    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    log_step "Validating ${#files[@]} shell script(s) with RUTOS compatibility"

    for file in "${files[@]}"; do
        TOTAL_FILES=$((TOTAL_FILES + 1))
        local file_issues=0

        log_info "Validating shell script: $file"

        # RUTOS/busybox compatibility checks
        if ! check_rutos_compatibility "$file"; then
            file_issues=$((file_issues + $?))
        fi

        # ShellCheck validation
        if [ "${TOOLS_AVAILABLE[shellcheck]}" = "true" ]; then
            if ! shellcheck -s sh "$file"; then
                log_error "ShellCheck failed for $file"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping ShellCheck validation (not available)"
        fi

        # shfmt validation (use 4 spaces and case indentation to match repository standard)
        if [ "${TOOLS_AVAILABLE[shfmt]}" = "true" ]; then
            if ! shfmt -i 4 -ci -d "$file"; then
                log_error "shfmt formatting issues in $file"
                log_info "Run 'shfmt -i 4 -ci -w $file' to fix formatting"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping shfmt validation (not available)"
        fi

        if [ $file_issues -eq 0 ]; then
            PASSED_FILES=$((PASSED_FILES + 1))
            log_success "✅ $file passed validation"
        else
            FAILED_FILES=$((FAILED_FILES + 1))
            shell_issues=$((shell_issues + file_issues))
        fi
    done

    return $shell_issues
}

# Function to validate Python files
validate_python_files() {
    local files=("$@")
    local python_issues=0

    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    log_step "Validating ${#files[@]} Python file(s)"

    for file in "${files[@]}"; do
        TOTAL_FILES=$((TOTAL_FILES + 1))
        local file_issues=0

        log_info "Validating Python file: $file"

        # Black code formatting
        if [ "${TOOLS_AVAILABLE[black]}" = "true" ]; then
            if ! black --check "$file"; then
                log_error "Black formatting issues in $file"
                log_info "Run 'black $file' to fix formatting"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping black validation (not available)"
        fi

        # isort import sorting
        if [ "${TOOLS_AVAILABLE[isort]}" = "true" ]; then
            if ! isort --check-only "$file"; then
                log_error "isort import issues in $file"
                log_info "Run 'isort $file' to fix imports"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping isort validation (not available)"
        fi

        # flake8 style guide
        if [ "${TOOLS_AVAILABLE[flake8]}" = "true" ]; then
            if ! flake8 "$file"; then
                log_error "flake8 style issues in $file"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping flake8 validation (not available)"
        fi

        # pylint comprehensive analysis
        if [ "${TOOLS_AVAILABLE[pylint]}" = "true" ]; then
            if ! pylint "$file" --score=no; then
                log_error "pylint issues in $file"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping pylint validation (not available)"
        fi

        # mypy type checking
        if [ "${TOOLS_AVAILABLE[mypy]}" = "true" ]; then
            if ! mypy "$file"; then
                log_error "mypy type issues in $file"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping mypy validation (not available)"
        fi

        # bandit security scanning
        if [ "${TOOLS_AVAILABLE[bandit]}" = "true" ]; then
            if ! bandit -r "$file"; then
                log_error "bandit security issues in $file"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping bandit validation (not available)"
        fi

        if [ $file_issues -eq 0 ]; then
            PASSED_FILES=$((PASSED_FILES + 1))
            log_success "✅ $file passed validation"
        else
            FAILED_FILES=$((FAILED_FILES + 1))
            python_issues=$((python_issues + file_issues))
        fi
    done

    return $python_issues
}

# Function to validate PowerShell files
validate_powershell_files() {
    local files=("$@")
    local ps_issues=0

    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    log_step "Validating ${#files[@]} PowerShell file(s)"

    for file in "${files[@]}"; do
        TOTAL_FILES=$((TOTAL_FILES + 1))
        local file_issues=0

        log_info "Validating PowerShell file: $file"

        # PSScriptAnalyzer validation
        if [ "${TOOLS_AVAILABLE[pwsh]}" = "true" ]; then
            if ! pwsh -Command "Invoke-ScriptAnalyzer -Path '$file' -Severity Warning,Error"; then
                log_error "PSScriptAnalyzer issues in $file"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping PowerShell validation (pwsh not available)"
        fi

        if [ $file_issues -eq 0 ]; then
            PASSED_FILES=$((PASSED_FILES + 1))
            log_success "✅ $file passed validation"
        else
            FAILED_FILES=$((FAILED_FILES + 1))
            ps_issues=$((ps_issues + file_issues))
        fi
    done

    return $ps_issues
}

# Function to validate Markdown files
validate_markdown_files() {
    local files=("$@")
    local md_issues=0

    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    log_step "Validating ${#files[@]} Markdown file(s)"

    for file in "${files[@]}"; do
        TOTAL_FILES=$((TOTAL_FILES + 1))
        local file_issues=0

        log_info "Validating Markdown file: $file"

        # markdownlint validation
        if [ "${TOOLS_AVAILABLE[markdownlint]}" = "true" ]; then
            if ! markdownlint "$file"; then
                log_error "markdownlint issues in $file"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping markdownlint validation (not available)"
        fi

        # prettier formatting
        if [ "${TOOLS_AVAILABLE[prettier]}" = "true" ]; then
            if ! prettier --check "$file"; then
                log_error "prettier formatting issues in $file"
                log_info "Run 'prettier --write $file' to fix formatting"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping prettier validation (not available)"
        fi

        if [ $file_issues -eq 0 ]; then
            PASSED_FILES=$((PASSED_FILES + 1))
            log_success "✅ $file passed validation"
        else
            FAILED_FILES=$((FAILED_FILES + 1))
            md_issues=$((md_issues + file_issues))
        fi
    done

    return $md_issues
}

# Function to validate JSON/YAML files
validate_json_yaml_files() {
    local files=("$@")
    local config_issues=0

    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    log_step "Validating ${#files[@]} JSON/YAML file(s)"

    for file in "${files[@]}"; do
        TOTAL_FILES=$((TOTAL_FILES + 1))
        local file_issues=0

        log_info "Validating config file: $file"

        # JSON validation with jq
        if [[ "$file" == *.json ]]; then
            if [ "${TOOLS_AVAILABLE[jq]}" = "true" ]; then
                if ! jq empty "$file"; then
                    log_error "JSON syntax issues in $file"
                    file_issues=$((file_issues + 1))
                fi
            else
                log_warning "Skipping JSON validation (jq not available)"
            fi
        fi

        # YAML validation with yamllint
        if [[ "$file" == *.yaml ]] || [[ "$file" == *.yml ]]; then
            if [ "${TOOLS_AVAILABLE[yamllint]}" = "true" ]; then
                if ! yamllint "$file"; then
                    log_error "YAML issues in $file"
                    file_issues=$((file_issues + 1))
                fi
            else
                log_warning "Skipping YAML validation (yamllint not available)"
            fi
        fi

        # prettier formatting for JSON/YAML
        if [ "${TOOLS_AVAILABLE[prettier]}" = "true" ]; then
            if ! prettier --check "$file"; then
                log_error "prettier formatting issues in $file"
                log_info "Run 'prettier --write $file' to fix formatting"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping prettier validation (not available)"
        fi

        if [ $file_issues -eq 0 ]; then
            PASSED_FILES=$((PASSED_FILES + 1))
            log_success "✅ $file passed validation"
        else
            FAILED_FILES=$((FAILED_FILES + 1))
            config_issues=$((config_issues + file_issues))
        fi
    done

    return $config_issues
}

# Function to validate Bicep files
validate_bicep_files() {
    local files=("$@")
    local bicep_issues=0

    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    log_step "Validating ${#files[@]} Bicep file(s)"

    for file in "${files[@]}"; do
        TOTAL_FILES=$((TOTAL_FILES + 1))
        local file_issues=0

        log_info "Validating Bicep file: $file"

        # Bicep lint validation
        if [ "${TOOLS_AVAILABLE[bicep]}" = "true" ]; then
            if ! bicep lint "$file"; then
                log_error "Bicep lint issues in $file"
                file_issues=$((file_issues + 1))
            fi
        else
            log_warning "Skipping Bicep validation (bicep CLI not available)"
        fi

        if [ $file_issues -eq 0 ]; then
            PASSED_FILES=$((PASSED_FILES + 1))
            log_success "✅ $file passed validation"
        else
            FAILED_FILES=$((FAILED_FILES + 1))
            bicep_issues=$((bicep_issues + file_issues))
        fi
    done

    return $bicep_issues
}

# Function to find files by extension
find_files_by_extension() {
    local extension="$1"
    local files=()

    # Use find to get all files with the extension
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find . -name "*.$extension" -type f -print0)

    printf '%s\n' "${files[@]}"
}

# Function to show help
show_help() {
    cat <<EOF
Comprehensive Code Quality Validation Script

Usage: $0 [OPTIONS] [FILES...]

Options:
    --all           Validate all files in the repository
    --shell-only    Validate only shell scripts
    --python-only   Validate only Python files
    --ps-only       Validate only PowerShell files
    --md-only       Validate only Markdown files
    --config-only   Validate only JSON/YAML files
    --bicep-only    Validate only Bicep files
    --install-deps  Show installation commands for missing dependencies
    --help, -h      Show this help message

Examples:
    $0 --all                    # Validate all files
    $0 --shell-only             # Validate only shell scripts
    $0 script1.sh script2.py    # Validate specific files
    $0 --install-deps           # Show installation commands

Tool Coverage:
    Shell:      shellcheck, shfmt, RUTOS/busybox compatibility
    Python:     black, flake8, pylint, mypy, isort, bandit
    PowerShell: PSScriptAnalyzer
    Markdown:   markdownlint, prettier
    JSON/YAML:  jq, yamllint, prettier
    Bicep:      bicep lint

RUTOS/Busybox Compatibility Checks:
    - Shebang validation (#!/bin/sh required)
    - Bash-specific syntax detection (arrays, double brackets, etc.)
    - Echo -e usage (should use printf instead)
    - Source command usage (should use . instead)
    - Function syntax compatibility
    - Color code best practices

EOF
}

# Function to show installation commands
show_installation_commands() {
    log_step "Installation commands for missing dependencies"

    cat <<EOF

=== INSTALLATION COMMANDS ===

Shell Tools:
    sudo apt-get install shellcheck shfmt
    # OR
    brew install shellcheck shfmt

Python Tools:
    pip install black flake8 pylint mypy isort bandit

PowerShell Tools:
    # Install PowerShell Core first
    # Then install PSScriptAnalyzer module:
    pwsh -Command "Install-Module -Name PSScriptAnalyzer -Force"

Markdown Tools:
    npm install -g markdownlint-cli prettier

JSON/YAML Tools:
    sudo apt-get install jq
    pip install yamllint
    npm install -g prettier

Bicep Tools:
    # Install Azure CLI first, then:
    az bicep install

All-in-one install script:
    # Ubuntu/Debian
    sudo apt-get update
    sudo apt-get install -y shellcheck shfmt jq
    pip install black flake8 pylint mypy isort bandit yamllint
    npm install -g markdownlint-cli prettier
    
    # macOS
    brew install shellcheck shfmt jq
    pip install black flake8 pylint mypy isort bandit yamllint
    npm install -g markdownlint-cli prettier

EOF
}

# Function to print summary
print_summary() {
    local total_issues=$1

    log_step "=== COMPREHENSIVE VALIDATION SUMMARY ==="
    log_info "Total files processed: $TOTAL_FILES"
    log_success "Files passed: $PASSED_FILES"
    log_error "Files failed: $FAILED_FILES"
    log_warning "Files skipped: $SKIPPED_FILES"

    if [ "$total_issues" -eq 0 ]; then
        log_success "🎉 All files passed comprehensive validation!"
        return 0
    else
        log_error "❌ $total_issues validation issues found across $FAILED_FILES files"
        return 1
    fi
}

# Main function
main() {
    local validation_mode="mixed"
    local files_to_validate=()
    local total_issues=0

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                validation_mode="all"
                shift
                ;;
            --shell-only)
                validation_mode="shell"
                shift
                ;;
            --python-only)
                validation_mode="python"
                shift
                ;;
            --ps-only)
                validation_mode="powershell"
                shift
                ;;
            --md-only)
                validation_mode="markdown"
                shift
                ;;
            --config-only)
                validation_mode="config"
                shift
                ;;
            --bicep-only)
                validation_mode="bicep"
                shift
                ;;
            --install-deps)
                show_installation_commands
                exit 0
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                files_to_validate+=("$1")
                shift
                ;;
        esac
    done

    log_info "Starting comprehensive code quality validation v$SCRIPT_VERSION"

    # Initialize tool availability
    initialize_tools

    # Collect files based on mode
    local shell_files=()
    local python_files=()
    local ps_files=()
    local md_files=()
    local json_files=()
    local yaml_files=()
    local bicep_files=()

    if [ "$validation_mode" = "all" ]; then
        # Find all files by extension
        mapfile -t shell_files < <(find_files_by_extension "sh")
        mapfile -t python_files < <(find_files_by_extension "py")
        mapfile -t ps_files < <(find_files_by_extension "ps1")
        mapfile -t md_files < <(find_files_by_extension "md")
        mapfile -t json_files < <(find_files_by_extension "json")
        mapfile -t yaml_files < <(find_files_by_extension "yaml")
        mapfile -t bicep_files < <(find_files_by_extension "bicep")
    elif [ ${#files_to_validate[@]} -gt 0 ]; then
        # Categorize provided files
        for file in "${files_to_validate[@]}"; do
            case "$file" in
                *.sh) shell_files+=("$file") ;;
                *.py) python_files+=("$file") ;;
                *.ps1) ps_files+=("$file") ;;
                *.md) md_files+=("$file") ;;
                *.json) json_files+=("$file") ;;
                *.yaml | *.yml) yaml_files+=("$file") ;;
                *.bicep) bicep_files+=("$file") ;;
                *) log_warning "Unknown file type: $file" ;;
            esac
        done
    else
        # Mode-specific file collection
        case "$validation_mode" in
            shell) mapfile -t shell_files < <(find_files_by_extension "sh") ;;
            python) mapfile -t python_files < <(find_files_by_extension "py") ;;
            powershell) mapfile -t ps_files < <(find_files_by_extension "ps1") ;;
            markdown) mapfile -t md_files < <(find_files_by_extension "md") ;;
            config)
                mapfile -t json_files < <(find_files_by_extension "json")
                mapfile -t yaml_files < <(find_files_by_extension "yaml")
                ;;
            bicep) mapfile -t bicep_files < <(find_files_by_extension "bicep") ;;
        esac
    fi

    # Run validations
    if [ "$validation_mode" = "all" ] || [ "$validation_mode" = "mixed" ] || [ "$validation_mode" = "shell" ]; then
        if ! validate_shell_scripts "${shell_files[@]}"; then
            total_issues=$((total_issues + $?))
        fi
    fi

    if [ "$validation_mode" = "all" ] || [ "$validation_mode" = "mixed" ] || [ "$validation_mode" = "python" ]; then
        if ! validate_python_files "${python_files[@]}"; then
            total_issues=$((total_issues + $?))
        fi
    fi

    if [ "$validation_mode" = "all" ] || [ "$validation_mode" = "mixed" ] || [ "$validation_mode" = "powershell" ]; then
        if ! validate_powershell_files "${ps_files[@]}"; then
            total_issues=$((total_issues + $?))
        fi
    fi

    if [ "$validation_mode" = "all" ] || [ "$validation_mode" = "mixed" ] || [ "$validation_mode" = "markdown" ]; then
        if ! validate_markdown_files "${md_files[@]}"; then
            total_issues=$((total_issues + $?))
        fi
    fi

    if [ "$validation_mode" = "all" ] || [ "$validation_mode" = "mixed" ] || [ "$validation_mode" = "config" ]; then
        local config_files=("${json_files[@]}" "${yaml_files[@]}")
        if ! validate_json_yaml_files "${config_files[@]}"; then
            total_issues=$((total_issues + $?))
        fi
    fi

    if [ "$validation_mode" = "all" ] || [ "$validation_mode" = "mixed" ] || [ "$validation_mode" = "bicep" ]; then
        if ! validate_bicep_files "${bicep_files[@]}"; then
            total_issues=$((total_issues + $?))
        fi
    fi

    # Print summary and exit
    print_summary $total_issues
    exit $?
}

# Execute main function
main "$@"
