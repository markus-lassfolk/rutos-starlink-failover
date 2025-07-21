#!/bin/bash
# Setup script for local development tools
# Installs markdownlint, prettier, and other code quality tools locally

set -e

# Version information (auto-updated by update-version.sh)

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.4.12"
readonly SCRIPT_VERSION
readonly SCRIPT_VERSION="2.4.11"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Standard colors for consistent output (RUTOS compatible)
# CRITICAL: Use RUTOS-compatible color detection
# shellcheck disable=SC2034  # CYAN may not be used but should be defined for consistency
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# Logging functions
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to show usage
show_usage() {
    cat <<EOF
Setup Local Development Tools v$SCRIPT_VERSION

This script installs code quality tools locally for the RUTOS Starlink Failover project:
- markdownlint-cli: Markdown linting and formatting
- prettier: Code and markdown formatting
- shellcheck: Shell script validation (if not available)
- shfmt: Shell script formatting (if not available)

Usage: $0 [options]

Options:
    --help, -h          Show this help message
    --node-only         Install only Node.js tools (skip shell tools)
    --shell-only        Install only shell tools (skip Node.js tools)
    --force             Force reinstall even if tools exist
    --check             Just check what tools are available

Examples:
    $0                  # Install all tools
    $0 --node-only      # Install only markdownlint and prettier
    $0 --check          # Check what tools are currently available
    $0 --force          # Force reinstall all tools

EOF
}

# Function to check current tool availability
check_tools() {
    log_step "Checking current tool availability"

    echo ""
    printf "%-20s %s\n" "Tool" "Status"
    printf "%-20s %s\n" "----" "------"

    # Node.js tools
    if command_exists markdownlint; then
        printf "%-20s %s✓ Available%s (%s)\n" "markdownlint" "$GREEN" "$NC" "$(markdownlint --version 2>/dev/null || echo "unknown version")"
    else
        printf "%-20s %s✗ Missing%s\n" "markdownlint" "$RED" "$NC"
    fi

    if command_exists prettier; then
        printf "%-20s %s✓ Available%s (%s)\n" "prettier" "$GREEN" "$NC" "$(prettier --version 2>/dev/null || echo "unknown version")"
    else
        printf "%-20s %s✗ Missing%s\n" "prettier" "$RED" "$NC"
    fi

    # Shell tools
    if command_exists shellcheck; then
        printf "%-20s %s✓ Available%s (%s)\n" "shellcheck" "$GREEN" "$NC" "$(shellcheck --version | grep version: | cut -d' ' -f2 2>/dev/null || echo "unknown version")"
    else
        printf "%-20s %s✗ Missing%s\n" "shellcheck" "$RED" "$NC"
    fi

    if command_exists shfmt; then
        printf "%-20s %s✓ Available%s (%s)\n" "shfmt" "$GREEN" "$NC" "$(shfmt --version 2>/dev/null || echo "unknown version")"
    else
        printf "%-20s %s✗ Missing%s\n" "shfmt" "$RED" "$NC"
    fi

    # Node.js itself
    if command_exists node; then
        printf "%-20s %s✓ Available%s (%s)\n" "node" "$GREEN" "$NC" "$(node --version 2>/dev/null || echo "unknown version")"
    else
        printf "%-20s %s✗ Missing%s\n" "node" "$RED" "$NC"
    fi

    if command_exists npm; then
        printf "%-20s %s✓ Available%s (%s)\n" "npm" "$GREEN" "$NC" "$(npm --version 2>/dev/null || echo "unknown version")"
    else
        printf "%-20s %s✗ Missing%s\n" "npm" "$RED" "$NC"
    fi

    echo ""
}

