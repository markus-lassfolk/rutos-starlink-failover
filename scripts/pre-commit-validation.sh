#!/bin/sh
# Pre-commit validation script for RUTOS Starlink Failover Project
# Version: 2.7.0
# Description: Comprehensive validation of shell scripts for RUTOS/busybox compatibility
#              and markdown files for documentation quality
#
# This script demonstrates proper RUTOS library usage while serving as a validation tool.
# It validates that all RUTOS scripts (-rutos.sh) and library files use POSIX/busybox
# compatibility standards and proper library integration.
#
# VALIDATION APPROACH:
# - RUTOS scripts (ending in -rutos.sh): Validated for POSIX/busybox compatibility
# - Library files (scripts/lib/*.sh): Validated for POSIX/busybox compatibility
# - Development scripts: Less strict validation
# - This validation script: Uses RUTOS library as example

# NOTE: We don't use 'set -e' here because we want to continue processing all files
# and collect all validation issues before exiting

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"

# CRITICAL: Load RUTOS library system (REQUIRED for proper script structure)
. "$(dirname "$0")/lib/rutos-lib.sh"

# CRITICAL: Initialize script with library features (REQUIRED)
rutos_init "pre-commit-validation.sh" "$SCRIPT_VERSION"

# Files to exclude from validation (patterns supported)
# Only exclude files that genuinely shouldn't be shell-validated
EXCLUDED_FILES="scripts/setup-dev-tools.ps1" # PowerShell script, not shell script

# Validation counters
TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
TOTAL_ISSUES=0
CRITICAL_ISSUES=0
MAJOR_ISSUES=0
MINOR_ISSUES=0

# Autonomous mode variables
AUTONOMOUS_MODE=0
# shellcheck disable=SC2034  # Reserved for future output file functionality
AUTONOMOUS_OUTPUT_FILE=""
AUTONOMOUS_ISSUES=""

# Output filtering variables
SHOW_FIRST=""
SHOW_LAST=""
FILTER_PATTERN=""

# Issue tracking for summary (format: "issue_type|file_path")
ISSUE_LIST=""

# Function to check if a file should be excluded from validation
is_excluded() {
    file="$1"

    # Get relative path for pattern matching
    normalized_path="$(echo "$file" | sed 's|^./||' | sed 's|\\|/|g')"

    # Check the single exclusion pattern (POSIX-compatible)
    case "$normalized_path" in
        *"$EXCLUDED_FILES"*)
            return 0 # File is excluded
            ;;
    esac

    return 1 # File is not excluded
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check development tools and suggest installation
check_dev_tools() {
    missing_tools=""

    # Check for Node.js tools
    if ! command_exists markdownlint; then
        missing_tools="$missing_tools markdownlint"
    fi

    if ! command_exists prettier; then
        missing_tools="$missing_tools prettier"
    fi

    # Check for shell tools
    if ! command_exists shellcheck; then
        missing_tools="$missing_tools shellcheck"
    fi

    if ! command_exists shfmt; then
        missing_tools="$missing_tools shfmt"
    fi

    # If tools are missing, provide helpful suggestions
    if [ -n "$missing_tools" ]; then
        log_info "Some development tools are missing:"
        for tool in $missing_tools; do
            printf "  %s✗ %s%s not available\n" "$YELLOW" "$tool" "$NC"
        done

        printf "\n"
        log_info "💡 Quick setup options:"
        log_info "  • Run setup script: ./scripts/setup-dev-tools.sh"
        log_info "  • Manual Node.js tools: npm install -g markdownlint-cli prettier"
        log_info "  • Manual shell tools: sudo apt install shellcheck && go install mvdan.cc/sh/v3/cmd/shfmt@latest"
        printf "\n"
        log_info "🚀 Full setup with configurations:"
        if [ -f "./scripts/setup-dev-tools.sh" ]; then
            log_info "  bash ./scripts/setup-dev-tools.sh"
        fi
        if [ -f "./scripts/setup-dev-tools.ps1" ]; then
            log_info "  .\\scripts\\setup-dev-tools.ps1    # Windows PowerShell"
        fi
        printf "\n"
    else
        log_debug "All development tools are available"
    fi
}

# Function to report an issue
report_issue() {
    severity="$1"
    file="$2"
    line="$3"
    message="$4"

    # Add to issue list for summary (format: "message|file_path")
    if [ -n "$ISSUE_LIST" ]; then
        ISSUE_LIST="${ISSUE_LIST}
${message}|${file}"
    else
        ISSUE_LIST="${message}|${file}"
    fi

    # For autonomous mode, collect structured data
    if [ "$AUTONOMOUS_MODE" = "1" ]; then
        # Escape JSON characters in message and file path
        escaped_message=$(printf '%s' "$message" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
        escaped_file=$(printf '%s' "$file" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

        # Add to autonomous issues array (using newline-separated format for bash compatibility)
        issue_json=$(printf '{"severity":"%s","file":"%s","line":%s,"message":"%s","category":"%s","fix_priority":%d}' \
            "$severity" "$escaped_file" "$line" "$escaped_message" \
            "$(categorize_issue "$message")" "$(get_fix_priority "$severity" "$message")")

        if [ -z "$AUTONOMOUS_ISSUES" ]; then
            AUTONOMOUS_ISSUES="$issue_json"
        else
            AUTONOMOUS_ISSUES="$AUTONOMOUS_ISSUES
$issue_json"
        fi
    else
        # Normal human-readable output - only show if not autonomous mode
        if [ "$AUTONOMOUS_MODE" = "0" ]; then
            case "$severity" in
                "CRITICAL")
                    printf "${RED}[CRITICAL]${NC} %s:%s %s\n" "$file" "$line" "$message"
                    ;;
                "MAJOR")
                    printf "${YELLOW}[MAJOR]${NC} %s:%s %s\n" "$file" "$line" "$message"
                    ;;
                "MINOR")
                    printf "${BLUE}[MINOR]${NC} %s:%s %s\n" "$file" "$line" "$message"
                    ;;
            esac
        fi
    fi

    case "$severity" in
        "CRITICAL") CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1)) ;;
        "MAJOR") MAJOR_ISSUES=$((MAJOR_ISSUES + 1)) ;;
        "MINOR") MINOR_ISSUES=$((MINOR_ISSUES + 1)) ;;
    esac

    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
}

# Function to categorize issues for autonomous fixing
categorize_issue() {
    message="$1"
    case "$message" in
        *"SCRIPT_VERSION"*) echo "version" ;;
        *"appears unused"*) echo "unused_var" ;;
        *"function() syntax"*) echo "function_syntax" ;;
        *"SC2181"* | *"exit code"*) echo "exit_code" ;;
        *"SC2126"* | *"grep -c"*) echo "grep_optimization" ;;
        *"SC2034"*) echo "unused_variable" ;;
        *"SC2162"* | *"read without -r"*) echo "read_safety" ;;
        *"SC2059"* | *"printf format"*) echo "printf_format" ;;
        *"color definitions"* | *"missing"*) echo "missing_colors" ;;
        *"MD013"* | *"line length"*) echo "line_length" ;;
        *"MD040"* | *"fenced code"*) echo "code_blocks" ;;
        *"readonly"*) echo "immutable_version" ;;
        *"automation comment"*) echo "automation_comment" ;;
        *) echo "other" ;;
    esac
}

# Function to determine fix priority (1=highest, 5=lowest)
get_fix_priority() {
    severity="$1"
    message="$2"

    case "$severity" in
        "CRITICAL") echo 1 ;;
        "MAJOR")
            case "$message" in
                *"SCRIPT_VERSION"*) echo 1 ;;
                *"function() syntax"*) echo 2 ;;
                *"SC2181"* | *"exit code"*) echo 2 ;;
                *"appears unused"* | *"SC2034"*) echo 3 ;;
                *"SC2126"* | *"grep -c"*) echo 3 ;;
                *"SC2162"* | *"read without -r"*) echo 3 ;;
                *) echo 4 ;;
            esac
            ;;
        "MINOR") echo 5 ;;
        *) echo 5 ;;
    esac
}

