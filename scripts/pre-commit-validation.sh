#!/bin/bash
# Pre-commit validation script for RUTOS Starlink Failover Project
# Version: 1.0.4
# Description: Comprehensive validation of shell scripts for RUTOS/busybox compatibility,
#              PowerShell scripts for automation quality, and markdown files for documentation
#
# NOTE: This script runs in the development environment (WSL/Linux), NOT on RUTOS,
# so it can use modern bash features for efficiency. It validates OTHER scripts
# for RUTOS compatibility but is excluded from its own validation checks.

# NOTE: We don't use 'set -e' here because we want to continue processing all files
# and collect all validation issues before exiting

# Version information
SCRIPT_VERSION="1.0.4"

# Files to exclude from validation (patterns supported)
# Files to exclude from validation
EXCLUDED_FILES=(
	"scripts/pre-commit-validation.sh"
	"scripts/setup-code-quality-tools.sh"
	"scripts/comprehensive-validation.sh"
)

# Standard colors for consistent output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'  # Bright magenta instead of dark blue for better readability
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
# More comprehensive check for git hook environments
if [ "$NO_COLOR" = "1" ] || [ "$TERM" = "dumb" ] || [ -z "$TERM" ] || ([ ! -t 1 ] && [ ! -t 2 ]); then
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
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
	log_debug "Script version: $SCRIPT_VERSION"
	log_debug "Working directory: $(pwd)"
	log_debug "Arguments: $*"
fi

# Validation counters
TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
TOTAL_ISSUES=0
CRITICAL_ISSUES=0
MAJOR_ISSUES=0
MINOR_ISSUES=0

# Issue tracking for summary (format: "issue_type|file_path")
ISSUE_LIST=""

# Function to check if a file should be excluded
# Function to check if a file should be excluded
is_excluded() {
	local file="$1"
	local pattern
	
	# Normalize path to handle both relative and absolute paths
	local normalized_path
	normalized_path=$(echo "$file" | sed 's|^\./||' | sed 's|\\|/|g')
	
	# Check if file is in excluded list
	for pattern in "${EXCLUDED_FILES[@]}"; do
		if [[ "$normalized_path" == *"$pattern"* ]]; then
			return 0  # File is excluded
		fi
	done
	
	return 1  # File is not excluded
}

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

	# Add to issue list for summary (format: "message|file_path")
	if [ -n "$ISSUE_LIST" ]; then
		ISSUE_LIST="${ISSUE_LIST}
${message}|${file}"
	else
		ISSUE_LIST="${message}|${file}"
	fi

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

# Function to check bash-specific syntax (simplified version)
check_bash_syntax() {
	file="$1"

	# Check for double brackets (bash-style conditions, not regex patterns)
	if grep -n "if[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			report_issue "CRITICAL" "$file" "$line_num" "Uses double brackets [[ ]] - use single brackets [ ] for busybox"
		done < <(grep -n "if[[:space:]]*\[\[.*\]\]" "$file" 2>/dev/null)
	fi

	# Check for double brackets in while loops
	if grep -n "while[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			report_issue "CRITICAL" "$file" "$line_num" "Uses double brackets [[ ]] - use single brackets [ ] for busybox"
		done < <(grep -n "while[[:space:]]*\[\[.*\]\]" "$file" 2>/dev/null)
	fi

	# Check for standalone double bracket conditions
	if grep -n "^[[:space:]]*\[\[.*\]\]" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			# Skip if it's a POSIX character class like [[:space:]]
			if ! echo "$line_content" | grep -q "\[\[:[a-z]*:\]\]"; then
				report_issue "CRITICAL" "$file" "$line_num" "Uses double brackets [[ ]] - use single brackets [ ] for busybox"
			fi
		done < <(grep -n "^[[:space:]]*\[\[.*\]\]" "$file" 2>/dev/null)
	fi

	# Check for local keyword
	if grep -n "^[[:space:]]*local " "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			report_issue "CRITICAL" "$file" "$line_num" "Uses 'local' keyword - not supported in busybox"
		done < <(grep -n "^[[:space:]]*local " "$file" 2>/dev/null)
	fi

	# Check for echo -e
	if grep -n "echo -e" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			report_issue "MAJOR" "$file" "$line_num" "Uses 'echo -e' - use printf for busybox compatibility"
		done < <(grep -n "echo -e" "$file" 2>/dev/null)
	fi

	# Check for source command (but not in echo statements)
	if grep -n "source " "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			# Skip if it's within an echo statement (documentation)
			if ! echo "$line_content" | grep -q "echo.*source"; then
				report_issue "MAJOR" "$file" "$line_num" "Uses 'source' command - use '.' (dot) for busybox"
			fi
		done < <(grep -n "source " "$file" 2>/dev/null)
	fi

	# Check for arrays
	if grep -n "declare -[aA]" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			report_issue "CRITICAL" "$file" "$line_num" "Uses arrays (declare -a) - not supported in busybox"
		done < <(grep -n "declare -[aA]" "$file" 2>/dev/null)
	fi

	# Check for function() syntax (the actual 'function' keyword, not function names containing 'function')
	if grep -n "^[[:space:]]*function[[:space:]]\+[[:alnum:]_]\+[[:space:]]*(" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			report_issue "MAJOR" "$file" "$line_num" "Uses function() syntax - use function_name() { } for busybox"
		done < <(grep -n "^[[:space:]]*function[[:space:]]\+[[:alnum:]_]\+[[:space:]]*(" "$file" 2>/dev/null)
	fi

	return 0
}