# Function to install Node.js tools
install_node_tools() {
    log_step "Installing Node.js tools (markdownlint, prettier)"

    # Check if Node.js is available
    if ! command_exists node || ! command_exists npm; then
        log_error "Node.js and npm are required but not found"
        log_error "Please install Node.js from: https://nodejs.org/"
        log_error "Or using package manager:"
        log_error "  Ubuntu/WSL: sudo apt install nodejs npm"
        log_error "  macOS: brew install node"
        log_error "  Windows: Download from nodejs.org or use chocolatey: choco install nodejs"
        return 1
    fi

    log_info "Node.js $(node --version) and npm $(npm --version) found"

    # Create package.json if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/package.json" ]; then
        log_step "Creating package.json for Node.js tools"
        cat >"$PROJECT_ROOT/package.json" <<'EOF'
{
  "name": "rutos-starlink-failover-tools",
  "version": "1.0.0",
  "description": "Development tools for RUTOS Starlink Failover project",
  "private": true,
  "scripts": {
    "lint:markdown": "markdownlint \"**/*.md\" --ignore node_modules --fix",
    "format:markdown": "prettier --write \"**/*.md\" --ignore-path .gitignore",
    "check:markdown": "markdownlint \"**/*.md\" --ignore node_modules && prettier --check \"**/*.md\" --ignore-path .gitignore"
  },
  "devDependencies": {
    "markdownlint-cli": "^0.37.0",
    "prettier": "^3.0.0"
  },
  "keywords": [
    "rutos",
    "starlink",
    "router",
    "failover",
    "monitoring"
  ]
}
EOF
        log_success "Created package.json"
    else
        log_info "package.json already exists"
    fi

    # Install Node.js dependencies
    log_step "Installing Node.js dependencies"
    cd "$PROJECT_ROOT"

    if [ "$FORCE_INSTALL" = "true" ]; then
        rm -rf node_modules package-lock.json
        log_info "Removed existing node_modules (force install)"
    fi

    if npm install; then
        log_success "Node.js tools installed successfully"
    else
        log_error "Failed to install Node.js tools"
        return 1
    fi

    # Create .markdownlint.json configuration
    if [ ! -f "$PROJECT_ROOT/.markdownlint.json" ]; then
        log_step "Creating markdownlint configuration"
        cat >"$PROJECT_ROOT/.markdownlint.json" <<'EOF'
{
  "default": true,
  "MD003": { "style": "atx" },
  "MD007": { "indent": 2 },
  "MD013": { "line_length": 120, "code_blocks": false, "tables": false },
  "MD024": { "allow_different_nesting": true },
  "MD033": { "allowed_elements": ["details", "summary", "br"] },
  "MD041": false
}
EOF
        log_success "Created .markdownlint.json configuration"
    fi

    # Create .prettierrc configuration
    if [ ! -f "$PROJECT_ROOT/.prettierrc" ]; then
        log_step "Creating prettier configuration"
        cat >"$PROJECT_ROOT/.prettierrc" <<'EOF'
{
  "printWidth": 120,
  "tabWidth": 2,
  "useTabs": false,
  "semi": false,
  "singleQuote": false,
  "quoteProps": "as-needed",
  "trailingComma": "none",
  "bracketSpacing": true,
  "proseWrap": "preserve",
  "overrides": [
    {
      "files": "*.md",
      "options": {
        "proseWrap": "preserve",
        "printWidth": 120
      }
    }
  ]
}
EOF
        log_success "Created .prettierrc configuration"
    fi

    return 0
}

# Function to install shell tools
install_shell_tools() {
    log_step "Installing shell tools (shellcheck, shfmt)"

    # Check for shellcheck
    if ! command_exists shellcheck || [ "$FORCE_INSTALL" = "true" ]; then
        log_step "Installing shellcheck"
        if command_exists apt; then
            log_info "Detected apt package manager"
            if sudo apt update && sudo apt install -y shellcheck; then
                log_success "shellcheck installed via apt"
            else
                log_warning "Failed to install shellcheck via apt"
            fi
        elif command_exists brew; then
            log_info "Detected brew package manager"
            if brew install shellcheck; then
                log_success "shellcheck installed via brew"
            else
                log_warning "Failed to install shellcheck via brew"
            fi
        elif command_exists dnf; then
            log_info "Detected dnf package manager"
            if sudo dnf install -y ShellCheck; then
                log_success "shellcheck installed via dnf"
            else
                log_warning "Failed to install shellcheck via dnf"
            fi
        else
            log_warning "No supported package manager found for shellcheck"
            log_info "Please install shellcheck manually:"
            log_info "  Ubuntu/WSL: sudo apt install shellcheck"
            log_info "  macOS: brew install shellcheck"
            log_info "  Fedora: sudo dnf install ShellCheck"
        fi
    else
        log_info "shellcheck already available"
    fi

    # Check for shfmt
    if ! command_exists shfmt || [ "$FORCE_INSTALL" = "true" ]; then
        log_step "Installing shfmt"
        if command_exists go; then
            log_info "Installing shfmt via Go"
            if go install mvdan.cc/sh/v3/cmd/shfmt@latest; then
                log_success "shfmt installed via Go"
                log_info "Make sure ~/go/bin is in your PATH"
            else
                log_warning "Failed to install shfmt via Go"
            fi
        elif command_exists brew; then
            log_info "Detected brew package manager"
            if brew install shfmt; then
                log_success "shfmt installed via brew"
            else
                log_warning "Failed to install shfmt via brew"
            fi
        else
            log_warning "No Go or brew found for shfmt installation"
            log_info "Please install shfmt manually:"
            log_info "  Go: go install mvdan.cc/sh/v3/cmd/shfmt@latest"
            log_info "  macOS: brew install shfmt"
            log_info "  Or download from: https://github.com/mvdan/sh/releases"
        fi
    else
        log_info "shfmt already available"
    fi

    return 0
}

# Function to update .gitignore
update_gitignore() {
    log_step "Updating .gitignore for development tools"

    GITIGNORE="$PROJECT_ROOT/.gitignore"

    # Add Node.js entries if not present
    if [ ! -f "$GITIGNORE" ] || ! grep -q "node_modules" "$GITIGNORE"; then
        log_step "Adding Node.js entries to .gitignore"
        cat >>"$GITIGNORE" <<'EOF'

# Node.js development tools
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
package-lock.json
.npm

EOF
        log_success "Updated .gitignore with Node.js entries"
    else
        log_info ".gitignore already contains Node.js entries"
    fi
}