# Function to determine if a file needs RUTOS/POSIX validation
needs_rutos_validation() {
    file="$1"

    # RUTOS scripts (ending in -rutos.sh) need validation
    case "$file" in
        *-rutos.sh) return 0 ;;
    esac

    # Library files (scripts/lib/*.sh) need validation since they're used by RUTOS scripts
    case "$file" in
        scripts/lib/*.sh) return 0 ;;
    esac

    return 1
}

# Function to check shebang compatibility (RUTOS scripts and library files)
check_shebang() {
    file="$1"
    shebang=$(head -1 "$file")

    # Only enforce POSIX shebang for RUTOS scripts and library files
    if ! needs_rutos_validation "$file"; then
        log_debug "Skipping shebang check for development script: $file"
        return 0
    fi

    case "$shebang" in
        "#!/bin/sh")
            log_debug "✓ $file: Uses POSIX shell shebang"
            return 0
            ;;
        "#!/bin/bash")
            report_issue "CRITICAL" "$file" "1" "RUTOS/library file uses bash shebang - should use #!/bin/sh for RUTOS compatibility"
            return 1
            ;;
        *)
            if [ -n "$shebang" ]; then
                report_issue "CRITICAL" "$file" "1" "RUTOS/library file has unknown shebang: $shebang (should be #!/bin/sh)"
            else
                report_issue "CRITICAL" "$file" "1" "RUTOS/library file missing shebang (should be #!/bin/sh)"
            fi
            return 1
            ;;
    esac
}

# Function to check bash-specific syntax (RUTOS scripts and library files)
check_bash_syntax() {
    file="$1"

    # Only apply POSIX/busybox validation to RUTOS scripts and library files
    if ! needs_rutos_validation "$file"; then
        log_debug "Skipping bash syntax check for development script: $file"
        return 0 # Skip validation for non-RUTOS scripts
    fi

    # Check for double brackets (bash-style conditions, not regex patterns)
    if grep -n "if[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
        # Use temporary file instead of process substitution
        temp_file="/tmp/bash_syntax_$$"
        grep -n "if[[:space:]]*\[\[.*\]\]" "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            report_issue "CRITICAL" "$file" "$line_num" "Uses double brackets [[ ]] - use single brackets [ ] for busybox"
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for double brackets in while loops
    if grep -n "while[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "while[[:space:]]*\[\[.*\]\]" "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            report_issue "CRITICAL" "$file" "$line_num" "Uses double brackets [[ ]] - use single brackets [ ] for busybox"
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for standalone double bracket conditions
    if grep -n "^[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "^[[:space:]]*\[\[.*\]\]" "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            # Skip if it's a POSIX character class like [[:space:]]
            if ! echo "$line_content" | grep -q "\[\[:[a-z]*:\]\]"; then
                report_issue "CRITICAL" "$file" "$line_num" "Uses double brackets [[ ]] - use single brackets [ ] for busybox"
            fi
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for local keyword
    if grep -n "^[[:space:]]*local " "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "^[[:space:]]*local " "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            report_issue "CRITICAL" "$file" "$line_num" "Uses 'local' keyword - not supported in busybox"
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for echo -e
    if grep -n "echo -e" "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "echo -e" "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            report_issue "MAJOR" "$file" "$line_num" "Uses 'echo -e' - use printf for busybox compatibility"
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for source command (but not in echo statements or comments)
    if grep -n "source " "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "source " "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            # Skip if it's within an echo statement (documentation) or comment lines
            if ! echo "$line_content" | grep -q "echo.*source" && ! echo "$line_content" | grep -q "^[[:space:]]*#.*source"; then
                report_issue "MAJOR" "$file" "$line_num" "Uses 'source' command - use '.' (dot) for busybox"
            fi
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for arrays
    if grep -n "declare -[aA]" "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "declare -[aA]" "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            report_issue "CRITICAL" "$file" "$line_num" "Uses arrays (declare -a) - not supported in busybox"
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for function() syntax (the actual 'function' keyword, not function names containing 'function')
    if grep -n "^[[:space:]]*function[[:space:]]\+[[:alnum:]_]\+[[:space:]]*(" "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "^[[:space:]]*function[[:space:]]\+[[:alnum:]_]\+[[:space:]]*(" "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            report_issue "MAJOR" "$file" "$line_num" "Uses function() syntax - use function_name() { } for busybox"
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    return 0
}

# Function to validate color code usage
validate_color_codes() {
    file="$1"

    # Check for direct color codes in printf statements (should use variables)
    if grep -n "printf.*\\\\033\[" "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "printf.*\\\\033\[" "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            report_issue "MAJOR" "$file" "$line_num" "Uses hardcoded color codes in printf - use color variables instead"
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for echo with color codes (should use printf)
    if grep -n "echo.*\\\\033\[" "$file" >/dev/null 2>&1; then
        while IFS=: read -r line_num line_content; do
            report_issue "MAJOR" "$file" "$line_num" "Uses echo with color codes - use printf for better compatibility"
        done < <(grep -n "echo.*\\\\033\[" "$file" 2>/dev/null)
    fi

    # CRITICAL: Check for Method 5 color format for RUTOS scripts
    # Method 5 format: printf "${COLOR}text${NC}" (WORKS in RUTOS)
    # Broken format: printf "%stext%s" "$COLOR" "$NC" (shows escape codes)
    case "$file" in
        *"-rutos.sh")
            # Check for the broken format that shows literal escape codes in RUTOS
            # Method 3 patterns to detect: printf "%s%s%s\n" "$BLUE" "text" "$NC"
            if grep -n 'printf.*"%.*%s.*%.*s.*".*\$\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)' "$file" >/dev/null 2>&1; then
                temp_file="/tmp/bash_syntax_$$"
                grep -n 'printf.*"%.*%s.*%.*s.*".*\$\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)' "$file" 2>/dev/null >"$temp_file"
                while IFS=: read -r line_num line_content; do
                    report_issue "CRITICAL" "$file" "$line_num" "RUTOS INCOMPATIBLE: Uses Method 3 printf format that shows escape codes. Use Method 5: printf \"\\\${COLOR}text\\\${NC}\" instead of printf \"%stext%s\" \"\\\$COLOR\" \"\\\$NC\""
                done <"$temp_file"
                rm -f "$temp_file"
            fi

            # Check if RUTOS script has proper Method 5 format examples
            # shellcheck disable=SC2016 # Single quotes are correct for grep patterns
            if grep -q 'printf.*".*\${[A-Z_]*}.*\${[A-Z_]*}.*"' "$file"; then
                log_debug "✓ $file: Uses Method 5 color format (RUTOS compatible)"
            elif grep -q 'printf.*".*%b.*"' "$file"; then
                log_debug "✓ $file: Uses %b format (install script compatible)"
            elif grep -q 'printf.*%s.*\$\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)' "$file"; then
                report_issue "MAJOR" "$file" "0" "RUTOS script should use Method 5 format: printf \"\\\${COLOR}text\\\${NC}\" for proper color display"
            fi
            ;;
    esac

    # Check for problematic printf patterns with color variables but missing proper format
    if grep -n "printf.*\\\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}.*%s.*\\\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}" "$file" >/dev/null 2>&1; then
        temp_file="/tmp/bash_syntax_$$"
        grep -n "printf.*\\\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}.*%s.*\\\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}" "$file" 2>/dev/null >"$temp_file"
        while IFS=: read -r line_num line_content; do
            # Only flag if it looks like color codes might be getting literal output
            # shellcheck disable=SC2016 # Single quotes are correct for grep patterns
            if echo "$line_content" | grep -q 'printf.*"[^"]*\\\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}[^"]*".*[^%]s'; then
                report_issue "MINOR" "$file" "$line_num" "Complex printf with colors - verify format string handles colors correctly"
            fi
        done <"$temp_file"
        rm -f "$temp_file"
    fi

    # Check for printf without proper format when using color variables
    if grep -n "printf.*\\\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}.*[^%][^s]\"" "$file" >/dev/null 2>&1; then
        while IFS=: read -r line_num line_content; do
            # Check if it's a printf that ends with a variable (not a format string)
            # shellcheck disable=SC2016 # Single quotes are correct for grep patterns
            if echo "$line_content" | grep -q 'printf.*\\\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}$'; then
                report_issue "MAJOR" "$file" "$line_num" "printf ending with color variable - missing format string or text"
            fi
        done < <(grep -n "printf.*\\\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}.*[^%][^s]\"" "$file" 2>/dev/null)
    fi

    # Check for proper color detection logic and completeness
    if grep -n "if.*-t.*1" "$file" >/dev/null 2>&1; then
        # Check if it's using the new simplified RUTOS-compatible pattern
        if grep -q "TERM.*dumb.*NO_COLOR" "$file"; then
            log_debug "✓ $file: Has RUTOS-compatible color detection"
        elif grep -q "command -v tput.*tput colors" "$file"; then
            report_issue "MAJOR" "$file" "0" "Using old complex color detection - update to RUTOS-compatible: if [ -t 1 ] && [ \"\${TERM:-}\" != \"dumb\" ] && [ \"\${NO_COLOR:-}\" != \"1\" ]"
        else
            log_debug "✓ $file: Has basic terminal color detection"
        fi

        # Check if all required colors are defined using POSIX-compatible method
        missing_colors=""

        # Check each required color individually
        for color in RED GREEN YELLOW BLUE CYAN NC; do
            if ! grep -q "^[[:space:]]*$color=" "$file"; then
                missing_colors="$missing_colors $color"
            fi
        done

        if [ -n "$missing_colors" ]; then
            report_issue "MAJOR" "$file" "0" "Missing color definitions:$missing_colors - all scripts should define RED, GREEN, YELLOW, BLUE, CYAN, NC"
        else
            log_debug "✓ $file: All required colors defined"
        fi

    elif grep -n "NO_COLOR\|TERM.*dumb" "$file" >/dev/null 2>&1; then
        # This is good - checking for NO_COLOR or dumb terminal
        log_debug "✓ $file: Has NO_COLOR detection"
    elif grep -n "^[[:space:]]*RED=\|^[[:space:]]*GREEN=\|^[[:space:]]*YELLOW=" "$file" >/dev/null 2>&1; then
        # Has color definitions but no detection - potential issue
        # Library files are exempt from this check as they provide fallback colors
        case "$file" in
            scripts/lib/*.sh)
                log_debug "✓ $file: Library file with fallback colors (detection handled by rutos-colors.sh)"
                ;;
            *)
                if ! grep -q "if.*-t.*1\|NO_COLOR\|TERM.*dumb" "$file"; then
                    report_issue "MAJOR" "$file" "0" "Defines colors but missing color detection logic - add RUTOS-compatible detection: if [ -t 1 ] && [ \"\${TERM:-}\" != \"dumb\" ] && [ \"\${NO_COLOR:-}\" != \"1\" ]"
                fi
                ;;
        esac
    fi

    return 0
}

# Function to validate SCRIPT_VERSION according to best practices
validate_script_version() {
    file="$1"

    # Library files don't need SCRIPT_VERSION - they're versioned as a unit
    case "$file" in
        scripts/lib/*.sh)
            log_debug "Skipping SCRIPT_VERSION check for library file: $file"
            return 0
            ;;
    esac

    # Check if SCRIPT_VERSION is defined
    if ! grep -q "^[[:space:]]*SCRIPT_VERSION=" "$file"; then
        report_issue "CRITICAL" "$file" "1" "Missing SCRIPT_VERSION variable - all scripts must define version"
        return 1
    fi

    # Check SCRIPT_VERSION format and best practices
    version_line_num=""
    version_line=""

    # Get the SCRIPT_VERSION line
    version_line_num=$(grep -n "^[[:space:]]*SCRIPT_VERSION=" "$file" | head -1 | cut -d: -f1)
    version_line=$(grep "^[[:space:]]*SCRIPT_VERSION=" "$file" | head -1)

    # Check if version is properly quoted
    if ! echo "$version_line" | grep -q 'SCRIPT_VERSION="[0-9]\+\.[0-9]\+\.[0-9]\+"'; then
        if echo "$version_line" | grep -q 'SCRIPT_VERSION=[0-9]'; then
            report_issue "MAJOR" "$file" "$version_line_num" "SCRIPT_VERSION should be quoted: SCRIPT_VERSION=\"X.Y.Z\""
        elif echo "$version_line" | grep -q 'SCRIPT_VERSION='; then
            report_issue "MAJOR" "$file" "$version_line_num" "SCRIPT_VERSION should use semantic versioning format: \"X.Y.Z\""
        fi
    fi

    # Check if version follows semantic versioning
    version_value=""
    version_value=$(echo "$version_line" | sed 's/.*SCRIPT_VERSION="\([^"]*\)".*/\1/' | sed 's/.*SCRIPT_VERSION=\([^[:space:]]*\).*/\1/' | tr -d '"')

    if ! echo "$version_value" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        report_issue "MAJOR" "$file" "$version_line_num" "SCRIPT_VERSION should use semantic versioning (X.Y.Z): current=\"$version_value\""
    fi

    # Check if readonly is used (recommended but not required)
    next_line_num=$((version_line_num + 1))
    next_line=""
    next_line=$(sed -n "${next_line_num}p" "$file" 2>/dev/null)

    if ! echo "$next_line" | grep -q "readonly.*SCRIPT_VERSION"; then
        # Check if readonly is on the same line
        if ! echo "$version_line" | grep -q "readonly"; then
            report_issue "MINOR" "$file" "$version_line_num" "Consider using 'readonly SCRIPT_VERSION' for immutable version"
        fi
    fi

    # Check positioning - SCRIPT_VERSION should be after shebang/set commands, before other variables
    set_line_num=""
    set_line_num=$(grep -n "^set " "$file" | head -1 | cut -d: -f1 2>/dev/null || echo "1")

    # SCRIPT_VERSION should be within first 30 lines and after set commands
    if [ "$version_line_num" -gt 30 ]; then
        report_issue "MINOR" "$file" "$version_line_num" "SCRIPT_VERSION should be defined near the top of the file (within first 30 lines)"
    fi

    if [ -n "$set_line_num" ] && [ "$version_line_num" -lt "$set_line_num" ]; then
        report_issue "MINOR" "$file" "$version_line_num" "SCRIPT_VERSION should be defined after 'set' commands"
    fi

    # Check for automation comment
    comment_line_num=$((version_line_num - 1))
    comment_line=""
    comment_line=$(sed -n "${comment_line_num}p" "$file" 2>/dev/null)

    if ! echo "$comment_line" | grep -q "auto-updated.*update-version"; then
        report_issue "MINOR" "$file" "$comment_line_num" "Consider adding automation comment: # Version information (auto-updated by update-version.sh)"
    fi

    # Check if version is actually used in the script
    if ! grep -q "\$SCRIPT_VERSION" "$file"; then
        report_issue "MINOR" "$file" "$version_line_num" "SCRIPT_VERSION is defined but never used - consider displaying in logs or help"
    fi

    return 0
}

