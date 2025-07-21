#!/bin/sh
# Fix common markdown issues found by markdownlint

# Color codes for output - RUTOS compatible
# shellcheck disable=SC2034  # Color variables may not all be used in every script
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

log_info() {
    printf "%s[INFO]%s %s\n" "$GREEN" "$NC" "$1"
}

log_warning() {
    printf "%s[WARNING]%s %s\n" "$YELLOW" "$NC" "$1"
}

log_error() {
    printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$1"
}

log_step() {
    printf "%s[STEP]%s %s\n" "$BLUE" "$NC" "$1"
}

# Fix MD040 - Add language specification to fenced code blocks
fix_md040() {
    file="$1"
    temp_file=$(mktemp)

    log_step "Fixing MD040 (missing language specification) in $file"

    # This is a complex fix that needs to identify the context of each code block
    # For now, we'll focus on the most common cases

    # First, let's identify directory structure blocks
    # Replace bare ``` (markdown code blocks without language) with ```text
    pattern='^```[[:space:]]*$'
    replacement='```text'
    sed "s/${pattern}/${replacement}/" "$file" >"$temp_file"

    # Check if any changes were made
    if ! diff -q "$file" "$temp_file" >/dev/null; then
        mv "$temp_file" "$file"
        log_info "Fixed code block language specifications in $file"
    else
        rm "$temp_file"
    fi
}

# Fix MD031 - Add blank lines around fenced code blocks
fix_md031() {
    file="$1"
    temp_file=$(mktemp)

    log_step "Fixing MD031 (blank lines around fences) in $file"

    # Add blank line before code blocks if missing
    sed -i 's/\([^[:space:]]\)$/\1\n/' "$file"

    # This is a complex regex operation that needs careful handling
    # For now, we'll skip this as it's prone to errors
    log_warning "MD031 fixes require manual intervention for $file"
}

# Fix MD026 - Remove trailing punctuation from headings
fix_md026() {
    file="$1"
    temp_file=$(mktemp)

    log_step "Fixing MD026 (trailing punctuation in headings) in $file"

    # Remove trailing colons from headings
    sed 's/^\(#\+.*\):$/\1/' "$file" >"$temp_file"

    # Check if any changes were made
    if ! diff -q "$file" "$temp_file" >/dev/null; then
        mv "$temp_file" "$file"
        log_info "Fixed trailing punctuation in headings in $file"
    else
        rm "$temp_file"
    fi
}

# Fix MD010 - Replace hard tabs with spaces
fix_md010() {
    file="$1"

    log_step "Fixing MD010 (hard tabs) in $file"

    # Replace tabs with 4 spaces
    sed -i 's/\t/    /g' "$file"
    log_info "Fixed hard tabs in $file"
}

# Main function
main() {
    log_info "Starting markdown issue fixes"

    # List of files that need fixes based on the validation report
    files="./.github/copilot-instructions.md ./.github/ISSUE_TEMPLATE/bug_report.md ./CLEANUP_SUMMARY.md ./CONFIGURATION_MANAGEMENT.md ./DEPLOYMENT_SUMMARY.md ./docs/BRANCH_TESTING.md ./docs/CODE_QUALITY_SYSTEM.md ./docs/CONFIG_PRESERVATION.md ./docs/HEALTH-CHECK.md ./docs/TROUBLESHOOTING.md ./docs/UPGRADE-GUIDE.md ./docs/VALIDATE_CONFIG_FIX.md ./INSTALLATION_STATUS.md ./README.md ./RUTOS-COMPATIBILITY-FIXES.md ./SECURITY.md ./Starlink-RUTOS-Failover/AzureLogging/analysis/README.md ./Starlink-RUTOS-Failover/AzureLogging/ANALYSIS_GUIDE.md ./Starlink-RUTOS-Failover/AzureLogging/GPS_INTEGRATION_GUIDE.md ./Starlink-RUTOS-Failover/AzureLogging/INSTALLATION_GUIDE.md ./Starlink-RUTOS-Failover/AzureLogging/README.md ./Starlink-RUTOS-Failover/AzureLogging/SOLUTION_OVERVIEW.md ./Starlink-RUTOS-Failover/README.md ./TESTING.md"

    for file in $files; do
        if [ -f "$file" ]; then
            log_step "Processing $file"

            # Apply fixes based on the issues found
            case "$file" in
                *"TESTING.md")
                    fix_md010 "$file"
                    fix_md040 "$file"
                    ;;
                *"DEPLOYMENT_SUMMARY.md" | *"INSTALLATION_STATUS.md" | *"SECURITY.md" | *"VALIDATE_CONFIG_FIX.md")
                    fix_md026 "$file"
                    ;;
                *"TROUBLESHOOTING.md")
                    fix_md031 "$file"
                    fix_md040 "$file"
                    ;;
                *)
                    fix_md040 "$file"
                    ;;
            esac
        else
            log_warning "File not found: $file"
        fi
    done

    log_info "Markdown fixes completed"
    log_info "Run validation again to check results"
}

# Run the main function
main "$@"
