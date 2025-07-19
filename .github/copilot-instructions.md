# VS Code Copilot Instructions for RUTOS Starlink Failover Project

## Project Context

This is a shell-based failover solution for Starlink connectivity on RUTX50 routers running RUTOS (busybox shell
environment). The project provides automated monitoring, configuration management, and failover capabilities with Azure
integration.

## Key Project Characteristics

- **Target Environment**: RUTX50 router with RUTOS RUT5_R_00.07.09.7 (armv7l architecture)
- **Shell Requirements**: POSIX-compliant for busybox sh (not bash)
- **Deployment**: Remote installation via curl from GitHub
- **Version Management**: Automatic semantic versioning with git integration
- **Configuration**: Template-based with automatic migration system

## Shell Scripting Guidelines

### CRITICAL Shell Compatibility Rules

1. **NO bash-specific syntax** - Use POSIX sh only
2. **NO arrays** - Use space-separated strings or multiple variables
3. **NO [[]]** - Use [ ] for all conditions
4. **NO function() syntax** - Use `function_name() {` format
5. **NO local variables** - All variables are global in busybox
6. **NO echo -e** - Use printf instead
7. **NO source command** - Use . (dot) for sourcing
8. **NO $'\n'** - Use actual newlines or printf

### CRITICAL ShellCheck Compliance Rules

1. **SC2034 - Unused variables**: Only define colors you actually use, or use `# shellcheck disable=SC2034` for
   intentionally unused variables
2. **SC2181 - Exit code checking**: Use direct command testing instead of `$?`
3. **SC3045 - export -f**: Never use `export -f` - not supported in POSIX sh
4. **SC1090/SC1091 - Source files**: Add `# shellcheck source=/dev/null` or `# shellcheck disable=SC1091` for dynamic
   sources

### Function Best Practices

```bash
# Correct function definition
function_name() {
    # Always validate inputs
    if [ $# -lt 1 ]; then
        printf "Error: function_name requires at least 1 argument\n"
        return 1
    fi

    # Use explicit closing brace
    # ... function body ...
}  # Always close functions properly
```

### Variable Handling

```bash
# Correct variable assignment and usage
VARIABLE="value"
if [ -n "$VARIABLE" ]; then
    printf "Variable is set: %s\n" "$VARIABLE"
fi

# For configuration variables, always provide defaults
CONFIG_VALUE="${CONFIG_VALUE:-default_value}"
```

## Project Structure Awareness

### Core Scripts and Their Purposes

- `scripts/install-rutos.sh` - Remote installation with comprehensive logging
- `scripts/validate-config.sh` - Configuration validation with debug mode
- `scripts/update-version.sh` - Automatic version management
- `scripts/upgrade-to-advanced.sh` - Configuration upgrades
- `scripts/update-config.sh` - Configuration updates
- `scripts/pre-commit-validation.sh` - Automated RUTOS compatibility validation
- `scripts/self-update.sh` - Self-update functionality
- `scripts/uci-optimizer.sh` - UCI configuration optimizer
- `Starlink-RUTOS-Failover/starlink_monitor.sh` - Main monitoring script
- `config/config.template.sh` - Base configuration template
- `tests/` - All test scripts organized in dedicated directory

### Version Management System

- Format: `MAJOR.MINOR.PATCH+GIT_COUNT.GIT_COMMIT[-dirty]`
- All scripts must include `SCRIPT_VERSION` variable
- Use `scripts/update-version.sh` for version increments
- VERSION and VERSION_INFO files are auto-generated

## Code Generation Rules

### Always Include These Elements

1. **Version Header**: Every script needs version information
2. **Error Handling**: Comprehensive error checking with exit codes and colored output messages
3. **Logging**: Timestamped output with consistent colors for debugging
4. **Debug Mode**: Support for DEBUG=1 environment variable
5. **Safety Checks**: Validate environment before making changes
6. **Consistent Colors**: Use standard color scheme for all output messages

### Standard Color Scheme

```bash
# Color definitions (busybox compatible) - ALWAYS include ALL colors
RED='\033[0;31m'      # Errors, critical issues
GREEN='\033[0;32m'    # Success, info, completed actions
YELLOW='\033[1;33m'   # Warnings, important notices
BLUE='\033[1;35m'     # Steps, progress indicators (bright magenta for better readability)
PURPLE='\033[0;35m'   # Special status, headers
CYAN='\033[0;36m'     # Debug messages, technical info
NC='\033[0m'          # No Color (reset)

# CRITICAL: Use RUTOS-compatible color detection
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    # Colors enabled
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    # Colors disabled
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

# CRITICAL: Use proper printf format strings to avoid SC2059 errors
# WRONG: printf "${RED}Error: %s${NC}\n" "$message"
# RIGHT: printf "%sError: %s%s\n" "$RED" "$message" "$NC"

# Standard logging functions
log_info()    # Green [INFO] for general information
log_warning() # Yellow [WARNING] for warnings
log_error()   # Red [ERROR] for errors (to stderr)
log_debug()   # Cyan [DEBUG] for debug info (if DEBUG=1)
log_success() # Green [SUCCESS] for successful completion
log_step()    # Blue [STEP] for progress steps
```