# Function to validate Markdown file versioning
validate_markdown_version() {
    file="$1"

    # Check for version information in markdown files
    has_version=false

    # Look for various version patterns in markdown
    if grep -q "^# Version:" "$file" ||
        grep -q "Version: [0-9]" "$file" ||
        grep -q "\*\*Version:\*\* [0-9]" "$file" ||
        grep -q "v[0-9]\+\.[0-9]\+\.[0-9]\+" "$file"; then
        has_version=true
    fi

    # Look for YAML frontmatter version
    if head -10 "$file" | grep -q "^version:" || head -10 "$file" | grep -q "^Version:"; then
        has_version=true
    fi

    if [ "$has_version" = "false" ]; then
        report_issue "MINOR" "$file" "1" "Consider adding version information to documentation file"
    fi

    return 0
}

# Function to run ShellCheck
run_shellcheck() {
    file="$1"

    if ! command_exists shellcheck; then
        log_warning "ShellCheck not available - skipping syntax validation"
        return 0
    fi

    # Determine shell type and exclusions based on file type
    shell_type="bash"
    exclude_codes=""

    if needs_rutos_validation "$file"; then
        shell_type="sh"
        # For RUTOS scripts, exclude SC2059 as Method 5 printf format is required for RUTOS compatibility
        exclude_codes="-e SC2059"
        log_debug "Using POSIX mode for RUTOS/library file: $file"
    else
        log_debug "Using bash mode for development script: $file"
    fi

    # Additional exclusions for library files
    case "$file" in
        scripts/lib/*.sh)
            # Library files are allowed to have "unused" variables (they're used by other scripts)
            # and dynamic sourcing patterns
            exclude_codes="$exclude_codes -e SC2034 -e SC1091 -e SC1090"
            log_debug "Adding library-specific exclusions for: $file"
            ;;
    esac

    # Run shellcheck with appropriate exclusions
    # shellcheck disable=SC2086 # We want word splitting for exclude_codes
    shellcheck_output=$(shellcheck -s "$shell_type" $exclude_codes "$file" 2>&1)
    shellcheck_exit_code=$?

    if [ $shellcheck_exit_code -eq 0 ]; then
        log_debug "✓ $file: Passes ShellCheck validation"
        return 0
    else
        log_warning "$file: ShellCheck found issues"
        [ "$AUTONOMOUS_MODE" = "0" ] && echo "$shellcheck_output" | head -10

        # Parse ShellCheck output to extract error codes - avoid subshell
        # Save output to temp file to avoid subshell issues
        temp_file=$(mktemp)
        echo "$shellcheck_output" >"$temp_file"

        # Parse the output line by line
        line_num=""
        while IFS= read -r line; do
            if echo "$line" | grep -q "^In.*line [0-9]+:"; then
                # shellcheck disable=SC2001 # Complex regex replacement with capture groups
                line_num=$(echo "$line" | sed 's/.*line \([0-9]*\):.*/\1/')
            elif echo "$line" | grep -qE "SC[0-9]+"; then
                # shellcheck disable=SC2001 # Complex regex replacement with capture groups
                sc_code=$(echo "$line" | sed 's/.*\(SC[0-9]*\).*/\1/')
                # shellcheck disable=SC2001 # Complex regex replacement with capture groups
                description=$(echo "$line" | sed 's/.*SC[0-9]*[^:]*: *//')
                report_issue "MAJOR" "$file" "$line_num" "$sc_code: $description"
            fi
        done <"$temp_file"

        # Clean up temp file
        rm -f "$temp_file"

        return 1
    fi
}

# Function to run shfmt formatting validation
run_shfmt() {
    file="$1"

    if ! command_exists shfmt; then
        log_warning "shfmt not available - skipping formatting validation"
        return 0
    fi

    # Determine shfmt options based on script type (match GitHub Action settings)
    shfmt_options="-i 4 -ci"
    if echo "$file" | grep -q '\-rutos\.sh$'; then
        # RUTOS scripts need POSIX-compatible formatting for local validation
        shfmt_options="-i 4 -ci -ln posix"
        log_debug "Using POSIX formatting validation for RUTOS script: $file"
        log_debug "Note: Server-side auto-formatting disabled, but local validation active"
    fi

    # Run shfmt to check formatting
    # shellcheck disable=SC2086 # We want word splitting for shfmt options
    if ! shfmt $shfmt_options -d "$file" >/dev/null 2>&1; then
        log_debug "shfmt found formatting issues in $file"

        # Count the number of formatting issues (lines of diff output)
        # shellcheck disable=SC2086 # We want word splitting for shfmt options
        diff_lines=$(shfmt $shfmt_options -d "$file" 2>/dev/null | wc -l)

        if [ "$diff_lines" -gt 0 ]; then
            report_issue "MAJOR" "$file" "0" "shfmt formatting issues - run 'shfmt $shfmt_options -w $file' to fix"
            return 1
        fi
    else
        log_debug "✓ $file: Passes shfmt formatting validation"
        return 0
    fi

    return 0
}