# Function to validate color code usage
validate_color_codes() {
	file="$1"

	# Check for direct color codes in printf statements (should use variables)
	if grep -n "printf.*\\\\033\[" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			report_issue "MAJOR" "$file" "$line_num" "Uses hardcoded color codes in printf - use color variables instead"
		done < <(grep -n "printf.*\\\\033\[" "$file" 2>/dev/null)
	fi

	# Check for echo with color codes (should use printf)
	if grep -n "echo.*\\\\033\[" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			report_issue "MAJOR" "$file" "$line_num" "Uses echo with color codes - use printf for better compatibility"
		done < <(grep -n "echo.*\\\\033\[" "$file" 2>/dev/null)
	fi

	# Check for problematic printf patterns with color variables but missing proper format
	if grep -n "printf.*\\\${[A-Z_]*}.*%s.*\\\${[A-Z_]*}" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			# Only flag if it looks like color codes might be getting literal output
			if echo "$line_content" | grep -q 'printf.*"[^"]*\\\${[A-Z_]*}[^"]*".*[^%]s'; then
				report_issue "MINOR" "$file" "$line_num" "Complex printf with colors - verify format string handles colors correctly"
			fi
		done < <(grep -n "printf.*\\\${[A-Z_]*}.*%s.*\\\${[A-Z_]*}" "$file" 2>/dev/null)
	fi

	# Check for printf without proper format when using color variables
	if grep -n "printf.*\\\${[A-Z_]*}.*[^%][^s]\"" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			# Check if it's a printf that ends with a variable (not a format string)
			if echo "$line_content" | grep -q 'printf.*\\\${[A-Z_]*}$'; then
				report_issue "MAJOR" "$file" "$line_num" "printf ending with color variable - missing format string or text"
			fi
		done < <(grep -n "printf.*\\\${[A-Z_]*}.*[^%][^s]\"" "$file" 2>/dev/null)
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
		
		# Check if all required colors are defined
		required_colors=("RED" "GREEN" "YELLOW" "BLUE" "CYAN" "NC")
		missing_colors=()
		
		for color in "${required_colors[@]}"; do
			if ! grep -q "^[[:space:]]*$color=" "$file"; then
				missing_colors+=("$color")
			fi
		done
		
		if [ ${#missing_colors[@]} -gt 0 ]; then
			missing_list=$(printf "%s " "${missing_colors[@]}")
			report_issue "MAJOR" "$file" "0" "Missing color definitions: ${missing_list% } - all scripts should define RED, GREEN, YELLOW, BLUE, CYAN, NC"
		else
			log_debug "✓ $file: All required colors defined"
		fi
		
	elif grep -n "NO_COLOR\|TERM.*dumb" "$file" >/dev/null 2>&1; then
		# This is good - checking for NO_COLOR or dumb terminal
		log_debug "✓ $file: Has NO_COLOR detection"
	elif grep -n "^[[:space:]]*RED=\|^[[:space:]]*GREEN=\|^[[:space:]]*YELLOW=" "$file" >/dev/null 2>&1; then
		# Has color definitions but no detection - potential issue
		if ! grep -q "if.*-t.*1\|NO_COLOR\|TERM.*dumb" "$file"; then
			report_issue "MAJOR" "$file" "0" "Defines colors but missing color detection logic - add RUTOS-compatible detection: if [ -t 1 ] && [ \"\${TERM:-}\" != \"dumb\" ] && [ \"\${NO_COLOR:-}\" != \"1\" ]"
		fi
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

	# Determine shell type based on filename
	# RUTOS scripts (ending with -rutos.sh) use POSIX mode
	# Other scripts use bash mode
	if echo "$file" | grep -q -- '-rutos\.sh$'; then
		shell_type="sh"
		log_debug "Using POSIX mode for RUTOS script: $file"
	else
		shell_type="bash"
		log_debug "Using bash mode for development script: $file"
	fi

	# Run shellcheck with appropriate shell mode and capture output
	shellcheck_output=$(shellcheck -s "$shell_type" "$file" 2>&1)

	if [ $? -eq 0 ]; then
		log_debug "✓ $file: Passes ShellCheck validation"
		return 0
	else
		log_warning "$file: ShellCheck found issues"
		echo "$shellcheck_output" | head -10

		# Parse ShellCheck output to extract error codes - avoid subshell
		# Save output to temp file to avoid subshell issues
		temp_file=$(mktemp)
		echo "$shellcheck_output" >"$temp_file"

		# Parse the output line by line
		line_num=""
		while IFS= read -r line; do
			if echo "$line" | grep -q "^In.*line [0-9]+:"; then
				line_num=$(echo "$line" | sed 's/.*line \([0-9]*\):.*/\1/')
			elif echo "$line" | grep -qE "SC[0-9]+"; then
				sc_code=$(echo "$line" | sed 's/.*\(SC[0-9]*\).*/\1/')
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

	# Run shfmt to check formatting
	if ! shfmt -d "$file" >/dev/null 2>&1; then
		log_debug "shfmt found formatting issues in $file"

		# Count the number of formatting issues (lines of diff output)
		diff_lines=$(shfmt -d "$file" 2>/dev/null | wc -l)

		if [ "$diff_lines" -gt 0 ]; then
			report_issue "MAJOR" "$file" "0" "shfmt formatting issues - run 'shfmt -w $file' to fix"
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

	# Check for common color variables that might be undefined
	local color_vars="RED GREEN YELLOW BLUE PURPLE CYAN NC"
	
	for var in $color_vars; do
		# Check if variable is used before definition
		if grep -n "\$$var\|\".*\$\{$var\}" "$file" >/dev/null 2>&1; then
			# Find first usage
			first_usage=$(grep -n "\$$var\|\".*\$\{$var\}" "$file" | head -1 | cut -d: -f1)
			
			# Find definition line
			definition_line=$(grep -n "^[[:space:]]*$var=" "$file" | head -1 | cut -d: -f1)
			
			# If variable is used but not defined, or used before definition
			if [ -z "$definition_line" ]; then
				report_issue "CRITICAL" "$file" "$first_usage" "Variable \$$var is used but not defined"
			elif [ "$first_usage" -lt "$definition_line" ]; then
				report_issue "CRITICAL" "$file" "$first_usage" "Variable \$$var is used before it's defined (line $definition_line)"
			fi
		fi
	done

	# Check for variables used in parameter expansion that might be undefined
	if grep -n "\${[A-Z_]*}" "$file" >/dev/null 2>&1; then
		while IFS=: read -r line_num line_content; do
			# Extract variable name from ${VAR} or ${VAR:-default}
			var_name=$(echo "$line_content" | sed -n 's/.*\${\([A-Z_]*\)[:-].*/\1/p')
			if [ -z "$var_name" ]; then
				var_name=$(echo "$line_content" | sed -n 's/.*\${\([A-Z_]*\)}.*/\1/p')
			fi
			
			# Skip if no variable name found or if it's a known environment variable
			if [ -n "$var_name" ] && ! echo "$var_name" | grep -Eq "^(PATH|HOME|USER|DEBUG|GITHUB_|LOG_|SCRIPT_|BASE_|VERSION_|INSTALL_|CRON_|HOTPLUG_|GRPCURL_|JQ_|MIN_)"; then
				# Check if this variable is defined in the file
				if ! grep -q "^[[:space:]]*$var_name=" "$file"; then
					# Check if the file sources a config file and the variable is defined there
					variable_found=0
					
					# Check if the file sources config.sh or config.template.sh
					if grep -q '\. "\$' "$file" || grep -q 'source "\$' "$file" || grep -q '\. [^"]*config\.sh' "$file" || grep -q 'source [^"]*config\.sh' "$file"; then
						# Check in config template files
						for config_file in "config/config.template.sh" "config/config.advanced.template.sh"; do
							if [ -f "$config_file" ] && grep -q "^[[:space:]]*export[[:space:]]*$var_name=" "$config_file"; then
								variable_found=1
								break
							fi
						done
					fi
					
					# Only report if variable is not found in sourced config files
					if [ "$variable_found" -eq 0 ]; then
						report_issue "MAJOR" "$file" "$line_num" "Variable \$$var_name might be undefined - check if it's defined earlier"
					fi
				fi
			fi
		done < <(grep -n "\${[A-Z_]*}" "$file" 2>/dev/null)
	fi

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

# Function to validate a single shell script file
validate_file() {
	file="$1"

	log_step "Validating: $file"

	initial_issues=$TOTAL_ISSUES

	# Try to auto-fix formatting issues first
	if auto_fix_formatting "$file"; then
		log_info "Applied auto-fixes to $file"
	fi

	# Check shebang
	check_shebang "$file"

	# Check bash-specific syntax
	check_bash_syntax "$file"

	# Check for undefined variables
	check_undefined_variables "$file"

	# Validate color code usage
	validate_color_codes "$file"

	# Run ShellCheck
	run_shellcheck "$file"

	# Run shfmt formatting validation (after potential auto-fixes)
	run_shfmt "$file"

	# Check for undefined variables
	check_undefined_variables "$file"

	# Calculate issues for this file
	file_issues=$((TOTAL_ISSUES - initial_issues))

	if [ $file_issues -eq 0 ]; then
		log_success "✓ $file: All checks passed"
		PASSED_FILES=$((PASSED_FILES + 1))
	else
		log_error "✗ $file: $file_issues issues found"
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
			# Auto-fix shell script formatting with shfmt
			if command_exists shfmt; then
				if ! shfmt -d "$file" >/dev/null 2>&1; then
					log_info "Auto-fixing shell script formatting: $file"
					shfmt -w "$file"
					fixes_applied=1
				fi
			fi
			;;
		"ps1")
			# Auto-fix PowerShell script formatting
			if command_exists pwsh; then
				log_debug "PowerShell formatting: Using pwsh for $file"
				# PowerShell formatting will be handled in validation
				# For now, we don't auto-fix PowerShell formatting
			elif command_exists powershell; then
				log_debug "PowerShell formatting: Using powershell for $file"
				# PowerShell formatting will be handled in validation
				# For now, we don't auto-fix PowerShell formatting
			fi
			;;
		"md")
			# Auto-fix markdown formatting with prettier
			if command_exists prettier; then
				# Check if prettier would make changes
				if ! prettier --check "$file" >/dev/null 2>&1; then
					log_info "Auto-fixing markdown formatting: $file"
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
		return 0
	fi
	
	# Run markdownlint and capture output
	markdownlint_output=$(markdownlint "$file" 2>&1)
	
	if [ $? -eq 0 ]; then
		log_debug "✓ $file: Passes markdownlint validation"
		return 0
	else
		log_warning "$file: markdownlint found issues"
		
		# Parse markdownlint output using a temporary file to avoid subshell
		temp_file="/tmp/markdownlint_$$"
		echo "$markdownlint_output" > "$temp_file"
		
		while IFS= read -r line; do
			if [[ "$line" =~ ^([^:]+):([0-9]+).*MD([0-9]+)(.*)$ ]]; then
				file_path="${BASH_REMATCH[1]}"
				line_num="${BASH_REMATCH[2]}"
				md_code="MD${BASH_REMATCH[3]}"
				description="${BASH_REMATCH[4]}"
				report_issue "MAJOR" "$file_path" "$line_num" "$md_code:$description"
			fi
		done < "$temp_file"
		
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
	
	log_step "Validating: $file"
	
	local initial_issues=$TOTAL_ISSUES
	
	# Try to auto-fix formatting issues first
	if auto_fix_formatting "$file"; then
		log_info "Applied auto-fixes to $file"
	fi
	
	# Run markdownlint validation
	run_markdownlint "$file"
	
	# Run prettier validation (after potential auto-fixes)
	run_prettier_markdown "$file"
	
	# Calculate issues for this file
	local file_issues=$((TOTAL_ISSUES - initial_issues))
	
	if [ $file_issues -eq 0 ]; then
		log_success "✓ $file: All checks passed"
		PASSED_FILES=$((PASSED_FILES + 1))
	else
		log_error "✗ $file: $file_issues issues found"
		FAILED_FILES=$((FAILED_FILES + 1))
	fi
	
	return $file_issues
}

# Function to run PSScriptAnalyzer validation
run_psscriptanalyzer() {
	local file="$1"
	
	# Check if PowerShell and PSScriptAnalyzer are available
	if command_exists pwsh; then
		log_debug "Running PSScriptAnalyzer on $file using pwsh"
		
		# Check if PSScriptAnalyzer module is available
		if pwsh -Command "Get-Module -ListAvailable PSScriptAnalyzer" >/dev/null 2>&1; then
			# Run PSScriptAnalyzer and capture output
			pssa_output=$(pwsh -Command "Invoke-ScriptAnalyzer -Path '$file' -Severity @('Error', 'Warning', 'Information') | ForEach-Object { \"\$(\$_.Severity)|\$(\$_.RuleName)|\$(\$_.Message)|\$(\$_.Line)\" }" 2>&1)
			
			if [ $? -eq 0 ] && [ -n "$pssa_output" ]; then
				# Parse PSScriptAnalyzer output
				while IFS='|' read -r severity rule message line_num; do
					if [ -n "$severity" ] && [ -n "$rule" ] && [ -n "$message" ] && [ -n "$line_num" ]; then
						case "$severity" in
							"Error")
								report_issue "CRITICAL" "$file" "$line_num" "$rule: $message"
								;;
							"Warning")
								report_issue "MAJOR" "$file" "$line_num" "$rule: $message"
								;;
							"Information")
								report_issue "MINOR" "$file" "$line_num" "$rule: $message"
								;;
						esac
					fi
				done <<< "$pssa_output"
			else
				log_debug "✓ $file: Passes PSScriptAnalyzer validation"
			fi
		else
			log_warning "PSScriptAnalyzer module not available - skipping advanced PowerShell validation"
		fi
	elif command_exists powershell; then
		log_debug "PowerShell Core (pwsh) not available, trying Windows PowerShell"
		log_warning "For best results, install PowerShell Core and PSScriptAnalyzer module"
	else
		log_warning "PowerShell not available - skipping PowerShell validation"
	fi
}