### CRITICAL Printf Format Rules

1. **NEVER use variables in printf format strings** - Causes SC2059 errors
2. **Use %s placeholders** for all variable content
3. **Colors go as separate arguments** not in format string

```bash
# WRONG - Variables in format string
printf "${RED}Error: %s${NC}\n" "$message"

# RIGHT - Variables as arguments
printf "%sError: %s%s\n" "$RED" "$message" "$NC"

# WRONG - Complex format with variables
printf "${GREEN}✅ HEALTHY${NC}   | %-25s | %s\n" "$component" "$details"

# RIGHT - Colors as separate arguments
printf "%s✅ HEALTHY%s   | %-25s | %s\n" "$GREEN" "$NC" "$component" "$details"
```

### CRITICAL Color Detection Rules

1. **NEVER use `command -v tput` pattern** - Not RUTOS compatible
2. **ALWAYS use simplified pattern** shown above
3. **ALWAYS define ALL colors** (RED, GREEN, YELLOW, BLUE, CYAN, NC)
4. **NEVER use `tput colors`** - Not available in busybox

### Color Usage Examples

```bash
# Progress tracking
log_step "Installing dependencies"
log_info "Downloading configuration template"
log_success "Installation completed successfully"

# Error handling
if ! command_exists curl; then
    log_error "curl is required but not installed"
    exit 1
fi

# Warnings
if [ "$USER" != "root" ]; then
    log_warning "Running as non-root user, some features may not work"
fi

# Debug information
log_debug "Configuration file path: $CONFIG_FILE"
log_debug "Current working directory: $(pwd)"
```

### Standard Script Template

```bash
#!/bin/sh
# Script: script_name.sh
# Version: [AUTO-GENERATED]
# Description: Brief description

set -e  # Exit on error

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="1.0.2"

# Standard colors for consistent output (compatible with busybox)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;35m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in a terminal that supports colors
if [ ! -t 1 ]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Standard logging functions with consistent colors
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
    # Note: Using clean debug logging instead of set -x for better readability
fi

# Debug functions for development (cleaner than set -x)
debug_exec() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "EXECUTING: $*"
    fi
    "$@"
}

debug_var() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "VARIABLE: $1 = $2"
    fi
}

debug_func() {
    if [ "$DEBUG" = "1" ]; then
        log_debug "FUNCTION: $1"
    fi
}

# Main function
main() {
    log_info "Starting script_name.sh v$SCRIPT_VERSION"

    # Validate environment
    if [ ! -f "/etc/openwrt_release" ]; then
        log_error "This script is designed for OpenWrt/RUTOS systems"
        exit 1
    fi

    log_step "Validating environment"
    # Environment validation logic here

    log_step "Main script logic"
    # Script logic here

    log_success "Script completed successfully"
}

# Execute main function
main "$@"
```

## Configuration Management Guidelines

### Template System Rules

1. **Clean Templates**: No ShellCheck comments in template files
2. **Preserve User Values**: Always maintain user configurations during migration
3. **Backup Strategy**: Create backups before any modifications
4. **Validation**: Separate structure validation from content validation

### Configuration Variables Pattern

```bash
# Standard configuration variable format
VARIABLE_NAME="${VARIABLE_NAME:-default_value}"  # Description of what this controls

# For boolean values
ENABLE_FEATURE="${ENABLE_FEATURE:-true}"  # Enable/disable feature (true/false)

# For numeric values with validation
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-30}"  # Timeout in seconds (1-300)
```

## Error Handling and Debugging

### Standard Error Patterns