# Function to check for undefined variables (especially color variables)
check_undefined_variables() {
    file="$1"

    # Library files are allowed to define color variables and shouldn't be checked for using them
    case "$file" in
        scripts/lib/*.sh)
            log_debug "Skipping undefined variable check for library file: $file"
            return 0
            ;;
    esac

    # Check for common color variables that might be undefined
    color_vars="RED GREEN YELLOW BLUE PURPLE CYAN NC"

    for var in $color_vars; do
        # Check if variable is used before definition
        if grep -n "\$$var\|\".*\$\{$var\}" "$file" >/dev/null 2>&1; then
            # Find first usage
            first_usage=$(grep -n "\$$var\|\".*\$\{$var\}" "$file" | head -1 | cut -d: -f1)

            # Find definition line
            definition_line=$(grep -n "^[[:space:]]*$var=" "$file" | head -1 | cut -d: -f1)

            # If variable is used but not defined, or used before definition
            if [ -z "$definition_line" ]; then
                # For RUTOS scripts, this is likely expected (they should use library)
                if [[ "$file" == *-rutos.sh ]]; then
                    log_debug "RUTOS script $file uses \$$var (should come from library)"
                else
                    report_issue "CRITICAL" "$file" "$first_usage" "Variable \$$var is used but not defined"
                fi
            elif [ "$first_usage" -lt "$definition_line" ]; then
                report_issue "CRITICAL" "$file" "$first_usage" "Variable \$$var is used before it's defined (line $definition_line)"
            fi
        fi
    done

    # Check for variables used in parameter expansion that might be undefined
    # NOTE: Temporarily disabled this complex check due to false positives
    # The core shellcheck fixes requested have been implemented
    # This feature needs further refinement to avoid issues

    # Check for variables used in functions that might not be in scope
    # Look for functions that use variables that aren't defined within the function
    if grep -n "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$file" >/dev/null 2>&1; then
        while IFS=: read -r line_num line_content; do
            func_name=$(echo "$line_content" | sed -n 's/^[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]*(.*/\1/p')
            if [ -n "$func_name" ]; then
                # Extract the function body and check for undefined variables
                awk -v start_line="$line_num" -v file="$file" '
					NR >= start_line && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(/ { 
						in_function=1; brace_count=0; func_start=NR
					}
					in_function && /{/ { brace_count++ }
					in_function && /}/ { 
						brace_count--; 
						if (brace_count == 0) { 
							in_function=0;
							# Check if this function uses color variables
							if (/\$CYAN/ || /\$RED/ || /\$GREEN/ || /\$YELLOW/ || /\$BLUE/ || /\$PURPLE/ || /\$NC/) {
								print "Function at line " func_start " uses color variables"
							}
						}
					}
				' "$file" >/dev/null 2>&1
            fi
        done < <(grep -n "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$file" 2>/dev/null)
    fi
}

# Function to test debug/test/dry-run integration patterns
test_debug_integration() {
    file="$1"

    # Skip non-RUTOS scripts - they may have different patterns
    case "$file" in
        *-rutos.sh) ;;
        *) return 0 ;;
    esac

    log_debug "Testing debug/test/dry-run integration for: $file"

    has_issues=0
    has_debug_support=0
    has_test_mode=0
    has_dry_run=0
    has_early_exit=0
    has_debug_before_exit=0

    # Check for DEBUG support
    if grep -q "DEBUG.*:-.*0" "$file" || grep -q "if.*DEBUG.*=" "$file"; then
        has_debug_support=1
        log_debug "  ✓ Found DEBUG support"
    fi

    # Check for TEST_MODE or RUTOS_TEST_MODE support
    if grep -q "RUTOS_TEST_MODE.*:-.*0" "$file" || grep -q "TEST_MODE.*:-.*0" "$file"; then
        has_test_mode=1
        log_debug "  ✓ Found test mode support"
    fi

    # Check for DRY_RUN support
    if grep -q "DRY_RUN.*:-.*0" "$file" || grep -q "if.*DRY_RUN.*=" "$file"; then
        has_dry_run=1
        log_debug "  ✓ Found DRY_RUN support"
    fi

    # Check for early exit pattern in test mode
    if grep -q "exit 0" "$file" && (grep -q "RUTOS_TEST_MODE.*1" "$file" || grep -q "TEST_MODE.*1" "$file"); then
        has_early_exit=1
        log_debug "  ✓ Found early exit in test mode"
    fi

    # Check if debug output happens before early exit
    debug_line=""
    exit_line=""
    debug_line=$(grep -n "printf.*DEBUG.*%s" "$file" | head -1 | cut -d: -f1)
    exit_line=$(grep -n "exit 0" "$file" | head -1 | cut -d: -f1)

    if [ -n "$debug_line" ] && [ -n "$exit_line" ] && [ "$debug_line" -lt "$exit_line" ]; then
        has_debug_before_exit=1
        log_debug "  ✓ Debug output occurs before early exit"
    fi

    # Advanced pattern validation
    local validation_issues=()

    # Issue 1: Scripts with test mode should support both TEST_MODE and RUTOS_TEST_MODE for compatibility
    if [ "$has_test_mode" = "1" ]; then
        if ! grep -q "TEST_MODE.*:-.*0.*RUTOS_TEST_MODE\|RUTOS_TEST_MODE.*:-.*0.*TEST_MODE" "$file"; then
            if ! (grep -q "TEST_MODE.*:-.*0" "$file" && grep -q "RUTOS_TEST_MODE.*:-.*0" "$file"); then
                validation_issues+=("Missing backward compatibility: should support both TEST_MODE and RUTOS_TEST_MODE")
                has_issues=1
            fi
        fi
    fi

    # Issue 2: Debug output should show all relevant variable states
    if [ "$has_debug_support" = "1" ] && [ "$has_test_mode" = "1" ] && [ "$has_dry_run" = "1" ]; then
        if ! grep -q "printf.*DEBUG.*DRY_RUN.*TEST_MODE\|printf.*DEBUG.*RUTOS_TEST_MODE.*DRY_RUN" "$file"; then
            validation_issues+=("Debug output should display DRY_RUN, TEST_MODE, and RUTOS_TEST_MODE states")
            has_issues=1
        fi
    fi

    # Issue 3: Early exit should happen AFTER debug output to allow troubleshooting
    if [ "$has_test_mode" = "1" ] && [ "$has_debug_support" = "1" ] && [ "$has_early_exit" = "1" ]; then
        if [ "$has_debug_before_exit" != "1" ]; then
            validation_issues+=("Early test mode exit should occur AFTER debug output for troubleshooting")
            has_issues=1
        fi
    fi

    # Issue 4: Scripts should capture original variable values for debug display
    if [ "$has_debug_support" = "1" ] && [ "$has_dry_run" = "1" ]; then
        if ! grep -q "ORIGINAL_DRY_RUN" "$file"; then
            validation_issues+=("Should capture ORIGINAL_DRY_RUN for debug display")
            has_issues=1
        fi
    fi

    if [ "$has_debug_support" = "1" ] && [ "$has_test_mode" = "1" ]; then
        if ! grep -q "ORIGINAL.*TEST_MODE" "$file"; then
            validation_issues+=("Should capture ORIGINAL_TEST_MODE/ORIGINAL_RUTOS_TEST_MODE for debug display")
            has_issues=1
        fi
    fi

    # Issue 5: Check for proper debug command tracing patterns
    if [ "$has_debug_support" = "1" ] && [ "$has_dry_run" = "1" ]; then
        # Look for commands that should be logged in debug mode
        local has_command_logging=0
        if grep -q "log_debug.*EXECUTING\|printf.*DEBUG.*EXECUTING" "$file"; then
            has_command_logging=1
        fi

        # Check if script has commands that modify system state
        if grep -qE "(curl|wget|echo.*>|cp|mv|rm|mkdir|chmod|chown|systemctl|service|crontab)" "$file"; then
            if [ "$has_command_logging" != "1" ]; then
                validation_issues+=("Scripts with system-modifying commands should log command execution in debug mode")
                has_issues=1
            fi
        fi
    fi

    # Issue 6: DRY_RUN should prevent actual execution of state-changing commands
    if [ "$has_dry_run" = "1" ]; then
        # Look for state-changing commands that should be wrapped in DRY_RUN checks
        risky_commands="curl wget echo.*> cp mv rm mkdir chmod chown systemctl service crontab"
        has_unprotected_commands=0

        for cmd in $risky_commands; do
            if grep -qE "$cmd" "$file" && ! grep -B5 -A5 "$cmd" "$file" | grep -q "DRY_RUN.*0"; then
                # Check if this command is in a conditional block
                cmd_lines=$(grep -n "$cmd" "$file" | cut -d: -f1)
                for line_num in $cmd_lines; do
                    # Check if this command is properly protected by DRY_RUN check
                    context=$(sed -n "$((line_num - 3)),$((line_num + 1))p" "$file")
                    if ! echo "$context" | grep -q "DRY_RUN.*0"; then
                        has_unprotected_commands=1
                        break
                    fi
                done
                [ "$has_unprotected_commands" = "1" ] && break
            fi
        done

        if [ "$has_unprotected_commands" = "1" ]; then
            validation_issues+=("State-changing commands should be protected by DRY_RUN checks")
            has_issues=1
        fi
    fi

    # Report issues
    if [ "$has_issues" = "1" ]; then
        report_issue "$file" "DEBUG_INTEGRATION" "Major" "Debug/Test/Dry-run integration issues found:"
        # Note: In POSIX mode, we don't store detailed validation issues array
        # This function focuses on detecting patterns rather than detailed reporting
        return 1
    fi

    # Report successful patterns
    success_patterns=""
    [ "$has_debug_support" = "1" ] && success_patterns="$success_patterns DEBUG-support"
    [ "$has_test_mode" = "1" ] && success_patterns="$success_patterns Test-mode-support"
    [ "$has_dry_run" = "1" ] && success_patterns="$success_patterns DRY_RUN-support"
    [ "$has_debug_before_exit" = "1" ] && success_patterns="$success_patterns Debug-before-exit-pattern"

    if [ -n "$success_patterns" ]; then
        log_debug "  ✓ $file: Good debug integration patterns:$success_patterns"
    fi

    return 0
}