# Function to run PowerShell syntax check
run_powershell_syntax_check() {
	local file="$1"
	
	if command_exists pwsh; then
		log_debug "Running PowerShell syntax check on $file"
		
		# Use PowerShell's parser to check syntax
		syntax_check=$(pwsh -Command "try { \$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content '$file' -Raw), [ref]\$null); Write-Output 'SYNTAX_OK' } catch { Write-Output \"SYNTAX_ERROR: \$(\$_.Exception.Message)\" }" 2>&1)
		
		if [[ "$syntax_check" == "SYNTAX_OK" ]]; then
			log_debug "✓ $file: PowerShell syntax is valid"
		else
			report_issue "CRITICAL" "$file" "0" "PowerShell Syntax Error: ${syntax_check#SYNTAX_ERROR: }"
		fi
	fi
}

# Function to check PowerShell automation patterns
check_powershell_automation_patterns() {
	local file="$1"
	local line_number=0
	
	log_debug "Checking PowerShell automation patterns in $file"
	
	while IFS= read -r line; do
		line_number=$((line_number + 1))
		
		# Check for hardcoded credentials
		if echo "$line" | grep -qi "password\s*=\s*['\"][^'\"]*['\"]"; then
			report_issue "CRITICAL" "$file" "$line_number" "Security: Hardcoded password detected"
		fi
		
		# Check for hardcoded API keys
		if echo "$line" | grep -qi "api[_-]key\s*=\s*['\"][^'\"]*['\"]"; then
			report_issue "CRITICAL" "$file" "$line_number" "Security: Hardcoded API key detected"
		fi
		
		# Check for Write-Host usage (prefer Write-Output)
		if echo "$line" | grep -q "Write-Host"; then
			report_issue "MINOR" "$file" "$line_number" "Best Practice: Consider using Write-Output instead of Write-Host for better pipeline support"
		fi
		
		# Check for Invoke-Expression usage (security risk)
		if echo "$line" | grep -q "Invoke-Expression\|iex"; then
			report_issue "MAJOR" "$file" "$line_number" "Security: Invoke-Expression can be a security risk - consider alternatives"
		fi
		
		# Check for cmdlet parameter validation
		if echo "$line" | grep -q "param\s*(" && ! echo "$line" | grep -q "\[Parameter"; then
			report_issue "MINOR" "$file" "$line_number" "Best Practice: Consider adding parameter validation attributes"
		fi
		
	done < "$file"
	
	# Check for try blocks without catch blocks (file-level check)
	if grep -q "try\s*{" "$file" && ! grep -q "catch" "$file"; then
		report_issue "MAJOR" "$file" "0" "Error Handling: Try block found without corresponding catch block"
	fi
}

