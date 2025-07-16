#!/bin/bash
# Setup script for comprehensive code quality tools
# Version: 1.0.2
# Description: Installs all code quality tools for the RUTOS Starlink Failover project

set -e

# Version information
SCRIPT_VERSION="1.0.2"

# Standard colors for consistent output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

log_step() {
    printf "${BLUE}[STEP]${NC} [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install system packages
install_system_packages() {
    log_step "Installing system packages"

    if command_exists apt-get; then
        log_info "Using apt-get (Ubuntu/Debian)"
        sudo apt-get update
        sudo apt-get install -y shellcheck shfmt jq curl wget
    elif command_exists brew; then
        log_info "Using brew (macOS)"
        brew install shellcheck shfmt jq
    elif command_exists yum; then
        log_info "Using yum (CentOS/RHEL)"
        sudo yum install -y jq curl wget
        log_warning "shellcheck and shfmt may need manual installation"
    else
        log_error "No supported package manager found"
        return 1
    fi
}

# Function to install Python tools
install_python_tools() {
    log_step "Installing Python code quality tools"

    if ! command_exists python3; then
        log_error "Python 3 is required but not installed"
        return 1
    fi

    if ! command_exists pip3; then
        log_error "pip3 is required but not installed"
        return 1
    fi

    log_info "Installing Python tools with pip3"
    pip3 install --user black flake8 pylint mypy isort bandit yamllint

    # Add user bin to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_info "Adding ~/.local/bin to PATH"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >>~/.bashrc
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

# Function to install Node.js tools
install_nodejs_tools() {
    log_step "Installing Node.js code quality tools"

    if ! command_exists node; then
        log_warning "Node.js not found. Installing Node.js tools may fail."
        log_info "Install Node.js from https://nodejs.org/ or use your package manager:"
        log_info "  Ubuntu/Debian: sudo apt-get install nodejs npm"
        log_info "  macOS: brew install node"
        return 1
    fi

    if ! command_exists npm; then
        log_error "npm is required but not installed"
        return 1
    fi

    log_info "Installing Node.js tools with npm"
    npm install -g markdownlint-cli prettier
}

# Function to install PowerShell tools
install_powershell_tools() {
    log_step "Installing PowerShell code quality tools"

    if ! command_exists pwsh; then
        log_warning "PowerShell Core not found. Skipping PowerShell tools installation."
        log_info "Install PowerShell Core from https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
        return 1
    fi

    log_info "Installing PSScriptAnalyzer module"
    pwsh -Command "Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser"
}

# Function to install Azure Bicep
install_bicep_tools() {
    log_step "Installing Azure Bicep CLI"

    if ! command_exists az; then
        log_warning "Azure CLI not found. Skipping Bicep installation."
        log_info "Install Azure CLI from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        return 1
    fi

    log_info "Installing Bicep CLI via Azure CLI"
    az bicep install
}

# Function to install Go tools (for shfmt if not available in package manager)
install_go_tools() {
    log_step "Installing Go-based tools"

    if ! command_exists go; then
        log_warning "Go not found. Skipping Go-based tools installation."
        log_info "Install Go from https://golang.org/dl/"
        return 1
    fi

    log_info "Installing shfmt via Go"
    go install mvdan.cc/sh/v3/cmd/shfmt@latest

    # Add GOPATH/bin to PATH if not already there
    GOPATH=$(go env GOPATH)
    if [[ ":$PATH:" != *":$GOPATH/bin:"* ]]; then
        log_info "Adding $GOPATH/bin to PATH"
        echo "export PATH=\"$GOPATH/bin:\$PATH\"" >>~/.bashrc
        export PATH="$GOPATH/bin:$PATH"
    fi
}

# Function to verify installations
verify_installations() {
    log_step "Verifying installations"

    local tools=(
        "shellcheck:Shell script linting"
        "shfmt:Shell script formatting"
        "black:Python code formatting"
        "flake8:Python style guide enforcement"
        "pylint:Python comprehensive linting"
        "mypy:Python type checking"
        "isort:Python import sorting"
        "bandit:Python security scanning"
        "markdownlint:Markdown linting"
        "prettier:Code formatting"
        "jq:JSON processing"
        "yamllint:YAML linting"
        "pwsh:PowerShell Core"
        "bicep:Azure Bicep CLI"
    )

    local available_count=0
    local total_count=${#tools[@]}

    for tool_info in "${tools[@]}"; do
        IFS=":" read -r tool_name tool_description <<<"$tool_info"
        if command_exists "$tool_name"; then
            log_info "✅ $tool_name ($tool_description) - Available"
            available_count=$((available_count + 1))
        else
            log_warning "❌ $tool_name ($tool_description) - Not available"
        fi
    done

    log_info "Tool availability: $available_count/$total_count tools available"

    if [ "$available_count" -eq "$total_count" ]; then
        log_info "🎉 All tools successfully installed!"
        return 0
    else
        log_warning "Some tools are missing. Check the warnings above."
        return 1
    fi
}

# Function to show manual installation instructions
show_manual_instructions() {
    log_step "Manual installation instructions for missing tools"

    cat <<EOF

=== MANUAL INSTALLATION INSTRUCTIONS ===

If automatic installation failed, here are manual installation commands:

Ubuntu/Debian:
    sudo apt-get update
    sudo apt-get install -y shellcheck shfmt jq nodejs npm
    pip3 install --user black flake8 pylint mypy isort bandit yamllint
    npm install -g markdownlint-cli prettier
    
    # For PowerShell (optional)
    wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    sudo apt-get update
    sudo apt-get install -y powershell
    
    # For Azure CLI and Bicep (optional)
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    az bicep install

macOS:
    brew install shellcheck shfmt jq node
    pip3 install --user black flake8 pylint mypy isort bandit yamllint
    npm install -g markdownlint-cli prettier
    
    # For PowerShell (optional)
    brew install --cask powershell
    
    # For Azure CLI and Bicep (optional)
    brew install azure-cli
    az bicep install

Windows (PowerShell):
    # Install Chocolatey package manager first
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    
    # Install tools
    choco install shellcheck jq nodejs python3 azure-cli
    pip install black flake8 pylint mypy isort bandit yamllint
    npm install -g markdownlint-cli prettier
    az bicep install

Using package managers:
    - Ubuntu/Debian: apt-get
    - macOS: brew
    - Windows: choco
    - Node.js: npm
    - Python: pip3
    - Go: go install

EOF
}

# Function to create a convenient alias
create_validation_alias() {
    log_step "Creating convenient validation alias"

    local alias_line
    alias_line="alias validate-code='$(pwd)/scripts/comprehensive-validation.sh'"
    local bashrc_file="$HOME/.bashrc"

    if [ -f "$bashrc_file" ]; then
        if ! grep -q "validate-code" "$bashrc_file"; then
            echo "$alias_line" >>"$bashrc_file"
            log_info "Added 'validate-code' alias to ~/.bashrc"
            log_info "Run 'source ~/.bashrc' or restart your terminal to use the alias"
        else
            log_info "Alias 'validate-code' already exists in ~/.bashrc"
        fi
    else
        log_warning "~/.bashrc not found. You can manually add: $alias_line"
    fi
}

# Function to show usage
show_usage() {
    cat <<EOF
Setup script for comprehensive code quality tools

Usage: $0 [OPTIONS]

Options:
    --system        Install system packages only (shellcheck, shfmt, jq)
    --python        Install Python tools only (black, flake8, pylint, etc.)
    --nodejs        Install Node.js tools only (markdownlint, prettier)
    --powershell    Install PowerShell tools only (PSScriptAnalyzer)
    --bicep         Install Azure Bicep CLI only
    --go            Install Go-based tools only (shfmt)
    --verify        Verify installations only
    --manual        Show manual installation instructions
    --help, -h      Show this help message

Examples:
    $0                  # Install all tools
    $0 --python         # Install only Python tools
    $0 --verify         # Check what's already installed
    $0 --manual         # Show manual installation instructions

EOF
}

# Main function
main() {
    local install_system=false
    local install_python=false
    local install_nodejs=false
    local install_powershell=false
    local install_bicep=false
    local install_go=false
    local verify_only=false
    local show_manual=false
    local install_all=true

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system)
                install_system=true
                install_all=false
                shift
                ;;
            --python)
                install_python=true
                install_all=false
                shift
                ;;
            --nodejs)
                install_nodejs=true
                install_all=false
                shift
                ;;
            --powershell)
                install_powershell=true
                install_all=false
                shift
                ;;
            --bicep)
                install_bicep=true
                install_all=false
                shift
                ;;
            --go)
                install_go=true
                install_all=false
                shift
                ;;
            --verify)
                verify_only=true
                shift
                ;;
            --manual)
                show_manual=true
                shift
                ;;
            --help | -h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    log_info "Starting code quality tools setup v$SCRIPT_VERSION"

    if [ "$show_manual" = true ]; then
        show_manual_instructions
        exit 0
    fi

    if [ "$verify_only" = true ]; then
        verify_installations
        exit $?
    fi

    # Install tools based on options
    if [ "$install_all" = true ]; then
        install_system_packages || log_warning "Some system packages may have failed"
        install_python_tools || log_warning "Some Python tools may have failed"
        install_nodejs_tools || log_warning "Some Node.js tools may have failed"
        install_powershell_tools || log_warning "PowerShell tools installation may have failed"
        install_bicep_tools || log_warning "Bicep installation may have failed"
        install_go_tools || log_warning "Go tools installation may have failed"
    else
        [ "$install_system" = true ] && install_system_packages
        [ "$install_python" = true ] && install_python_tools
        [ "$install_nodejs" = true ] && install_nodejs_tools
        [ "$install_powershell" = true ] && install_powershell_tools
        [ "$install_bicep" = true ] && install_bicep_tools
        [ "$install_go" = true ] && install_go_tools
    fi

    # Always verify installations
    verify_installations

    # Create convenient alias
    create_validation_alias

    log_info "Setup completed! You can now run comprehensive code validation:"
    log_info "  ./scripts/comprehensive-validation.sh --all"
    log_info "  validate-code --all  # (after sourcing ~/.bashrc)"
}

# Execute main function
main "$@"
