# RUTOS Library System Documentation

## Overview

The RUTOS Library System provides standardized, reusable components for all RUTOS Starlink Failover scripts. This modular approach ensures consistency, maintainability, and proper POSIX sh compatibility across the entire project.

## Library Modules

### 1. `rutos-lib.sh` - Main Entry Point

- **Purpose**: Single include file that loads all library modules
- **Usage**: `. "$(dirname "$0")/lib/rutos-lib.sh"`
- **Features**: Auto-detection of library location, initialization functions

### 2. `rutos-colors.sh` - Color Management

- **Purpose**: Standardized color definitions for terminal output
- **Features**:
  - RUTOS-compatible color detection
  - Method 5 printf format support (required for RUTOS)
  - Enable/disable color functions
  - Standard color scheme across all scripts

### 3. `rutos-logging.sh` - 4-Level Logging Framework

- **Purpose**: Comprehensive logging system with multiple verbosity levels
- **Logging Levels**:
  - **NORMAL**: Standard operation info
  - **DRY_RUN**: Shows what would be done without executing
  - **DEBUG**: Detailed debugging with context and stack traces
  - **RUTOS_TEST_MODE**: Full execution trace with command tracking

- **Core Functions**:
  - `log_info()`, `log_success()`, `log_warning()`, `log_error()`
  - `log_debug()`, `log_trace()`, `log_step()`
  - `safe_execute()` - DRY_RUN aware command execution
  - `log_error_with_context()` - Enhanced error reporting
  - `log_script_init()` - Standard script initialization logging

### 4. `rutos-common.sh` - Utility Functions

- **Purpose**: Common utilities used across scripts
- **Categories**:
  - Environment validation
  - Command availability checking
  - File and directory operations
  - Network utilities
  - Process and service management
  - Configuration management
  - String and data utilities
  - Cleanup and error handling

## Usage Patterns

### Basic Script Setup

```bash
#!/bin/sh
# Load RUTOS library system
. "$(dirname "$0")/lib/rutos-lib.sh"

# Initialize script with full features
rutos_init "my-script" "1.0.0"

# Now use standardized functions
log_info "Script started"
safe_execute "echo 'Hello World'" "Print greeting"
```

### Simple Script Setup

```bash
#!/bin/sh
# Load RUTOS library system
. "$(dirname "$0")/lib/rutos-lib.sh"

# Minimal initialization
rutos_init_simple "my-simple-script"

log_info "Simple script started"
```

### Portable Script (No RUTOS Validation)

```bash
#!/bin/sh
# Load RUTOS library system
. "$(dirname "$0")/lib/rutos-lib.sh"

# Skip RUTOS environment validation
rutos_init_portable "my-portable-script" "1.0.0"
```

## Logging Level Examples

### NORMAL Mode (Default)

```bash
# Standard operation
log_info "Checking Starlink connection"
log_success "Connection established"
log_warning "Signal strength is low"
log_error "Connection failed"
```

### DRY_RUN Mode (DRY_RUN=1)

```bash
# Shows what would be done
safe_execute "systemctl restart starlink" "Restart Starlink service"
# Output: [DRY-RUN] Would execute: Restart Starlink service
```

### DEBUG Mode (DEBUG=1)

```bash
# Detailed debugging information
log_debug "Current signal strength: -85 dBm"
log_error_with_context "Failed to connect" "starlink-monitor.sh" "42" "check_connection"
# Shows full context: script, line, function, environment
```

### RUTOS_TEST_MODE (RUTOS_TEST_MODE=1)

```bash
# Full execution trace
log_trace "EXECUTING: curl -s http://192.168.1.1/api/status"
log_variable_change "STARLINK_STATUS" "" "ONLINE"
log_command_execution "ping -c 1 8.8.8.8"
```

## Environment Variables

### Core Variables

- `DRY_RUN=1` - Enable dry-run mode (no system changes)
- `DEBUG=1` - Enable debug logging
- `RUTOS_TEST_MODE=1` - Enable full trace logging
- `TEST_MODE=1` - Backward compatibility for RUTOS_TEST_MODE

### Control Variables

- `NO_COLOR=1` - Disable color output
- `SKIP_RUTOS_VALIDATION=1` - Skip RUTOS environment checks
- `RUTOS_LOGGING_NO_AUTO_SETUP=1` - Disable automatic logging setup
- `ALLOW_TEST_EXECUTION=1` - Allow execution in test mode

## Migration from Old Scripts

### Before (Old Pattern)

```bash
#!/bin/sh
# Old duplicate code in every script
RED='\033[0;31m'
GREEN='\033[0;32m'
# ... more colors

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}
# ... more duplicate functions

DRY_RUN="${DRY_RUN:-0}"
# ... manual setup
```

### After (New Library Pattern)

```bash
#!/bin/sh
# New standardized approach
. "$(dirname "$0")/lib/rutos-lib.sh"
rutos_init "script-name" "1.0.0"

# All functions and colors available immediately
log_info "Ready to go with standardized logging"
safe_execute "echo test" "Test command"
```

## Benefits

### Consistency

- All scripts use identical logging format
- Standardized color scheme
- Consistent error handling patterns

### Maintainability

- Update logging behavior once, affects all scripts
- Centralized bug fixes
- Single source of truth for common functions

### RUTOS Compatibility

- Tested with busybox sh
- POSIX sh compliance
- Method 5 printf format support

### Enhanced Debugging

- 4-level logging system
- Command execution tracing
- Variable change tracking
- Error context with stack traces

### Safety

- DRY_RUN mode prevents accidental changes
- Test mode validation
- Automatic cleanup handlers

## Testing

The library system integrates with `dev-testing-rutos.sh` to validate:

- All scripts properly load the library
- Logging levels work correctly
- Error handling is consistent
- RUTOS compatibility is maintained

## File Structure

```
scripts/
├── lib/
│   ├── rutos-lib.sh          # Main entry point
│   ├── rutos-colors.sh       # Color management
│   ├── rutos-logging.sh      # 4-level logging framework
│   ├── rutos-common.sh       # Common utilities
│   └── README.md             # This documentation
└── [script-name].sh          # Scripts using the library
```

## Future Extensions

The library system is designed to be extensible:

- Additional utility modules can be added to `lib/`
- New logging levels can be implemented
- Platform-specific modules can be included
- Advanced debugging features can be added

This modular approach ensures the RUTOS project remains maintainable and consistent as it grows.