# Function to validate PowerShell script file
validate_powershell_file() {
	local file="$1"
	
	log_step "Validating PowerShell script: $file"
	
	local initial_issues=$TOTAL_ISSUES
	
	# Try to auto-fix formatting issues first
	if auto_fix_formatting "$file"; then
		log_info "Applied auto-fixes to $file"
	fi
	
	# Run PSScriptAnalyzer validation if available
	run_psscriptanalyzer "$file"
	
	# Run PowerShell syntax validation
	run_powershell_syntax_check "$file"
	
	# Check for common PowerShell automation issues
	check_powershell_automation_patterns "$file"
	
	# Calculate issues for this file
	local file_issues=$((TOTAL_ISSUES - initial_issues))
	
	if [ $file_issues -eq 0 ]; then
		log_success "✓ $file: All checks passed"
		PASSED_FILES=$((PASSED_FILES + 1))
	else
		log_error "✗ $file: $file_issues issues found"
		FAILED_FILES=$((FAILED_FILES + 1))
	fi
	
	return $file_issues
}

# Function to display issue summary by type
display_issue_summary() {
	if [ -z "$ISSUE_LIST" ]; then
		return 0
	fi

	printf "\n"
	printf "${PURPLE}=== ISSUE BREAKDOWN ===${NC}\n"
	printf "Most common issues found:\n\n"

	# Process the issue list to group by message type
	# Create a temporary file to process issues
	temp_file="/tmp/issue_summary_$$"

	# Write issues to temp file for processing
	printf "%s\n" "$ISSUE_LIST" >"$temp_file"

	# Group issues by ShellCheck code, PSScriptAnalyzer rule, markdown linting code, or other message types
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
			# Check if this is a PSScriptAnalyzer issue
			elif echo "$message" | grep -q "^PS[A-Za-z]*:"; then
				# Extract just the PSScriptAnalyzer rule name
				ps_rule=$(echo "$message" | cut -d':' -f1)
				# Group by PSScriptAnalyzer rule
				case "$ps_rule" in
				"PSAvoidUsingWriteHost")
					printf "%s: Use Write-Output instead of Write-Host for better pipeline compatibility\n" "$ps_rule"
					;;
				"PSAvoidTrailingWhitespace")
					printf "%s: Remove trailing whitespace from lines\n" "$ps_rule"
					;;
				"PSAvoidUsingInvokeExpression")
					printf "%s: Avoid Invoke-Expression for security reasons\n" "$ps_rule"
					;;
				"PSUseApprovedVerbs")
					printf "%s: Use approved PowerShell verbs for function names\n" "$ps_rule"
					;;
				"PSAvoidGlobalVars")
					printf "%s: Avoid using global variables\n" "$ps_rule"
					;;
				"PSAvoidDefaultValueSwitchParameter")
					printf "%s: Switch parameters should not have default values\n" "$ps_rule"
					;;
				"PSAvoidUsingEmptyCatchBlock")
					printf "%s: Empty catch blocks should be avoided\n" "$ps_rule"
					;;
				"PSUseBOMForUnicodeEncodedFile")
					printf "%s: Unicode files should have BOM encoding\n" "$ps_rule"
					;;
				"PSReviewUnusedParameter")
					printf "%s: Parameters should be used in functions\n" "$ps_rule"
					;;
				*)
					printf "%s: PowerShell best practice violation\n" "$ps_rule"
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
				# Other issues - show as is
				printf "%s\n" "$message"
			fi
		fi
	done <"$temp_file" | sort | uniq -c | sort -nr >"${temp_file}.counts"

	# Display grouped results
	while read -r count message; do
		if [ -n "$message" ]; then
			# Count unique files for this message type
			if echo "$message" | grep -q "^SC[0-9]*:"; then
				# For ShellCheck codes, count files that have this specific code
				sc_code=$(echo "$message" | cut -d':' -f1)
				unique_files=$(grep "^$sc_code:" "$temp_file" | cut -d'|' -f2 | sort -u | wc -l)
			elif echo "$message" | grep -q "^PS[A-Za-z]*:"; then
				# For PSScriptAnalyzer rules, count files that have this specific rule
				ps_rule=$(echo "$message" | cut -d':' -f1)
				unique_files=$(grep "^$ps_rule:" "$temp_file" | cut -d'|' -f2 | sort -u | wc -l)
			elif echo "$message" | grep -q "^MD[0-9]*:"; then
				# For markdown linting codes, count files that have this specific code
				md_code=$(echo "$message" | cut -d':' -f1)
				unique_files=$(grep "^$md_code:" "$temp_file" | cut -d'|' -f2 | sort -u | wc -l)
			elif echo "$message" | grep -q "^prettier:"; then
				# For prettier issues, count files with prettier formatting issues
				unique_files=$(grep -F "prettier formatting issues" "$temp_file" | cut -d'|' -f2 | sort -u | wc -l)
			else
				# For other issues, count normally
				unique_files=$(grep -F "$message|" "$temp_file" | cut -d'|' -f2 | sort -u | wc -l)
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
	log_step "Generating validation summary"

	printf "\n"
	printf "${PURPLE}=== VALIDATION SUMMARY ===${NC}\n"
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

	if [ $TOTAL_ISSUES -eq 0 ]; then
		log_success "All validations passed!"
		return 0
	else
		log_error "Validation failed with $TOTAL_ISSUES issues"
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
    --all           Validate all shell, PowerShell and markdown files in the repository
    --shell-only    Validate only shell script files
    --ps1-only      Validate only PowerShell script files
    --md-only       Validate only markdown files
    --help, -h      Show this help message

