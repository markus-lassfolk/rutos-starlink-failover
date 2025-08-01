#!/bin/sh

# ==============================================================================
# Version Update Script
#
# This script automatically updates version numbers across the project
# using git information and timestamps.
#
# CRITICAL: This script follows RUTOS library patterns and best practices
# - RUTOS scripts (-rutos.sh) use library system (no readonly SCRIPT_VERSION)
# - Standalone scripts can use readonly SCRIPT_VERSION
# - Respects shell compatibility and POSIX requirements
#
# Usage:
#   ./update-version.sh [major|minor|patch]
#
# ==============================================================================

set -eu

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.8.0"
# NOTE: This script is standalone and can use readonly. RUTOS scripts should NOT.

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"

# Simple logging functions (no colors needed for this script)
log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo "[DEBUG] $1" >&2
    fi
}

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# Function to get git information
get_git_info() {
    if [ -d "$PROJECT_ROOT/.git" ]; then
        GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        GIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        GIT_DIRTY=""
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            GIT_DIRTY="-dirty"
        fi
    else
        GIT_COMMIT="unknown"
        GIT_BRANCH="unknown"
        GIT_COUNT="0"
        GIT_DIRTY=""
    fi
}

# Function to increment version
increment_version() {
    version="$1"
    level="$2"

    # Parse version (major.minor.patch)
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    patch=$(echo "$version" | cut -d. -f3)

    # Ensure we have valid numbers
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}

    case "$level" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch" | *)
            patch=$((patch + 1))
            ;;
    esac

    echo "$major.$minor.$patch"
}