```bash
# Function with error handling and colored output
safe_operation() {
    operation="$1"  # No 'local' keyword - busybox doesn't support it
    log_debug "Attempting: $operation"

    if ! command_here; then
        log_error "Failed to $operation"
        return 1
    fi

    log_debug "Success: $operation"
    return 0
}

# Configuration validation with colors
validate_config() {
    config_file="$1"

    log_step "Validating configuration file"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    if ! grep -q "REQUIRED_VARIABLE" "$config_file"; then
        log_warning "Missing required variable in configuration"
        return 1
    fi

    log_success "Configuration validation passed"
    return 0
}

# Network operation with retry and colored feedback
download_with_retry() {
    url="$1"
    output_file="$2"
    max_attempts=3
    attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_step "Download attempt $attempt of $max_attempts"

        if curl -fsSL "$url" -o "$output_file"; then
            log_success "Download completed successfully"
            return 0
        else
            log_warning "Download attempt $attempt failed"
            attempt=$((attempt + 1))
            sleep 2
        fi
    done

    log_error "All download attempts failed"
    return 1
}
```

### Debug Mode Implementation

```bash
# Debug mode with colored output
DEBUG="${DEBUG:-0}"
if [ "$DEBUG" = "1" ]; then
    log_debug "==================== DEBUG MODE ENABLED ===================="
    set -x  # Enable command tracing
fi

# Debug logging throughout the script
log_debug "Current environment: $(uname -a)"
log_debug "Script version: $SCRIPT_VERSION"
log_debug "Working directory: $(pwd)"

# Conditional debug information
if [ "$DEBUG" = "1" ]; then
    log_debug "Full environment variables:"
    env | grep -E "(STARLINK|CONFIG|DEBUG)" | while read -r line; do
        log_debug "  $line"
    done
fi
```

## Testing and Validation

### Testing Environment Context

- **Router**: RUTX50 with RUTOS RUT5_R_00.07.09.7
- **Architecture**: armv7l
- **Shell**: busybox sh (limited POSIX compliance)
- **Network**: Starlink primary, cellular backup
- **Installation**: Remote via curl

### Common Testing Scenarios

1. **Fresh Installation**: New router setup
2. **Configuration Migration**: Upgrading from old template
3. **Debug Mode**: Troubleshooting with DEBUG=1
4. **Version Updates**: Using update-version.sh
5. **Remote Downloads**: GitHub raw content access

## VS Code Development Environment

### Terminal Configuration

- **Default Shell**: PowerShell (Windows environment)
- **Recommended for Shell Development**: Switch to WSL/bash when working on shell scripts
- **Available Options**: PowerShell, WSL, Git Bash
- **Best Practice**: Use WSL or Git Bash for shell script development and testing

### Terminal Commands for Development

```bash
# Switch to WSL for shell development
wsl

# Or use Git Bash for better POSIX compatibility
# Terminal -> Select Default Profile -> Git Bash

# Make scripts executable in WSL/Git Bash (not needed in PowerShell)
chmod +x scripts/*.sh
```

### Why Use WSL/Git Bash for Shell Development?

- **Better POSIX Compliance**: Closer to RUTOS environment
- **ShellCheck Support**: Native shell script linting
- **File Permissions**: Can set executable permissions
- **Command Compatibility**: Tools like `find`, `grep`, `awk` work as expected
- **Testing**: More accurate testing environment for shell scripts

### Code Quality and Pre-Commit Checks

#### CRITICAL: Always Run Before Commits

1. **Pre-Commit Validation**: Run `./scripts/pre-commit-validation.sh` for comprehensive checks
2. **ShellCheck**: Validate all shell scripts for POSIX compliance
3. **shfmt Integration**: Automatic formatting validation using industry standard
4. **Version Consistency**: Ensure all scripts have matching version info
5. **Template Validation**: Verify configuration templates are clean

#### Automated Pre-Commit Validation System

```bash
# Run comprehensive validation (REQUIRED before commits)
./scripts/pre-commit-validation.sh

# For staged files only (pre-commit hook)
./scripts/pre-commit-validation.sh --staged

# With debug output for troubleshooting
DEBUG=1 ./scripts/pre-commit-validation.sh

# The validation system checks:
# - ShellCheck compliance (POSIX sh only)
# - Bash-specific syntax detection
# - RUTOS compatibility patterns
# - Code formatting with shfmt
# - Critical whitespace issues
# - Template cleanliness
```

#### ShellCheck Integration

```bash
# Install ShellCheck (if not already installed)
# On WSL/Ubuntu:
sudo apt-get install shellcheck

# On Windows with Chocolatey:
choco install shellcheck

# Install shfmt for formatting validation
# On WSL/Ubuntu:
sudo apt-get install shfmt
# Or: go install mvdan.cc/sh/v3/cmd/shfmt@latest

# The pre-commit validation script handles all checks automatically
# Manual checks are no longer needed if using the validation system
```

#### Pre-Commit Quality Checklist

