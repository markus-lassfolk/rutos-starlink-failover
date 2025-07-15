#!/bin/sh

# ==============================================================================
# Version Update Script
#
# This script automatically updates version numbers across the project
# using git information and timestamps.
#
# Usage:
#   ./update-version.sh [major|minor|patch]
#
# ==============================================================================

set -eu

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"

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
        "patch"|*)
            patch=$((patch + 1))
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Function to update version in files
update_version_in_files() {
    version="$1"
    build_info="$2"
    
    # Update VERSION file
    echo "$version" > "$VERSION_FILE"
    
    # Update install.sh
    if [ -f "$PROJECT_ROOT/scripts/install.sh" ]; then
        sed -i "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$version\"/" "$PROJECT_ROOT/scripts/install.sh"
        # Add build info as comment
        sed -i "/^SCRIPT_VERSION=/a\\# Build: $build_info" "$PROJECT_ROOT/scripts/install.sh"
    fi
    
    # Update validate-config.sh
    if [ -f "$PROJECT_ROOT/scripts/validate-config.sh" ]; then
        sed -i "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$version\"/" "$PROJECT_ROOT/scripts/validate-config.sh"
        # Add build info as comment
        sed -i "/^SCRIPT_VERSION=/a\\# Build: $build_info" "$PROJECT_ROOT/scripts/validate-config.sh"
    fi
    
    # Update other scripts
    for script in "$PROJECT_ROOT/scripts"/*.sh; do
        if [ -f "$script" ] && [ "$script" != "$PROJECT_ROOT/scripts/install.sh" ] && [ "$script" != "$PROJECT_ROOT/scripts/validate-config.sh" ]; then
            if grep -q "^SCRIPT_VERSION=" "$script" 2>/dev/null; then
                sed -i "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$version\"/" "$script"
            fi
        fi
    done
}

# Function to create version info file
create_version_info() {
    version="$1"
    build_info="$2"
    
    cat > "$PROJECT_ROOT/VERSION_INFO" << EOF
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
    
    # Validate level
    case "$level" in
        "major"|"minor"|"patch")
            ;;
        *)
            echo "Usage: $0 [major|minor|patch]"
            echo "Default: patch"
            exit 1
            ;;
    esac
    
    # Get git information
    get_git_info
    
    # Read current version
    if [ -f "$VERSION_FILE" ]; then
        current_version=$(tr -d '\n\r' < "$VERSION_FILE" | tr -d ' ')
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
    echo "- VERSION"
    echo "- VERSION_INFO"
    echo "- scripts/install.sh"
    echo "- scripts/validate-config.sh"
    echo "- Other scripts with SCRIPT_VERSION"
}

# Run main function
main "$@"