# Function to create helper scripts
create_helper_scripts() {
    log_step "Creating helper scripts for development tools"

    # Create npm script helpers if they don't exist
    SCRIPTS_DIR="$PROJECT_ROOT/scripts"

    # Markdown validation helper
    cat >"$SCRIPTS_DIR/validate-markdown.sh" <<'EOF'
#!/bin/bash
# Markdown validation helper script
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "Running markdown validation..."

# Check if tools are available
if ! command -v markdownlint >/dev/null 2>&1; then
    echo "❌ markdownlint not found - run ./scripts/setup-dev-tools.sh first"
    exit 1
fi

if ! command -v prettier >/dev/null 2>&1; then
    echo "❌ prettier not found - run ./scripts/setup-dev-tools.sh first"
    exit 1
fi

# Run markdownlint
echo "🔍 Running markdownlint..."
if markdownlint "**/*.md" --ignore node_modules; then
    echo "✅ markdownlint passed"
else
    echo "❌ markdownlint found issues"
    echo "💡 Run 'markdownlint \"**/*.md\" --ignore node_modules --fix' to auto-fix"
    exit 1
fi

# Run prettier check
echo "🔍 Checking prettier formatting..."
if prettier --check "**/*.md" --ignore-path .gitignore; then
    echo "✅ prettier formatting is correct"
else
    echo "❌ prettier found formatting issues"
    echo "💡 Run 'prettier --write \"**/*.md\" --ignore-path .gitignore' to auto-fix"
    exit 1
fi

echo "✅ All markdown validation passed!"
EOF

    chmod +x "$SCRIPTS_DIR/validate-markdown.sh"
    log_success "Created validate-markdown.sh"

    # Markdown formatting helper
    cat >"$SCRIPTS_DIR/format-markdown.sh" <<'EOF'
#!/bin/bash
# Markdown formatting helper script
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "Formatting markdown files..."

# Check if tools are available
if ! command -v markdownlint >/dev/null 2>&1; then
    echo "❌ markdownlint not found - run ./scripts/setup-dev-tools.sh first"
    exit 1
fi

if ! command -v prettier >/dev/null 2>&1; then
    echo "❌ prettier not found - run ./scripts/setup-dev-tools.sh first"
    exit 1
fi

# Auto-fix with markdownlint
echo "🔧 Auto-fixing with markdownlint..."
markdownlint "**/*.md" --ignore node_modules --fix

# Format with prettier
echo "🔧 Formatting with prettier..."
prettier --write "**/*.md" --ignore-path .gitignore

echo "✅ Markdown formatting complete!"
EOF

    chmod +x "$SCRIPTS_DIR/format-markdown.sh"
    log_success "Created format-markdown.sh"
}

# Main function
main() {
    log_info "Starting development tools setup v$SCRIPT_VERSION"

    # Parse command line arguments
    NODE_ONLY=false
    SHELL_ONLY=false
    FORCE_INSTALL=false
    CHECK_ONLY=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help | -h)
                show_usage
                exit 0
                ;;
            --node-only)
                NODE_ONLY=true
                shift
                ;;
            --shell-only)
                SHELL_ONLY=true
                shift
                ;;
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --check)
                CHECK_ONLY=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Just check tools if requested
    if [ "$CHECK_ONLY" = "true" ]; then
        check_tools
        exit 0
    fi

    log_step "Setting up development tools for RUTOS Starlink Failover project"
    log_info "Project root: $PROJECT_ROOT"
    echo ""

    # Show current status
    check_tools

    # Install tools based on options
    if [ "$SHELL_ONLY" != "true" ]; then
        if ! install_node_tools; then
            log_error "Failed to install Node.js tools"
            exit 1
        fi
        echo ""
    fi

    if [ "$NODE_ONLY" != "true" ]; then
        install_shell_tools
        echo ""
    fi

    # Update project files
    update_gitignore
    create_helper_scripts

    echo ""
    log_success "Development tools setup complete!"
    echo ""

    # Final status check
    log_step "Final tool status"
    check_tools

    echo ""
    log_info "Available helper commands:"
    log_info "  ./scripts/validate-markdown.sh    - Validate all markdown files"
    log_info "  ./scripts/format-markdown.sh      - Auto-format all markdown files"
    log_info "  ./scripts/pre-commit-validation.sh - Full pre-commit validation"
    echo ""
    log_info "NPM scripts (if Node.js tools installed):"
    log_info "  npm run lint:markdown      - Lint markdown files"
    log_info "  npm run format:markdown    - Format markdown files"
    log_info "  npm run check:markdown     - Check markdown formatting"
    echo ""
    log_success "You can now run full validation with all tools available!"
}

# Run main function
main "$@"
