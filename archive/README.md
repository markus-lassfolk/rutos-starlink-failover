# Legacy Archive

This directory contains the complete legacy Bash-based implementation of the RUTOS Starlink 
Failover system, preserved for reference during the Go rewrite transition.

## What's Archived

### `/legacy-bash/`
- **All original shell scripts** (`.sh` files) - The complete Bash implementation
- **Analysis and documentation** - All `*ANALYSIS*.md`, `*SUMMARY*.md`, `*IMPLEMENTATION*.md` files  
- **Test files and logs** - Development test files, validation results, debug logs
- **Legacy configuration** - Original `config/` directory and related files
- **Integration modules** - `gps-integration/`, `cellular-integration/`, `automation/` directories
- **Development tools** - PowerShell scripts, Python utilities, Node.js packages
- **Documentation archive** - All implementation guides, troubleshooting docs, migration notes

### Purpose
- **Reference implementation** - Complete working Bash system for comparison
- **Migration guidance** - Understanding existing logic for Go implementation  
- **Troubleshooting** - Historical context for decisions and implementations
- **Documentation** - Preserved analysis and lessons learned

## Current Status

The legacy system is **feature complete** and **functionally tested** but is being replaced 
by a Go-based daemon (`starfaild`) for better:
- Performance and resource efficiency
- Type safety and maintainability  
- Cross-compilation and deployment
- Integration with OpenWrt/RutOS ecosystems

## Script Overview

Key components that were replaced by the Go daemon:

### Core Scripts
- `starlink_monitor_unified-rutos.sh` - Main monitoring loop
- `connection-scoring-system-rutos.sh` - Interface scoring logic
- `intelligent-failover-manager-rutos.sh` - Decision engine
- `install-rutos.sh` - Installation and setup

### Supporting Components
- `lib/rutos-lib.sh` - Shared library functions
- `collectors/` - Interface metric collection scripts
- `scoring/` - Scoring algorithm implementations
- Various test and analysis scripts

## Migration to Go

The Go implementation (`starfaild`) provides equivalent functionality with:

### Improvements
- **Performance**: Single binary vs multiple script processes
- **Memory**: Predictable RAM usage vs variable script overhead
- **Reliability**: Compiled binary vs shell script interpretation
- **Integration**: Native UCI/ubus vs external command calls
- **Maintainability**: Type safety vs string manipulation

### Compatibility
- Same UCI configuration format
- Compatible member discovery logic
- Equivalent scoring algorithms
- Same mwan3 integration approach

## Reference Use

These scripts remain valuable for:

1. **Algorithm Reference**: Understanding the original scoring logic
2. **Platform Compatibility**: Checking RUTOS-specific integrations
3. **Debugging**: Comparing behavior between implementations
4. **Education**: Learning the evolution of the system

## Not for Production

**Do not use these scripts in production environments.** They are:

- No longer maintained or updated
- Missing recent bug fixes and improvements
- Less efficient than the Go implementation
- Potentially incompatible with newer firmware versions

## Documentation

Original documentation for the Bash implementation can be found in:

- `DEPLOYMENT-GUIDE.md` - Installation procedures
- `TESTING.md` - Testing methodologies
- `RUTOS-PERSISTENT-STORAGE.md` - Storage architecture
- Various `*_SUMMARY.md` files - Feature documentation

## Support

For issues or questions about the legacy implementation:

1. **Migration**: See `docs/MIGRATION_GUIDE.md` for transition help
2. **Current System**: Use the Go implementation and its documentation
3. **Historical Questions**: Reference the preserved documentation in this archive

**Last Active Version**: 3.x (July 2025)
