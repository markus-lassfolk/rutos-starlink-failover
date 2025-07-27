#!/bin/sh
# Setup script for RUTOS development environment
# Version: 2.7.1
# Description: Sets up pre-commit hooks and validation tools

set -e

# Colors for output
# Check if terminal supports colors
# shellcheck disable=SC2034

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.1"
readonly SCRIPT_VERSION
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Fallback to no colors if terminal doesn't support them
    # shellcheck disable=SC2034
    # shellcheck disable=SC2034  # Color variables may not all be used in every script
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$1"
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "${CYAN}[DEBUG]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Main setup function
main() {
    # Display script version for troubleshooting
    if [ "${DEBUG:-0}" = "1" ] || [ "${VERBOSE:-0}" = "1" ]; then
        printf "[DEBUG] %s v%s\n" "setup-dev-environment.sh" "$SCRIPT_VERSION" >&2
    fi
    log_debug "==================== SCRIPT START ==================="
    log_debug "Script: setup-dev-environment.sh v$SCRIPT_VERSION"
    log_debug "Working directory: $(pwd)"
    log_debug "Arguments: $*"
    log_debug "======================================================"
    log_info "Setting up RUTOS development environment..."

    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        log_error "This script must be run from the root of a git repository"
        exit 1
    fi

    # Make validation script executable
    log_step "Making validation script executable"
    chmod +x scripts/pre-commit-validation.sh

    # Setup pre-commit hook
    log_step "Setting up pre-commit hook"
    if [ -f ".git/hooks/pre-commit" ]; then
        log_info "Pre-commit hook already exists"
    else
        log_error "Pre-commit hook not found. Please run this script from the repository root."
        exit 1
    fi

    chmod +x .git/hooks/pre-commit

    # Check for ShellCheck
    log_step "Checking for ShellCheck"
    if command_exists shellcheck; then
        log_info "✓ ShellCheck is available"
    else
        log_warning "ShellCheck not found. Install it for better validation:"
        echo "  Ubuntu/Debian: sudo apt-get install shellcheck"
        echo "  macOS: brew install shellcheck"
        echo "  Windows: choco install shellcheck"
    fi

    # Test the validation script
    log_step "Testing validation script"
    if ./scripts/pre-commit-validation.sh --staged >/dev/null 2>&1; then
        log_info "✓ Validation script is working"
    else
        log_warning "Validation script test failed - check for syntax errors"
    fi

    # Create quality check alias
    log_step "Creating quality check script"
    cat >scripts/quality-check-enhanced.sh <<'EOF'
#!/bin/sh
# Enhanced quality check script that uses pre-commit validation
echo "Running enhanced quality check..."
./scripts/pre-commit-validation.sh "$@"
EOF
    chmod +x scripts/quality-check-enhanced.sh

    echo ""
    log_info "🎉 RUTOS development environment setup complete!"
    echo ""
    echo "Usage:"
    echo "  • Pre-commit hook: Automatically runs on 'git commit'"
    echo "  • Manual validation: ./scripts/pre-commit-validation.sh"
    echo "  • Staged files only: ./scripts/pre-commit-validation.sh --staged"
    echo "  • Enhanced quality check: ./scripts/quality-check-enhanced.sh"
    echo ""
    echo "The pre-commit hook will:"
    echo "  ✓ Check busybox compatibility"
    echo "  ✓ Validate POSIX compliance"
    echo "  ✓ Detect bash-specific syntax"
    echo "  ✓ Check for required patterns"
    echo "  ✓ Run ShellCheck validation"
    echo ""
    echo "To bypass validation (NOT RECOMMENDED):"
    echo "  git commit --no-verify"
}

# Execute main function
main "$@"