- [ ] Run `./scripts/pre-commit-validation.sh` and fix all issues
- [ ] All shell scripts pass ShellCheck with no errors
- [ ] No bash-specific syntax (arrays, [[]], function() syntax)
- [ ] All functions have proper closing braces
- [ ] Version information is consistent across scripts
- [ ] Debug mode support is implemented
- [ ] Error handling is comprehensive
- [ ] Templates are clean (no ShellCheck comments)
- [ ] Code formatting passes shfmt validation

#### Automated Quality Check Script

```bash
# Run comprehensive quality checks (use in WSL/Git Bash)
./scripts/pre-commit-validation.sh

# On Windows PowerShell, switch to WSL first:
wsl
./scripts/pre-commit-validation.sh

# The validation system provides:
# - Color-coded output (RED for critical, YELLOW for major, BLUE for minor)
# - Detailed issue reporting with line numbers
# - Comprehensive summary with pass/fail statistics
# - Debug mode for troubleshooting validation issues
```

#### Manual Quality Checks (if automated script fails)

```bash
# Individual checks you can run manually
shellcheck scripts/*.sh Starlink-RUTOS-Failover/*.sh
grep -r "\[\[" scripts/ Starlink-RUTOS-Failover/  # Should return nothing
grep -r "local " scripts/ Starlink-RUTOS-Failover/  # Should return nothing
grep -r "echo -e" scripts/ Starlink-RUTOS-Failover/  # Should return nothing
```

#### VS Code Extensions for Quality

- **ShellCheck**: Provides real-time shell script linting
- **Bash IDE**: Enhanced shell script editing
- **GitLens**: Better git integration for version tracking
- **Error Lens**: Inline error display

### Modern Development Workflow

1. **Switch to WSL/Bash**: Better shell script development environment
2. **Edit Scripts**: Use VS Code with ShellCheck extension
3. **Run Pre-Commit Validation**: `./scripts/pre-commit-validation.sh`
4. **Fix All Issues**: Address errors and warnings before commit
5. **Test Locally**: Validate syntax and basic functionality
6. **Commit**: Only after all quality checks pass

### Development Tools Integration

- **ShellCheck**: Automated syntax and compatibility validation
- **shfmt**: Code formatting and style validation
- **Pre-commit Hooks**: Automated quality checks before commits
- **Debug Mode**: Enhanced debugging with clean output (`DEBUG=1`)
- **Version Management**: Automatic version tracking and updates

### Quality Assurance Pipeline

```bash
# Step 1: Run pre-commit validation
./scripts/pre-commit-validation.sh

# Step 2: Fix any issues found
# Critical issues must be fixed
# Major issues should be fixed
# Minor issues can be addressed later

# Step 3: Verify fixes
./scripts/pre-commit-validation.sh --staged

# Step 4: Commit when all checks pass
git commit -m "Description of changes"
```

### Development Environment Setup

```bash
# Install required tools (WSL/Linux)
sudo apt-get update
sudo apt-get install shellcheck shfmt

# Or on Windows with Chocolatey
choco install shellcheck

# Set up pre-commit hooks (optional)
cp scripts/pre-commit-validation.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Azure Integration Considerations

### When Working with Azure Components

- Follow Azure development best practices
- Use Azure tools when available
- Implement proper authentication patterns
- Consider network connectivity requirements for RUTOS environment

### Azure Logging Integration

- Located in `Starlink-RUTOS-Failover/AzureLogging/`
- Python-based analysis tools with requirements.txt
- Bicep templates for infrastructure
- PowerShell and shell setup scripts

## File Naming and Organization

### Naming Conventions

- Scripts: `kebab-case.sh` (e.g., `validate-config.sh`)
- Configs: `config.template.sh`, `config.advanced.template.sh`
- Documentation: `UPPERCASE.md` (e.g., `TESTING.md`)
- Logs: `lowercase.log` (e.g., `installation.log`)

### Directory Structure

```text
scripts/           # All utility scripts
config/           # Configuration templates
Starlink-RUTOS-Failover/  # Main monitoring scripts
AzureLogging/     # Azure integration components
tests/            # Test scripts and validation tools
docs/             # Documentation
```

### Test Directory Organization

```text
tests/
├── README.md                      # Test documentation
├── test-suite.sh                  # Main test runner
├── test-core-logic.sh             # Core functionality tests
├── test-comprehensive-scenarios.sh # Comprehensive testing
├── test-deployment-functions.sh   # Deployment testing
├── test-final-verification.sh     # Final verification
├── test-validation-features.sh    # Validation system tests
├── test-validation-fix.sh         # Validation fixes
├── audit-rutos-compatibility.sh   # RUTOS compatibility audit
├── rutos-compatibility-test.sh    # RUTOS compatibility testing
├── verify-deployment.sh           # Deployment verification
└── verify-deployment-script.sh    # Alternative deployment verification
```

## Common Pitfalls to Avoid

1. **Bash-specific syntax** in a busybox environment
2. **Missing function closing braces** causing nested definitions
3. **ShellCheck comments** in template files
4. **Unsafe crontab modifications** (comment instead of delete)
5. **Missing error handling** in remote operations
6. **Hardcoded paths** without environment validation
7. **Version mismatches** between scripts

## Git and Version Control

### Branch Strategy

- Main branch: `main`
- Development: `feature/testing-improvements`
- All changes go through feature branches

### Pre-Commit Quality Gates

```bash
# MANDATORY: Run before every commit
./scripts/pre-commit-validation.sh