# Function to parse .gitignore and generate find exclusions
parse_gitignore_exclusions() {
    gitignore_file="$PROJECT_ROOT/.gitignore"
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
                        dir_pattern="${pattern%/}"
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

# Function to add version usage patterns to scripts
add_version_usage_patterns() {
    file="$1"

    # Skip if this is update-version.sh itself (already handled)
    if echo "$file" | grep -q "update-version.sh$"; then
        return 0
    fi

    # Skip templates and test files (they shouldn't show versions)
    if echo "$file" | grep -qE "template\.sh$|test-.*\.sh$|.*-test\.sh$"; then
        log_debug "Skipping version usage for template/test file: $file"
        return 0
    fi

    # Check if script already has version usage patterns
    if grep -q "Script.*\$SCRIPT_VERSION\|v\$SCRIPT_VERSION" "$file"; then
        log_debug "Version usage patterns already exist in: $file"
        return 0
    fi

    # Get script name for display
    script_name="$(basename "$file")"

    # Look for existing main() function or help patterns
    if grep -q "main()" "$file"; then
        # Script has main() function - add version display there
        if ! grep -A 10 "main()" "$file" | grep -q "SCRIPT_VERSION"; then
            # Add version display to beginning of main function
            sed -i "/^main() {\$/,/^    [^[:space:]]/ {
                /^main() {\$/ {
                    a\\
    # Display script version for troubleshooting\\
    if [ \"\${DEBUG:-0}\" = \"1\" ] || [ \"\${VERBOSE:-0}\" = \"1\" ]; then\\
        printf \"[DEBUG] %s v%s\\\\n\" \"$script_name\" \"\$SCRIPT_VERSION\" >&2\\
    fi\\
    log_debug \"==================== SCRIPT START ===================\"\\
    log_debug \"Script: $script_name v\$SCRIPT_VERSION\"\\
    log_debug \"Working directory: \$(pwd)\"\\
    log_debug \"Arguments: \$*\"\\
    log_debug \"======================================================\"
                }
            }" "$file" && echo "    ✓ Added version display to main() function"
        fi
    elif grep -q "help\|usage\|--help\|-h" "$file"; then
        # Script has help patterns - add version display there
        if ! grep -B 5 -A 5 "help\|usage" "$file" | grep -q "SCRIPT_VERSION"; then
            # Find help/usage section and add version
            sed -i "/--help\\|-h\\|usage\\|help)/ {
                i\\
        echo \"$script_name v\$SCRIPT_VERSION\"\\
        echo \"\"
            }" "$file" && echo "    ✓ Added version display to help section"
        fi
    else
        # No clear pattern found - add basic version logging
        if grep -q "log_info\|log_debug\|printf.*INFO\|echo.*INFO" "$file"; then
            # Script has logging - add version to debug output
            log_debug "Adding version display to logging in: $file"
            # Look for first log_info or similar and add version before it
            sed -i "0,/log_info\\|log_debug\\|printf.*INFO\\|echo.*INFO/ {
                /log_info\\|log_debug\\|printf.*INFO\\|echo.*INFO/ i\\
    # Version information for troubleshooting\\
    if [ \"\${DEBUG:-0}\" = \"1\" ]; then\\
        log_debug \"Script: $script_name v\$SCRIPT_VERSION\"\\
    fi
            }" "$file" && echo "    ✓ Added version to debug logging"
        fi
    fi
}

# Function to update version in files
update_version_in_files() {
    version="$1"
    build_info="$2"

    echo "Updating version to $version in all project files..."

    # Update VERSION file
    echo "$version" >"$VERSION_FILE"

    # Get exclusion patterns from .gitignore
    exclusions=$(parse_gitignore_exclusions)

    # Find and update ALL shell scripts (.sh files) respecting .gitignore
    echo "Processing shell scripts (excluding .gitignore patterns)..."
    eval "find \"$PROJECT_ROOT\" -name \"*.sh\" $exclusions" | while read -r file; do
        echo "  Processing: $file"

        # Determine if this is a RUTOS script (uses library system)
        is_rutos_script=false
        if echo "$file" | grep -q -- "-rutos\.sh$"; then
            is_rutos_script=true
            log_debug "Detected RUTOS library script: $file"
        fi

        if grep -q "^[[:space:]]*SCRIPT_VERSION=" "$file"; then
            # Update existing SCRIPT_VERSION (but don't touch readonly lines)
            if [ "$is_rutos_script" = true ]; then
                # RUTOS scripts: Only update the version value, remove any readonly declarations
                sed -i "s/^[[:space:]]*SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$version\"/" "$file"
                # Remove any readonly SCRIPT_VERSION lines (library manages this)
                sed -i "/^[[:space:]]*readonly[[:space:]]*SCRIPT_VERSION/d" "$file"
                echo "    ✓ Updated RUTOS script version (removed readonly)"
            else
                # Standalone scripts: Update version and ensure readonly is present
                sed -i "s/^[[:space:]]*SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$version\"/" "$file"
                if ! grep -q "^[[:space:]]*readonly[[:space:]]*SCRIPT_VERSION" "$file"; then
                    # Add readonly after SCRIPT_VERSION line if missing
                    sed -i "/^SCRIPT_VERSION=/a\\
readonly SCRIPT_VERSION" "$file"
                fi
                echo "    ✓ Updated standalone script version (with readonly)"
            fi
        else
            # Add SCRIPT_VERSION if missing
            if [ -f "$file" ] && head -1 "$file" | grep -q "^#!/"; then
                # Find where to insert SCRIPT_VERSION (after shebang, comments, and set commands)
                insert_line=2

                # Skip initial comments and set commands
                temp_file="/tmp/version_update_$$"
                tail -n +2 "$file" >"$temp_file"
                while read -r line_content; do
                    if echo "$line_content" | grep -q "^#\|^set \|^$"; then
                        insert_line=$((insert_line + 1))
                    else
                        break
                    fi
                done <"$temp_file"
                rm -f "$temp_file"

                # Insert SCRIPT_VERSION with automation comment
                temp_version_content="$(mktemp)"
                {
                    head -n "$((insert_line - 1))" "$file"
                    echo ""
                    echo "# Version information (auto-updated by update-version.sh)"
                    echo "SCRIPT_VERSION=\"$version\""

                    # Only add readonly for standalone scripts, NOT for RUTOS scripts
                    if [ "$is_rutos_script" = false ]; then
                        echo "readonly SCRIPT_VERSION"
                    fi

                    tail -n "+$insert_line" "$file"
                } >"$temp_version_content"
                mv "$temp_version_content" "$file"

                if [ "$is_rutos_script" = true ]; then
                    echo "    ✓ Added RUTOS script version (no readonly - library manages this)"
                else
                    echo "    ✓ Added standalone script version (with readonly)"
                fi
            fi
        fi

        # Add version usage patterns if they don't exist
        add_version_usage_patterns "$file"

        # Update header comment version if it exists
        if grep -q "^# Version:" "$file"; then
            sed -i "s/^# Version:.*/# Version: $version/" "$file"
            echo "    ✓ Updated header version comment"
        fi
    done

    # Update configuration files (.sh config files)
    echo "Processing configuration files..."
    find "$PROJECT_ROOT/config" -name "*.sh" 2>/dev/null | while read -r file; do
        echo "  Processing config: $file"

        if grep -q "^[[:space:]]*TEMPLATE_VERSION=" "$file"; then
            sed -i "s/^[[:space:]]*TEMPLATE_VERSION=.*/TEMPLATE_VERSION=\"$version\"/" "$file"
        elif grep -q "^[[:space:]]*CONFIG_VERSION=" "$file"; then
            sed -i "s/^[[:space:]]*CONFIG_VERSION=.*/CONFIG_VERSION=\"$version\"/" "$file"
        else
            # Add version to config files
            if head -1 "$file" | grep -q "^#!/"; then
                sed -i "3i\\
\\
# Template version (auto-updated by update-version.sh)\\
TEMPLATE_VERSION=\"$version\"\\
readonly TEMPLATE_VERSION" "$file"
                echo "    ✓ Added version to config file"
            fi
        fi
    done

    # Update Markdown files with version headers (respecting .gitignore)
    echo "Processing documentation files (excluding .gitignore patterns)..."

    # Use a simpler approach - find all .md files then filter out unwanted ones
    find "$PROJECT_ROOT" -name "*.md" -type f | while read -r file; do
        # Skip specific directories that should never be processed
        case "$file" in
            */node_modules/*)
                log_debug "Skipping node_modules file: $file"
                continue
                ;;
            */.git/*)
                log_debug "Skipping .git file: $file"
                continue
                ;;
            */.github/*)
                log_debug "Skipping .github file: $file"
                continue
                ;;
            */temp/*)
                log_debug "Skipping temp file: $file"
                continue
                ;;
        esac

        echo "  Processing markdown: $file"

        # Check if file already has version information
        if grep -q "^# Version:" "$file" || grep -q "^Version:" "$file"; then
            # Update existing version
            sed -i "s/^# Version:.*/# Version: $version/" "$file"
            sed -i "s/^Version:.*/Version: $version/" "$file"
            echo "    ✓ Updated existing version"
        else
            # Add version header for important documentation
            if echo "$file" | grep -qE "(README|DEPLOYMENT|INSTALLATION|CONFIGURATION|TESTING)"; then
                # Add version after the main title
                if grep -q "^# " "$file"; then
                    first_header_line=$(grep -n "^# " "$file" | head -1 | cut -d: -f1)
                    sed -i "${first_header_line}a\\
\\
**Version:** $version | **Updated:** $(date '+%Y-%m-%d')" "$file"
                    echo "    ✓ Added version to important documentation"
                fi
            fi
        fi
    done

    # Update package.json if it exists
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        echo "  Processing package.json"
        if command -v jq >/dev/null 2>&1; then
            jq ".version = \"$version\"" "$PROJECT_ROOT/package.json" >"$PROJECT_ROOT/package.json.tmp" &&
                mv "$PROJECT_ROOT/package.json.tmp" "$PROJECT_ROOT/package.json"
            echo "    ✓ Updated package.json version"
        else
            sed -i "s/\"version\":[[:space:]]*\"[^\"]*\"/\"version\": \"$version\"/" "$PROJECT_ROOT/package.json"
            echo "    ✓ Updated package.json version (fallback method)"
        fi
    fi

    # Update pyproject.toml if it exists
    if [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
        echo "  Processing pyproject.toml"
        sed -i "s/^version[[:space:]]*=.*/version = \"$version\"/" "$PROJECT_ROOT/pyproject.toml"
        echo "    ✓ Updated pyproject.toml version"
    fi

    echo "Version update completed!"
}

# Function to create version info file
create_version_info() {
    version="$1"
    build_info="$2"

    cat >"$PROJECT_ROOT/VERSION_INFO" <<EOF
# Version Information
VERSION=$version
BUILD_DATE=$(date '+%Y-%m-%d %H:%M:%S')
BUILD_INFO=$build_info
GIT_COMMIT=$GIT_COMMIT
GIT_BRANCH=$GIT_BRANCH
GIT_COUNT=$GIT_COUNT
GIT_DIRTY=$GIT_DIRTY
EOF
}

# Main function
main() {
    level="${1:-patch}"

    # Show version for help or debug
    if [ "$level" = "--help" ] || [ "$level" = "-h" ]; then
        echo "Version Update Script v$SCRIPT_VERSION"
        echo ""
        echo "Usage: $0 [major|minor|patch|--help]"
        echo ""
        echo "This script follows RUTOS best practices:"
        echo "  - RUTOS scripts (*-rutos.sh) use library system (no readonly SCRIPT_VERSION)"
        echo "  - Standalone scripts use readonly SCRIPT_VERSION"
        echo "  - Respects shell compatibility and POSIX requirements"
        echo ""
        echo "Options:"
        echo "  major    Increment major version (X.0.0)"
        echo "  minor    Increment minor version (X.Y.0)"
        echo "  patch    Increment patch version (X.Y.Z) [default]"
        echo "  --help   Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 patch   # 1.0.0 -> 1.0.1"
        echo "  $0 minor   # 1.0.0 -> 1.1.0"
        echo "  $0 major   # 1.0.0 -> 2.0.0"
        exit 0
    fi

    # Display version in debug mode
    if [ "${DEBUG:-0}" = "1" ]; then
        log_debug "==================== DEBUG MODE ENABLED ===================="
        log_debug "Script: update-version.sh v$SCRIPT_VERSION"
        log_debug "Working directory: $(pwd)"
        log_debug "Arguments: $*"
        log_debug "Level: $level"
        log_debug "RUTOS Best Practices: Enabled"
        log_debug "=============================================================="
    fi

    # Validate level
    case "$level" in
        "major" | "minor" | "patch") ;;

        *)
            echo "Version Update Script v$SCRIPT_VERSION"
            echo "Error: Invalid level '$level'"
            echo "Usage: $0 [major|minor|patch]"
            echo "Default: patch"
            exit 1
            ;;
    esac

    # Get git information
    get_git_info

    # Show script version in main output
    echo "Version Update Script v$SCRIPT_VERSION"
    echo "=================================================="

    # Read current version
    if [ -f "$VERSION_FILE" ]; then
        current_version=$(tr -d '\n\r' <"$VERSION_FILE" | tr -d ' ')
        # Ensure version is not empty
        if [ -z "$current_version" ]; then
            current_version="1.0.0"
        fi
    else
        current_version="1.0.0"
    fi

    # Increment version
    new_version=$(increment_version "$current_version" "$level")

    # Create build info
    build_info="$new_version+$GIT_COUNT.$GIT_COMMIT$GIT_DIRTY"

    # Update version in files
    update_version_in_files "$new_version" "$build_info"

    # Create version info file
    create_version_info "$new_version" "$build_info"

    echo "Version updated: $current_version -> $new_version"
    echo "Build info: $build_info"
    echo "Branch: $GIT_BRANCH"
    echo "Commit: $GIT_COMMIT"

    # Show what files were updated
    echo ""
    echo "Updated files:"
    echo "- VERSION (project version file)"
    echo "- VERSION_INFO (detailed build information)"
    echo "- All shell scripts (.sh files) following RUTOS best practices:"
    echo "  * RUTOS scripts (*-rutos.sh): SCRIPT_VERSION without readonly"
    echo "  * Standalone scripts: SCRIPT_VERSION with readonly"
    echo "- Configuration templates (config/*.sh)"
    echo "- Important documentation files (*.md)"
    echo "- package.json (if present)"
    echo "- pyproject.toml (if present)"

    echo ""
    echo "✅ All project files now use version: $new_version"
    echo "✅ RUTOS library compatibility maintained"
    echo ""
    echo "💡 TIP: Run './scripts/pre-commit-validation.sh' to verify version consistency"
    echo "💡 TIP: RUTOS scripts will get SCRIPT_VERSION managed by library system"
}

# Run main function
main "$@"
