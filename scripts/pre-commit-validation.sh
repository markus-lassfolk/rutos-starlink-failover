#!/bin/bash
# Pre-commit validation script for RUTOS Starlink Failover Project
# Version: 1.0.2
# Description: Comprehensive validation of shell scripts for RUTOS/busybox compatibility
#
# NOTE: This script runs in the development environment (WSL/Linux), NOT on RUTOS,
# so it can use modern bash features for efficiency. It validates OTHER scripts
# for RUTOS compatibility but is excluded from its own validation checks.

# NOTE: We don't use 'set -e' here because we want to continue processing all files
# and collect all validation issues before exiting

# Version information
SCRIPT_VERSION="1.0.2"

# Files to exclude from validation (patterns supported)
EXCLUDED_FILES=(
	"scripts/pre-commit-validation.sh"
	"scripts/setup-code-quality-tools.sh"
	"scripts/comprehensive-validation.sh"
)

# Standard colors for consistent output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
is_excluded() {
	local file="$1"
	local pattern
	
	for pattern in "${EXCLUDED_FILES[@]}"; do
		case "$file" in
		*"$pattern"*)
			return 0  # File is excluded
			;;
		esac
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

	# Run shellcheck with POSIX mode and capture output
	shellcheck_output=$(shellcheck -s sh "$file" 2>&1)

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

# Function to validate a single file
validate_file() {
	file="$1"

	log_step "Validating: $file"

	initial_issues=$TOTAL_ISSUES

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

	# Run shfmt formatting validation
	run_shfmt "$file"

	# Run shfmt
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

	# Group issues by ShellCheck code first, then by full message
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
			else
				# Non-ShellCheck issues - show as is
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
			else
				# For non-ShellCheck issues, count normally
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
RUTOS Busybox Compatibility Validation Script

Usage: $0 [OPTIONS] [FILES...]

OPTIONS:
    --staged        Validate only staged files (for git pre-commit hook)
    --all           Validate all shell files in the repository
    --help, -h      Show this help message

EXAMPLES:
    $0                              # Validate all shell files
    $0 --all                        # Same as above, but explicit
    $0 --staged                     # Validate only staged files (git hook mode)
    $0 file1.sh file2.sh            # Validate specific files
    $0 scripts/*.sh                 # Validate all files in scripts directory

DESCRIPTION:
    This script validates shell scripts for RUTOS/busybox compatibility by checking:
    - Shebang compatibility (#!/bin/sh required)
    - Bash-specific syntax (arrays, double brackets, etc.)
    - Echo -e usage (should use printf instead)
    - Source command usage (should use . instead)
    - Function syntax compatibility
    - ShellCheck validation in POSIX mode

    The script processes ALL files even if some fail validation, providing
    a comprehensive report of all issues found across all files.

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
	log_info "Starting RUTOS busybox compatibility validation v$SCRIPT_VERSION"

	# Skip self-validation
	log_step "Self-validation: Skipped - this script is excluded from validation"

	# Check if running with specific files
	if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
		show_help
		exit 0
	elif [ "$1" = "--staged" ]; then
		log_info "Running in pre-commit mode (staged files only)"
		# Get staged shell files, excluding specified files
		files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' | while read -r file; do
			if ! is_excluded "$file"; then
				echo "$file"
			fi
		done | sort)
	elif [ "$1" = "--all" ]; then
		log_info "Running in comprehensive validation mode (all shell files)"
		# Get all shell files, excluding specified files
		files=$(find . -name "*.sh" -type f | while read -r file; do
			if ! is_excluded "$file"; then
				echo "$file"
			fi
		done | sort)
	elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
		show_help
		return 0
	elif [ $# -gt 0 ]; then
		log_info "Running in specific file mode"
		files="$@"
	else
		log_info "Running in full validation mode (all shell files)"
		files=$(find . -name "*.sh" -type f | while read -r file; do
			if ! is_excluded "$file"; then
				echo "$file"
			fi
		done | sort)
	fi

	if [ -z "$files" ]; then
		log_warning "No shell files found to validate"
		return 0
	fi

	# Convert to array for counting
	file_count=0
	for file in $files; do
		file_count=$((file_count + 1))
	done

	# Validate each file
	log_step "Processing $file_count files"
	for file in $files; do
		if [ -f "$file" ]; then
			# Check if file should be excluded (for specific file mode)
			if is_excluded "$file"; then
				log_debug "Skipping excluded file: $file"
				continue
			fi
			
			TOTAL_FILES=$((TOTAL_FILES + 1))
			validate_file "$file"
		else
			log_debug "Skipping non-existent file: $file"
		fi
	done

	# Display summary
	if ! display_summary; then
		return 1
	fi

	return 0
}

# Execute main function
main "$@"