# Function to validate RUTOS library usage
validate_library_usage() {
    local file="$1"

    # Handle library files specially - they define the functions and variables
    if [[ "$file" == scripts/lib/*.sh ]]; then
        log_debug "Validating library file for POSIX compatibility: $file"

        # Library files are allowed to define logging functions and color variables
        # They should be POSIX-compatible but don't need to load themselves
        return 0
    fi

    # Only validate RUTOS scripts (ending in -rutos.sh) for library usage
    case "$file" in
        *-rutos.sh)
            log_debug "Validating RUTOS library usage for: $file"
            ;;
        *)
            log_debug "Skipping library validation for non-RUTOS script: $file"
            return 0
            ;;
    esac

    # Check 1: Script should load the RUTOS library
    if ! grep -q '\. "$(dirname "\$0")/lib/rutos-lib\.sh"' "$file" && ! grep -q '\. "\$(dirname \$0)/lib/rutos-lib\.sh"' "$file"; then
        report_issue "CRITICAL" "$file" "1" "RUTOS script must load library: . \"\$(dirname \"\$0\")/lib/rutos-lib.sh\""
        return 1
    fi

    # Check 2: Script should call rutos_init
    if ! grep -q "rutos_init " "$file"; then
        report_issue "CRITICAL" "$file" "1" "RUTOS script must call rutos_init after loading library"
        return 1
    fi

    # Check 3: Script should NOT define its own logging functions (library provides them)
    local forbidden_functions="log_info log_error log_debug log_trace log_warning log_success log_step"
    for func in $forbidden_functions; do
        local func_line=$(grep -n "^$func()" "$file" | head -1 | cut -d: -f1)
        if [ -n "$func_line" ]; then
            report_issue "MAJOR" "$file" "$func_line" "Do not define $func() - provided by RUTOS library"
        fi
    done

    # Check 4: Script should NOT define its own color variables (library provides them)
    local color_vars="RED GREEN YELLOW BLUE PURPLE CYAN NC"
    for color in $color_vars; do
        local color_line=$(grep -n "^[[:space:]]*$color=" "$file" | head -1 | cut -d: -f1)
        if [ -n "$color_line" ]; then
            report_issue "MAJOR" "$file" "$color_line" "Do not define $color= - provided by RUTOS library"
        fi
    done

    # Check 5: Script should use safe_execute() for system commands
    local risky_commands="curl wget systemctl service crontab"
    for cmd in $risky_commands; do
        # Look for direct usage not wrapped in safe_execute
        if grep -q "$cmd " "$file" && ! grep -q "safe_execute.*$cmd" "$file"; then
            local cmd_line=$(grep -n "$cmd " "$file" | head -1 | cut -d: -f1)
            if [ -n "$cmd_line" ]; then
                report_issue "MINOR" "$file" "$cmd_line" "Consider using safe_execute() for system command: $cmd"
            fi
        fi
    done

    # Check 6: Validate proper Method 5 printf format for RUTOS compatibility
    if grep -q 'printf.*%s.*\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}' "$file"; then
        local printf_line=$(grep -n 'printf.*%s.*\${\(RED\|GREEN\|YELLOW\|BLUE\|PURPLE\|CYAN\|NC\)}' "$file" | head -1 | cut -d: -f1)
        if [ -n "$printf_line" ]; then
            report_issue "MAJOR" "$file" "$printf_line" "Use Method 5 format: printf \"\${COLOR}text\${NC}\" not printf \"%stext%s\" \"\$COLOR\" \"\$NC\""
        fi
    fi

    # Check 7: Script should support standard environment variables
    local expected_vars="DEBUG DRY_RUN RUTOS_TEST_MODE"
    for var in $expected_vars; do
        if ! grep -q "$var" "$file"; then
            report_issue "MINOR" "$file" "1" "Consider supporting standard variable: $var (library handles this)"
        fi
    done

    # Check 8: Validate proper error handling patterns
    if ! grep -q "log_function_entry\|log_function_exit" "$file"; then
        report_issue "MINOR" "$file" "1" "Consider using log_function_entry/exit for better debugging"
    fi

    log_success "✓ $file: RUTOS library validation completed"
    return 0
}

# Function to validate a single shell script file
validate_file() {
    file="$1"

    [ "$AUTONOMOUS_MODE" = "0" ] && log_step "Validating: $file"

    initial_issues=$TOTAL_ISSUES

    # Try to auto-fix formatting issues first
    auto_fix_formatting "$file"
    fix_result=$?
    if [ $fix_result -eq 1 ]; then
        [ "$AUTONOMOUS_MODE" = "0" ] && log_info "Applied auto-fixes to $file"
    fi

    # Check shebang
    check_shebang "$file"

    # Validate RUTOS library usage (CRITICAL - must be first after basic checks)
    validate_library_usage "$file"

    # Check bash-specific syntax
    check_bash_syntax "$file"

    # Check for undefined variables
    check_undefined_variables "$file"

    # Validate color code usage
    validate_color_codes "$file"

    # Validate SCRIPT_VERSION according to best practices
    validate_script_version "$file"

    # Run ShellCheck
    run_shellcheck "$file"

    # Run shfmt formatting validation (after potential auto-fixes)
    run_shfmt "$file"

    # Test debug/test/dry-run integration patterns (RUTOS scripts only)
    test_debug_integration "$file"

    # Calculate issues for this file
    file_issues=$((TOTAL_ISSUES - initial_issues))

    if [ $file_issues -eq 0 ]; then
        [ "$AUTONOMOUS_MODE" = "0" ] && log_success "✓ $file: All checks passed"
        PASSED_FILES=$((PASSED_FILES + 1))
    else
        [ "$AUTONOMOUS_MODE" = "0" ] && log_error "✗ $file: $file_issues issues found"
        FAILED_FILES=$((FAILED_FILES + 1))
    fi

    return $file_issues
}

# Function to auto-fix formatting issues
auto_fix_formatting() {
    local file="$1"
    local file_extension="${file##*.}"
    local fixes_applied=0

    case "$file_extension" in
        "sh")
            # Auto-fix shell script formatting with shfmt (match GitHub Action settings)
            if command_exists shfmt; then
                # Determine shfmt options based on script type
                shfmt_options="-i 4 -ci"
                if echo "$file" | grep -q '\-rutos\.sh$'; then
                    # RUTOS scripts need POSIX-compatible formatting
                    shfmt_options="-i 4 -ci -ln posix"
                fi

                # shellcheck disable=SC2086 # We want word splitting for shfmt options
                if ! shfmt $shfmt_options -d "$file" >/dev/null 2>&1; then
                    [ "$AUTONOMOUS_MODE" = "0" ] && log_info "Auto-fixing shell script formatting: $file (options: $shfmt_options)"
                    # shellcheck disable=SC2086 # We want word splitting for shfmt options
                    shfmt $shfmt_options -w "$file"
                    fixes_applied=1
                fi
            fi
            ;;
        "md")
            # Auto-fix markdown formatting with prettier
            if command_exists prettier; then
                # Check if prettier would make changes
                if ! prettier --check "$file" >/dev/null 2>&1; then
                    [ "$AUTONOMOUS_MODE" = "0" ] && log_info "Auto-fixing markdown formatting: $file"
                    prettier --write "$file" >/dev/null 2>&1
                    fixes_applied=1
                fi
            fi
            ;;
    esac

    return $fixes_applied
}

# Function to run markdownlint validation
run_markdownlint() {
    local file="$1"

    if ! command_exists markdownlint; then
        log_warning "markdownlint not available - skipping markdown validation"
        log_warning "💡 To install: run './scripts/setup-dev-tools.sh' or 'npm install -g markdownlint-cli'"
        return 0
    fi

    # Run markdownlint and capture output
    markdownlint_output=$(markdownlint "$file" 2>&1)
    markdownlint_exit_code=$?

    if [ $markdownlint_exit_code -eq 0 ]; then
        log_debug "✓ $file: Passes markdownlint validation"
        return 0
    else
        log_warning "$file: markdownlint found issues"

        # Parse markdownlint output using a temporary file to avoid subshell
        temp_file="/tmp/markdownlint_$$"
        echo "$markdownlint_output" >"$temp_file"

        while IFS= read -r line; do
            if [[ "$line" =~ ^([^:]+):([0-9]+).*MD([0-9]+)(.*)$ ]]; then
                file_path="${BASH_REMATCH[1]}"
                line_num="${BASH_REMATCH[2]}"
                md_code="MD${BASH_REMATCH[3]}"
                description="${BASH_REMATCH[4]}"
                report_issue "MAJOR" "$file_path" "$line_num" "$md_code:$description"
            fi
        done <"$temp_file"

        # Clean up temporary file
        rm -f "$temp_file"

        return 1
    fi
}

# Function to run prettier validation for markdown
run_prettier_markdown() {
    local file="$1"

    if ! command_exists prettier; then
        log_warning "prettier not available - skipping markdown formatting validation"
        log_warning "💡 To install: run './scripts/setup-dev-tools.sh' or 'npm install -g prettier'"
        return 0
    fi

    # Check if prettier would make changes
    if prettier --check "$file" >/dev/null 2>&1; then
        log_debug "✓ $file: Passes prettier formatting validation"
        return 0
    else
        log_debug "prettier found formatting issues in $file"
        report_issue "MAJOR" "$file" "0" "prettier formatting issues - run 'prettier --write $file' to fix"
        return 1
    fi
}

# Function to validate markdown file
validate_markdown_file() {
    local file="$1"

    [ "$AUTONOMOUS_MODE" = "0" ] && log_step "Validating: $file"

    local initial_issues=$TOTAL_ISSUES

    # Try to auto-fix formatting issues first
    if auto_fix_formatting "$file"; then
        [ "$AUTONOMOUS_MODE" = "0" ] && log_info "Applied auto-fixes to $file"
    fi

    # Run markdownlint validation
    run_markdownlint "$file"

    # Validate markdown versioning
    validate_markdown_version "$file"

    # Run prettier validation (after potential auto-fixes)
    run_prettier_markdown "$file"

    # Calculate issues for this file
    local file_issues=$((TOTAL_ISSUES - initial_issues))

    if [ $file_issues -eq 0 ]; then
        [ "$AUTONOMOUS_MODE" = "0" ] && log_success "✓ $file: All checks passed"
        PASSED_FILES=$((PASSED_FILES + 1))
    else
        [ "$AUTONOMOUS_MODE" = "0" ] && log_error "✗ $file: $file_issues issues found"
        FAILED_FILES=$((FAILED_FILES + 1))
    fi

    return $file_issues
}

# Function to display debug integration patterns summary
display_debug_integration_summary() {
    [ "$AUTONOMOUS_MODE" = "1" ] && return 0 # Skip in autonomous mode

    local files_to_analyze="$1"
    local rutos_scripts=()
    scripts_with_debug=0
    scripts_with_test_mode=0
    scripts_with_dry_run=0
    scripts_with_all_patterns=0
    scripts_with_integration_issues=0
    rutos_script_count=0

    # Filter for RUTOS scripts from the files being validated and count them
    for file in $files_to_analyze; do
        case "$file" in
            *-rutos.sh)
                rutos_script_count=$((rutos_script_count + 1))
                ;;
        esac
    done

    if [ "$rutos_script_count" -eq 0 ]; then
        log_debug "No RUTOS scripts found in validated files - skipping debug integration summary"
        return 0
    fi

    # Analyze each RUTOS script
    for script in $files_to_analyze; do
        case "$script" in
            *-rutos.sh)
                has_debug=0
                has_test_mode=0
        local has_dry_run=0
        local has_issues=0

        # Check for DEBUG support
        if grep -q "DEBUG.*:-.*0" "$script" || grep -q "if.*DEBUG.*=" "$script"; then
            has_debug=1
            scripts_with_debug=$((scripts_with_debug + 1))
        fi

        # Check for TEST_MODE or RUTOS_TEST_MODE support
        if grep -q "RUTOS_TEST_MODE.*:-.*0" "$script" || grep -q "TEST_MODE.*:-.*0" "$script"; then
            has_test_mode=1
            scripts_with_test_mode=$((scripts_with_test_mode + 1))
        fi

        # Check for DRY_RUN support
        if grep -q "DRY_RUN.*:-.*0" "$script" || grep -q "if.*DRY_RUN.*=" "$script"; then
            has_dry_run=1
            scripts_with_dry_run=$((scripts_with_dry_run + 1))
        fi

        # Check for integration issues (from our issue list)
        if echo "$ISSUE_LIST" | grep -q "DEBUG_INTEGRATION.*$script"; then
            has_issues=1
            scripts_with_integration_issues=$((scripts_with_integration_issues + 1))
        fi

        # Count scripts with all three patterns
        if [ "$has_debug" = "1" ] && [ "$has_test_mode" = "1" ] && [ "$has_dry_run" = "1" ]; then
            scripts_with_all_patterns=$((scripts_with_all_patterns + 1))
        fi
                ;;
        esac
    done

    # Display summary if we have RUTOS scripts
    printf "\n"
    printf "%s=== DEBUG INTEGRATION PATTERNS SUMMARY ===%s\n" "$PURPLE" "$NC"
    printf "RUTOS scripts analyzed: %d\n" "$rutos_script_count"
    printf "\n"
    if [ "$rutos_script_count" -gt 0 ]; then
        printf "Scripts with DEBUG support:     %d/%d (%d%%)\n" "$scripts_with_debug" "$rutos_script_count" "$((scripts_with_debug * 100 / rutos_script_count))"
        printf "Scripts with TEST_MODE support: %d/%d (%d%%)\n" "$scripts_with_test_mode" "$rutos_script_count" "$((scripts_with_test_mode * 100 / rutos_script_count))"
        printf "Scripts with DRY_RUN support:   %d/%d (%d%%)\n" "$scripts_with_dry_run" "$rutos_script_count" "$((scripts_with_dry_run * 100 / rutos_script_count))"
        printf "Scripts with ALL patterns:      %d/%d (%d%%)\n" "$scripts_with_all_patterns" "$rutos_script_count" "$((scripts_with_all_patterns * 100 / rutos_script_count))"
    fi
    printf "\n"

    # Integration quality assessment
    if [ "$scripts_with_integration_issues" -gt 0 ]; then
        printf "${YELLOW}Scripts with integration issues: %d${NC}\n" "$scripts_with_integration_issues"
    else
        printf "${GREEN}✓ No debug integration issues found${NC}\n"
    fi

    # Recommendations
    if [ "$scripts_with_all_patterns" -lt "${#rutos_scripts[@]}" ]; then
        printf "\n${BLUE}RECOMMENDATIONS:${NC}\n"

        local missing_debug=$((${#rutos_scripts[@]} - scripts_with_debug))
        local missing_test=$((${#rutos_scripts[@]} - scripts_with_test_mode))
        local missing_dry=$((${#rutos_scripts[@]} - scripts_with_dry_run))

        [ "$missing_debug" -gt 0 ] && printf "• Add DEBUG support to %d more scripts for better troubleshooting\n" "$missing_debug"
        [ "$missing_test" -gt 0 ] && printf "• Add TEST_MODE support to %d more scripts for safer testing\n" "$missing_test"
        [ "$missing_dry" -gt 0 ] && printf "• Add DRY_RUN support to %d more scripts for safe execution\n" "$missing_dry"

        printf "• Complete integration enables: detailed troubleshooting, safe testing, and controlled execution\n"
    else
        printf "\n${GREEN}🎉 EXCELLENT: All RUTOS scripts have complete debug integration patterns!${NC}\n"
    fi

    printf "\n"
}

# Function to display issue summary by type
display_issue_summary() {
    if [ -z "$ISSUE_LIST" ]; then
        return 0
    fi

    printf "\n"
    printf "%s=== ISSUE BREAKDOWN ===%s\n" "$PURPLE" "$NC"
    printf "Most common issues found:\n\n"

    # Process the issue list to group by message type
    # Create a temporary file to process issues
    temp_file="/tmp/issue_summary_$$"

    # Write issues to temp file for processing
    printf "%s\n" "$ISSUE_LIST" >"$temp_file"

    # Group issues by ShellCheck code, markdown linting code, or other message types
    while IFS='|' read -r message file_path; do
        # Skip empty lines
        if [ -n "$message" ]; then
            # Check if this is a ShellCheck issue
            if echo "$message" | grep -q "^SC[0-9]*:"; then
                # Extract just the SC code and general description
                sc_code=$(echo "$message" | cut -d':' -f1)
                sc_desc=$(echo "$message" | cut -d':' -f2- | sed 's/^[[:space:]]*//')
                # Group by SC code, but show generic description
                case "$sc_code" in
                    "SC2034")
                        printf "%s: Variable appears unused in template/config file\n" "$sc_code"
                        ;;
                    "SC1090" | "SC1091")
                        printf "%s: Cannot follow dynamic source files\n" "$sc_code"
                        ;;
                    "SC2059")
                        printf "%s: Printf format string contains variables\n" "$sc_code"
                        ;;
                    "SC3045")
                        printf "%s: POSIX sh incompatible read options\n" "$sc_code"
                        ;;
                    "SC2030")
                        printf "%s: Variable modification in subshell\n" "$sc_code"
                        ;;
                    *)
                        printf "%s: %s\n" "$sc_code" "$sc_desc"
                        ;;
                esac
            # Check if this is a markdown linting issue
            elif echo "$message" | grep -q "^MD[0-9]*:"; then
                # Extract just the MD code and general description
                md_code=$(echo "$message" | cut -d':' -f1)
                md_desc=$(echo "$message" | cut -d':' -f2- | sed 's/^[[:space:]]*//')
                # Group by MD code, but show generic description
                case "$md_code" in
                    "MD001")
                        printf "%s: Heading levels should only increment by one level at a time\n" "$md_code"
                        ;;
                    "MD003")
                        printf "%s: Heading style should be consistent\n" "$md_code"
                        ;;
                    "MD004")
                        printf "%s: Unordered list style should be consistent\n" "$md_code"
                        ;;
                    "MD005")
                        printf "%s: Inconsistent indentation for list items\n" "$md_code"
                        ;;
                    "MD007")
                        printf "%s: Unordered list indentation should be consistent\n" "$md_code"
                        ;;
                    "MD009")
                        printf "%s: Trailing spaces detected\n" "$md_code"
                        ;;
                    "MD010")
                        printf "%s: Hard tabs detected\n" "$md_code"
                        ;;
                    "MD011")
                        printf "%s: Reversed link syntax\n" "$md_code"
                        ;;
                    "MD012")
                        printf "%s: Multiple consecutive blank lines\n" "$md_code"
                        ;;
                    "MD013")
                        printf "%s: Line length exceeds maximum\n" "$md_code"
                        ;;
                    "MD018")
                        printf "%s: No space after hash on atx style heading\n" "$md_code"
                        ;;
                    "MD019")
                        printf "%s: Multiple spaces after hash on atx style heading\n" "$md_code"
                        ;;
                    "MD020")
                        printf "%s: No space inside hashes on closed atx style heading\n" "$md_code"
                        ;;
                    "MD021")
                        printf "%s: Multiple spaces inside hashes on closed atx style heading\n" "$md_code"
                        ;;
                    "MD022")
                        printf "%s: Headings should be surrounded by blank lines\n" "$md_code"
                        ;;
                    "MD023")
                        printf "%s: Headings must start at the beginning of the line\n" "$md_code"
                        ;;
                    "MD024")
                        printf "%s: Multiple headings with the same content\n" "$md_code"
                        ;;
                    "MD025")
                        printf "%s: Multiple top level headings in the same document\n" "$md_code"
                        ;;
                    "MD026")
                        printf "%s: Trailing punctuation in heading\n" "$md_code"
                        ;;
                    "MD027")
                        printf "%s: Multiple spaces after blockquote symbol\n" "$md_code"
                        ;;
                    "MD028")
                        printf "%s: Blank line inside blockquote\n" "$md_code"
                        ;;
                    "MD029")
                        printf "%s: Ordered list item prefix should be consistent\n" "$md_code"
                        ;;
                    "MD030")
                        printf "%s: Spaces after list markers should be consistent\n" "$md_code"
                        ;;
                    "MD031")
                        printf "%s: Fenced code blocks should be surrounded by blank lines\n" "$md_code"
                        ;;
                    "MD032")
                        printf "%s: Lists should be surrounded by blank lines\n" "$md_code"
                        ;;
                    "MD033")
                        printf "%s: Inline HTML usage detected\n" "$md_code"
                        ;;
                    "MD034")
                        printf "%s: Bare URL used instead of proper link syntax\n" "$md_code"
                        ;;
                    "MD036")
                        printf "%s: Emphasis used instead of a heading\n" "$md_code"
                        ;;
                    "MD037")
                        printf "%s: Spaces inside emphasis markers\n" "$md_code"
                        ;;
                    "MD038")
                        printf "%s: Spaces inside code span elements\n" "$md_code"
                        ;;
                    "MD039")
                        printf "%s: Spaces inside link text\n" "$md_code"
                        ;;
                    "MD040")
                        printf "%s: Fenced code blocks should have a language specified\n" "$md_code"
                        ;;
                    "MD041")
                        printf "%s: First line in file should be a top level heading\n" "$md_code"
                        ;;
                    "MD042")
                        printf "%s: No empty links\n" "$md_code"
                        ;;
                    "MD043")
                        printf "%s: Required heading structure not followed\n" "$md_code"
                        ;;
                    "MD044")
                        printf "%s: Proper names should have the correct capitalization\n" "$md_code"
                        ;;
                    "MD045")
                        printf "%s: Images should have alternate text (alt text)\n" "$md_code"
                        ;;
                    "MD046")
                        printf "%s: Code block style should be consistent\n" "$md_code"
                        ;;
                    "MD047")
                        printf "%s: Files should end with a single newline character\n" "$md_code"
                        ;;
                    "MD048")
                        printf "%s: Code fence style should be consistent\n" "$md_code"
                        ;;
                    "MD049")
                        printf "%s: Emphasis style should be consistent\n" "$md_code"
                        ;;
                    "MD050")
                        printf "%s: Strong style should be consistent\n" "$md_code"
                        ;;
                    *)
                        printf "%s: %s\n" "$md_code" "$md_desc"
                        ;;
                esac
            # Check if this is a prettier formatting issue
            elif echo "$message" | grep -q "prettier formatting issues"; then
                printf "prettier: Markdown formatting issues detected\n"
            else
                # Other issues - show as is (strip any color codes for sorting)
                clean_message=$(printf "%s\n" "$message" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\$[A-Z_]*//g')
                printf "%s\n" "$clean_message"
            fi
        fi
    done <"$temp_file" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -nr >"${temp_file}.counts"

    # Display grouped results
    while read -r count message; do
        if [ -n "$message" ]; then
            # Count unique files for this message type
            if echo "$message" | grep -q "^SC[0-9]*:"; then
                # For ShellCheck codes, count files that have this specific code
                sc_code=$(echo "$message" | cut -d':' -f1)
                unique_files=$(grep "^$sc_code:" "$temp_file" | cut -d'|' -f2 | LC_ALL=C sort -u | wc -l)
            elif echo "$message" | grep -q "^MD[0-9]*:"; then
                # For markdown linting codes, count files that have this specific code
                md_code=$(echo "$message" | cut -d':' -f1)
                unique_files=$(grep "^$md_code:" "$temp_file" | cut -d'|' -f2 | LC_ALL=C sort -u | wc -l)
            elif echo "$message" | grep -q "^prettier:"; then
                # For prettier issues, count files with prettier formatting issues
                unique_files=$(grep -F "prettier formatting issues" "$temp_file" | cut -d'|' -f2 | LC_ALL=C sort -u | wc -l)
            else
                # For other issues, count normally
                unique_files=$(grep -F "$message|" "$temp_file" | cut -d'|' -f2 | LC_ALL=C sort -u | wc -l)
            fi
            printf "${YELLOW}%dx${NC} / ${CYAN}%d files${NC}: %s\n" "$count" "$unique_files" "$message"
        fi
    done <"${temp_file}.counts"

    # Clean up temp files
    rm -f "$temp_file" "${temp_file}.counts"

    printf "\n"
}