EXAMPLES:
    $0                              # Validate all shell, PowerShell and markdown files
    $0 --all                        # Same as above, but explicit
    $0 --staged                     # Validate only staged files (git hook mode)
    $0 --shell-only                 # Validate only shell scripts
    $0 --ps1-only                   # Validate only PowerShell scripts
    $0 --md-only                    # Validate only markdown files
    $0 file1.sh file2.ps1 file3.md  # Validate specific files
    $0 scripts/*.sh automation/*.ps1 # Validate files in specific directories

DESCRIPTION:
    This script validates shell scripts for RUTOS/busybox compatibility,
    PowerShell scripts for automation quality, and markdown files for 
    documentation quality by checking:
    
    SHELL SCRIPTS:
    - Shebang compatibility (#!/bin/sh required for RUTOS scripts)
    - Bash-specific syntax (arrays, double brackets, etc.) for RUTOS scripts
    - Echo -e usage (should use printf instead) for RUTOS scripts
    - Source command usage (should use . instead) for RUTOS scripts
    - Function syntax compatibility for RUTOS scripts
    - ShellCheck validation in POSIX mode for *-rutos.sh files, bash mode for others
    - RUTOS naming convention compliance (*-rutos.sh for RUTOS-target scripts)
    - shfmt formatting (with auto-fix)
    
    POWERSHELL SCRIPTS:
    - PSScriptAnalyzer validation (Error, Warning, Information levels)
    - PowerShell syntax validation using built-in parser
    - Security pattern checks (hardcoded credentials, Invoke-Expression usage)
    - Best practice validation (Write-Host vs Write-Output, error handling)
    - Parameter validation recommendations
    
    MARKDOWN FILES:
    - markdownlint validation
    - prettier formatting (with auto-fix)

    AUTO-FIXING:
    The script automatically fixes formatting issues using:
    - shfmt for shell scripts
    - prettier for markdown files
    - PowerShell formatting (planned for future versions)
    
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

# Main function
main() {
	log_info "Starting RUTOS busybox compatibility, PowerShell, and markdown validation v$SCRIPT_VERSION"

	# Skip self-validation
	log_step "Self-validation: Skipped - this script is excluded from validation"

	local shell_files=""
	local powershell_files=""
	local markdown_files=""
	
	# Check if running with specific files
	if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
		show_help
		exit 0
	elif [ "$1" = "--staged" ]; then
		log_info "Running in pre-commit mode (staged files only)"
		# Get staged shell, PowerShell and markdown files, excluding specified files
		shell_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' | while read -r file; do
			if ! is_excluded "$file"; then
				echo "$file"
			fi
		done | sort)
		powershell_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.ps1$' | sort)
		markdown_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' | sort)
	elif [ "$1" = "--all" ]; then
		log_info "Running in comprehensive validation mode (all shell, PowerShell and markdown files)"
		# Get all shell, PowerShell and markdown files, excluding specified files
		shell_files=$(find . -name "*.sh" -type f | while read -r file; do
			if ! is_excluded "$file"; then
				echo "$file"
			fi
		done | sort)
		powershell_files=$(find . -name "*.ps1" -type f | sort)
		markdown_files=$(find . -name "*.md" -type f | sort)
	elif [ "$1" = "--shell-only" ]; then
		log_info "Running in shell-only validation mode"
		# Get all shell files, excluding specified files
		shell_files=$(find . -name "*.sh" -type f | while read -r file; do
			if ! is_excluded "$file"; then
				echo "$file"
			fi
		done | sort)
	elif [ "$1" = "--md-only" ]; then
		log_info "Running in markdown-only validation mode"
		# Get all markdown files
		markdown_files=$(find . -name "*.md" -type f | sort)
	elif [ "$1" = "--ps1-only" ]; then
		log_info "Running in PowerShell-only validation mode"
		# Get all PowerShell files
		powershell_files=$(find . -name "*.ps1" -type f | sort)
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
				*.ps1)
					powershell_files="$powershell_files $file"
					;;
				*)
					log_warning "Unsupported file type: $file (only .sh, .ps1 and .md supported)"
					;;
			esac
		done
	else
		log_info "Running in full validation mode (all shell, PowerShell and markdown files)"
		# Get all shell, PowerShell and markdown files, excluding specified files
		shell_files=$(find . -name "*.sh" -type f | while read -r file; do
			if ! is_excluded "$file"; then
				echo "$file"
			fi
		done | sort)
		powershell_files=$(find . -name "*.ps1" -type f | sort)
		markdown_files=$(find . -name "*.md" -type f | sort)
	fi

	# Count total files
	local total_files=0
	for file in $shell_files $powershell_files $markdown_files; do
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

	# Validate PowerShell files
	if [ -n "$powershell_files" ]; then
		log_info "Validating PowerShell files"
		for file in $powershell_files; do
			if [ -f "$file" ]; then
				TOTAL_FILES=$((TOTAL_FILES + 1))
				validate_powershell_file "$file"
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
	if ! display_summary; then
		return 1
	fi

	return 0
}

# Execute main function
main "$@"