# For staged files only (pre-commit hook usage)
./scripts/pre-commit-validation.sh --staged

# With debug output for troubleshooting
DEBUG=1 ./scripts/pre-commit-validation.sh

# The validation system automatically handles:
# - ShellCheck validation
# - RUTOS compatibility checks
# - Code formatting validation
# - Version consistency checks
# - Template validation
```

### Commit Message Format

```text
Brief description of change

- Bullet point of specific change
- Another specific change
- Reference to issue/feature if applicable
- Quality: All ShellCheck issues resolved
```

### GitHub Actions/Workflows

- **Shell Script Validation**: Automated ShellCheck on all PRs
- **POSIX Compliance**: Verify busybox compatibility
- **Version Consistency**: Check all scripts have matching versions
- **Template Validation**: Ensure configuration templates are clean

## Success Metrics

### Code Quality Indicators

- ✅ POSIX sh compatibility (validated by pre-commit system)
- ✅ Comprehensive error handling (standardized logging functions)
- ✅ Debug mode support (clean, structured output)
- ✅ Timestamped logging (consistent color-coded format)
- ✅ Version information (automatic semantic versioning)
- ✅ Safe operation patterns (validated by 50+ compatibility checks)

### Testing Validation

- ✅ Works on RUTX50 with RUTOS (tested through 23 rounds)
- ✅ Remote installation via curl (production ready)
- ✅ Configuration migration (automatic template system)
- ✅ Debug mode functionality (enhanced readability)
- ✅ Version system operation (git-integrated versioning)
- ✅ Quality assurance (automated pre-commit validation)

### Development Experience

- ✅ Modern tooling integration (ShellCheck, shfmt)
- ✅ Automated quality checks (pre-commit validation)
- ✅ Clean debug output (structured logging)
- ✅ Repository organization (dedicated test directory)
- ✅ Comprehensive documentation (up-to-date guides)
- ✅ Consistent code formatting (shfmt validation)

### Production Readiness

- ✅ RUTOS compatibility (busybox shell support)
- ✅ Error handling (comprehensive safety checks)
- ✅ Configuration management (template migration)
- ✅ Remote deployment (curl installation)
- ✅ Version tracking (semantic versioning)
- ✅ Quality assurance (validation system)

---

**Remember**: This project prioritizes reliability and compatibility over advanced features. Always test changes in the
RUTOS environment and maintain backward compatibility with existing configurations.

## Current Project Status (As of July 2025)

### Development Milestones Achieved

- **Round 1-23**: Comprehensive testing and validation system development
- **Production Ready**: Full RUTOS compatibility achieved
- **Automated Quality**: Pre-commit validation system implemented
- **Repository Organized**: Clean structure with dedicated test directory
- **Debug System**: Modern, readable debug output system
- **Validation Coverage**: 50+ compatibility checks implemented

### Core Features Operational

- ✅ **Remote Installation**: Works via curl on RUTX50
- ✅ **Configuration Management**: Template migration and validation
- ✅ **Debug Mode**: Enhanced debugging with clean output
- ✅ **Version Management**: Automatic semantic versioning
- ✅ **Quality Assurance**: Comprehensive pre-commit validation
- ✅ **RUTOS Compatibility**: Full busybox shell support

### Current Focus Areas

1. **Main Monitoring Script**: Final testing of `starlink_monitor.sh`
2. **Advanced Configuration**: Complete `config.advanced.template.sh`
3. **Azure Integration**: Logging and monitoring components
4. **Documentation**: Keep all guides up-to-date

### Recent Improvements

- **Round 22**: Repository cleanup and test organization
- **Round 23**: Debug output improvements with clean, structured logging
- **Modern Tooling**: Integration of shfmt and enhanced validation
- **Development Experience**: Better debugging and quality assurance