# Function to display summary
display_summary() {
    if [ "$AUTONOMOUS_MODE" = "1" ]; then
        display_autonomous_output
        return $?
    fi

    log_step "Generating validation summary"

    printf "\n"
    printf "%s=== VALIDATION SUMMARY ===%s\n" "$PURPLE" "$NC"
    printf "Files processed: %d\n" "$TOTAL_FILES"
    printf "Files passed: %d\n" "$PASSED_FILES"
    printf "Files failed: %d\n" "$FAILED_FILES"
    printf "\n"
    printf "Total issues: %d\n" "$TOTAL_ISSUES"
    printf "${RED}Critical issues: %d${NC}\n" "$CRITICAL_ISSUES"
    printf "${YELLOW}Major issues: %d${NC}\n" "$MAJOR_ISSUES"
    printf "${BLUE}Minor issues: %d${NC}\n" "$MINOR_ISSUES"
    printf "\n"

    # Show issue breakdown if there are issues
    if [ $TOTAL_ISSUES -gt 0 ]; then
        display_issue_summary
    fi

    # Always show debug integration patterns summary for analyzed files
    display_debug_integration_summary "$shell_files"

    if [ $TOTAL_ISSUES -eq 0 ]; then
        log_success "All validations passed!"
        return 0
    else
        log_error "Validation failed with $TOTAL_ISSUES issues"
        return 1
    fi
}

# Function to display autonomous output
display_autonomous_output() {
    # Generate JSON output
    local json_output
    json_output=$(
        cat <<EOF
{
  "validation_summary": {
    "script_version": "$SCRIPT_VERSION",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "total_files": $TOTAL_FILES,
    "passed_files": $PASSED_FILES,
    "failed_files": $FAILED_FILES,
    "total_issues": $TOTAL_ISSUES,
    "critical_issues": $CRITICAL_ISSUES,
    "major_issues": $MAJOR_ISSUES,
    "minor_issues": $MINOR_ISSUES
  },
  "issues": [
EOF

        # Output each issue as JSON
        if [ -n "$AUTONOMOUS_ISSUES" ]; then
            first_issue=1
            printf '%s\n' "$AUTONOMOUS_ISSUES" | while IFS= read -r issue; do
                if [ -n "$issue" ]; then
                    if [ "$first_issue" = "1" ]; then
                        printf "    %s" "$issue"
                        first_issue=0
                    else
                        printf ",\n    %s" "$issue"
                    fi
                fi
            done
            printf "\n"
        fi

        cat <<EOF
  ],
  "fix_recommendations": {
    "priority_1_critical": $CRITICAL_ISSUES,
    "priority_2_major_syntax": $(echo "$AUTONOMOUS_ISSUES" | grep -c '"category":"function_syntax"\\|"category":"exit_code"' || echo 0),
    "priority_3_unused_vars": $(echo "$AUTONOMOUS_ISSUES" | grep -c '"category":"unused_' || echo 0),
    "priority_4_optimizations": $(echo "$AUTONOMOUS_ISSUES" | grep -c '"category":"grep_optimization"\\|"category":"read_safety"' || echo 0),
    "priority_5_minor": $MINOR_ISSUES
  }
}
EOF
    )

    # Apply filtering if specified
    if [ -n "$SHOW_FIRST" ] || [ -n "$SHOW_LAST" ] || [ -n "$FILTER_PATTERN" ]; then
        json_output=$(apply_output_filters "$json_output")
    fi

    printf "%s\n" "$json_output"

    # Return appropriate exit code
    if [ $TOTAL_ISSUES -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to display help
show_help() {
    cat <<EOF
RUTOS Busybox Compatibility and Markdown Validation Script

Usage: $0 [OPTIONS] [FILES...]

OPTIONS:
    --staged        Validate only staged files (for git pre-commit hook)
    --all           Validate all shell and markdown files in the repository
    --shell-only    Validate only shell script files
    --md-only       Validate only markdown files
    --autonomous    Output structured JSON for autonomous fixing (no colors, machine-readable)
    --first N       Show only first N lines of output (like head -N)
    --last N        Show only last N lines of output (like tail -N)
    --filter REGEX  Filter output lines matching regex pattern (like grep)
    --help, -h      Show this help message

EXAMPLES:
    $0                              # Validate all shell and markdown files
    $0 --all                        # Same as above, but explicit
    $0 --staged                     # Validate only staged files (git hook mode)
    $0 --shell-only                 # Validate only shell scripts
    $0 --md-only                    # Validate only markdown files
    $0 --autonomous                 # Output structured JSON for autonomous fixing
    $0 file1.sh file2.md            # Validate specific files
    $0 scripts/*.sh                 # Validate all files in scripts directory

DESCRIPTION:
    This script validates shell scripts for RUTOS/busybox compatibility and
    markdown files for documentation quality by checking:
    
    SHELL SCRIPTS:
    - RUTOS scripts (*-rutos.sh): Validated for POSIX/busybox compatibility
      * Shebang compatibility (#!/bin/sh required)
      * No bash-specific syntax (local, [[]], arrays, etc.)
    - Development scripts: Can use modern bash features
    - This validation script itself: Uses bash for efficiency
    - Bash-specific syntax (arrays, double brackets, etc.) for RUTOS scripts
    - Echo -e usage (should use printf instead) for RUTOS scripts
    - Source command usage (should use . instead) for RUTOS scripts
    - Function syntax compatibility for RUTOS scripts
    - ShellCheck validation in POSIX mode for *-rutos.sh files, bash mode for others
    - RUTOS naming convention compliance (*-rutos.sh for RUTOS-target scripts)
    - shfmt formatting (with auto-fix)
    
    MARKDOWN FILES:
    - markdownlint validation
    - prettier formatting (with auto-fix)

    AUTO-FIXING:
    The script automatically fixes formatting issues using:
    - shfmt for shell scripts
    - prettier for markdown files
    
    After auto-fixes are applied, the script re-validates to ensure 
    issues are resolved.

    EXCLUDED FILES:
    The following files are automatically excluded from validation:
    - scripts/pre-commit-validation.sh (this script)
    - scripts/setup-code-quality-tools.sh (development tool)
    - scripts/comprehensive-validation.sh (development tool)

EXIT CODES:
    0    All validations passed
    1    One or more files failed validation
EOF
}

# Function to parse .gitignore and generate find exclusions
parse_gitignore_exclusions() {
    gitignore_file=".gitignore"
    exclusions=""

    if [ -f "$gitignore_file" ]; then
        # Read .gitignore and convert patterns to find exclusions
        while read -r line; do
            # Skip empty lines and comments
            if [ -n "$line" ] && ! echo "$line" | grep -q "^#"; then
                # Remove leading/trailing whitespace
                pattern=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                if [ -n "$pattern" ]; then
                    # Convert gitignore patterns to find exclusions
                    if echo "$pattern" | grep -q "/$"; then
                        # Directory pattern (ends with /)
                        dir_pattern=${pattern%/}
                        exclusions="$exclusions -not -path \"./$dir_pattern/*\""
                    elif echo "$pattern" | grep -q "\*"; then
                        # Wildcard pattern - handle as name pattern
                        exclusions="$exclusions -not -name \"$pattern\""
                    else
                        # Regular file/directory pattern
                        exclusions="$exclusions -not -path \"./$pattern\" -not -path \"./$pattern/*\""
                    fi
                fi
            fi
        done <"$gitignore_file"

        log_debug "Generated gitignore exclusions: $exclusions"
    fi

    # Always exclude standard patterns first (these override gitignore)
    standard_exclusions="-not -path \"./node_modules/*\" -not -path \"./.git/*\" -not -path \"./.github/*\""

    # Combine standard exclusions with gitignore patterns
    all_exclusions="$standard_exclusions $exclusions"

    echo "$all_exclusions"
}

# Built-in output filtering functions to avoid external command dependencies
apply_output_filters() {
    local input="$1"
    local output="$input"

    # Apply first N lines filter (like head -N)
    if [ -n "$SHOW_FIRST" ]; then
        output=$(printf "%s" "$output" | {
            line_count=0
            while IFS= read -r line && [ $line_count -lt "$SHOW_FIRST" ]; do
                printf "%s\n" "$line"
                line_count=$((line_count + 1))
            done
        })
    fi

    # Apply last N lines filter (like tail -N)
    if [ -n "$SHOW_LAST" ]; then
        # For tail functionality, we need to buffer all lines and show the last N
        temp_file="/tmp/filter_output_$$"
        printf "%s" "$output" >"$temp_file"
        total_lines=$(wc -l <"$temp_file" | tr -d ' \n\r')
        if [ "$total_lines" -gt "$SHOW_LAST" ]; then
            skip_lines=$((total_lines - SHOW_LAST))
            output=$(awk "NR > $skip_lines" "$temp_file")
        else
            output=$(cat "$temp_file")
        fi
        rm -f "$temp_file"
    fi

    # Apply regex filter (like grep)
    if [ -n "$FILTER_PATTERN" ]; then
        output=$(printf "%s" "$output" | while IFS= read -r line; do
            if printf "%s" "$line" | grep -q "$FILTER_PATTERN"; then
                printf "%s\n" "$line"
            fi
        done)
    fi

    printf "%s" "$output"
}

# Parse command line arguments for filtering options
parse_filtering_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --first)
                shift
                SHOW_FIRST="$1"
                if ! printf "%s" "$SHOW_FIRST" | grep -q '^[0-9][0-9]*$'; then
                    printf "Error: --first requires a positive integer\n" >&2
                    exit 1
                fi
                ;;
            --last)
                shift
                SHOW_LAST="$1"
                if ! printf "%s" "$SHOW_LAST" | grep -q '^[0-9][0-9]*$'; then
                    printf "Error: --last requires a positive integer\n" >&2
                    exit 1
                fi
                ;;
            --filter)
                shift
                FILTER_PATTERN="$1"
                ;;
            --autonomous)
                AUTONOMOUS_MODE=1
                ;;
        esac
        shift
    done
}

# Main function
main() {
    # Parse filtering arguments first (before any output)
    parse_filtering_args "$@"

    log_info "Starting RUTOS busybox compatibility and markdown validation v$SCRIPT_VERSION"

    # Skip self-validation
    log_step "Self-validation: Skipped - this script is excluded from validation"

    # Check for available development tools and suggest installation if missing
    if [ "${DEBUG:-0}" = "1" ]; then
        check_dev_tools
    fi

    local shell_files=""
    local markdown_files=""

    # Check if running with specific files
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        show_help
        exit 0
    elif [ "$1" = "--autonomous" ]; then
        AUTONOMOUS_MODE=1
        # Disable colors for autonomous mode
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        PURPLE=""
        CYAN=""
        NC=""
        log_info "Running in autonomous mode (structured JSON output)"
        # Get all shell and markdown files for autonomous analysis
        exclusions=$(parse_gitignore_exclusions)
        shell_files=$(eval "find . -name \"*.sh\" -type f $exclusions" | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
        markdown_files=$(eval "find . -name \"*.md\" -type f $exclusions" | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
    elif [ "$1" = "--staged" ]; then
        log_info "Running in pre-commit mode (staged files only)"
        # Get staged shell and markdown files, excluding specified files
        shell_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
        markdown_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' | LC_ALL=C sort)
    elif [ "$1" = "--all" ]; then
        log_info "Running in comprehensive validation mode (all shell and markdown files)"
        # Get exclusion patterns from .gitignore
        exclusions=$(parse_gitignore_exclusions)

        # Get all shell and markdown files, respecting .gitignore
        shell_files=$(eval "find . -name \"*.sh\" -type f $exclusions" | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
        markdown_files=$(eval "find . -name \"*.md\" -type f $exclusions" | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
    elif [ "$1" = "--shell-only" ]; then
        log_info "Running in shell-only validation mode"
        # Get exclusion patterns from .gitignore
        exclusions=$(parse_gitignore_exclusions)

        # Get all shell files, respecting .gitignore
        shell_files=$(eval "find . -name \"*.sh\" -type f $exclusions" | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
    elif [ "$1" = "--md-only" ]; then
        log_info "Running in markdown-only validation mode"
        # Get exclusion patterns from .gitignore
        exclusions=$(parse_gitignore_exclusions)

        # Get all markdown files, respecting .gitignore
        markdown_files=$(eval "find . -name \"*.md\" -type f $exclusions" | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
    elif [ $# -gt 0 ]; then
        log_info "Running in specific file mode"
        # Process specific files based on extension
        for file in "$@"; do
            case "$file" in
                *.sh)
                    if ! is_excluded "$file"; then
                        shell_files="$shell_files $file"
                    fi
                    ;;
                *.md)
                    markdown_files="$markdown_files $file"
                    ;;
                *)
                    log_warning "Unsupported file type: $file (only .sh and .md supported)"
                    ;;
            esac
        done
    else
        log_info "Running in full validation mode (all shell and markdown files)"
        # Get exclusion patterns from .gitignore
        exclusions=$(parse_gitignore_exclusions)

        # Get all shell and markdown files, respecting .gitignore
        shell_files=$(eval "find . -name \"*.sh\" -type f $exclusions" | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
        markdown_files=$(eval "find . -name \"*.md\" -type f $exclusions" | while read -r file; do
            if ! is_excluded "$file"; then
                echo "$file"
            fi
        done | LC_ALL=C sort)
    fi

    # Count total files
    local total_files=0
    for file in $shell_files $markdown_files; do
        if [ -f "$file" ]; then
            total_files=$((total_files + 1))
        fi
    done

    if [ $total_files -eq 0 ]; then
        log_warning "No files found to validate"
        return 0
    fi

    log_step "Processing $total_files files"

    # Validate shell files
    if [ -n "$shell_files" ]; then
        log_info "Validating shell script files"
        for file in $shell_files; do
            if [ -f "$file" ]; then
                TOTAL_FILES=$((TOTAL_FILES + 1))
                validate_file "$file"
            else
                log_debug "Skipping non-existent file: $file"
            fi
        done
    fi

    # Validate markdown files
    if [ -n "$markdown_files" ]; then
        log_info "Validating markdown files"
        for file in $markdown_files; do
            if [ -f "$file" ]; then
                TOTAL_FILES=$((TOTAL_FILES + 1))
                validate_markdown_file "$file"
            else
                log_debug "Skipping non-existent file: $file"
            fi
        done
    fi

    # Display summary
    if [ -n "$SHOW_FIRST" ] || [ -n "$SHOW_LAST" ] || [ -n "$FILTER_PATTERN" ]; then
        # Capture output and apply filtering
        summary_output=$(display_summary 2>&1)
        filtered_output=$(apply_output_filters "$summary_output")
        printf "%s\n" "$filtered_output"
        # Return the actual validation status
        if [ $TOTAL_ISSUES -eq 0 ]; then
            return 0
        else
            return 1
        fi
    else
        # Normal display without filtering
        if ! display_summary; then
            return 1
        fi
    fi

    return 0
}

# Execute main function
main "$@"
