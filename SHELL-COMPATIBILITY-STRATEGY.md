# RUTOS Shell Compatibility Strategy

## Problem
RUTOS uses ash/dash shell, but our CI/CD workflows expect bash syntax for proper validation.

## Solution: Dual Compatibility Approach

### For Deployment Scripts (RUTOS-specific)
- Use `#!/bin/sh` shebang
- POSIX shell syntax only
- Compatible with ash/dash
- Examples: `deploy-starlink-solution.sh`, `rutos-compatibility-test.sh`

### For Development/CI Scripts (Development environment)
- Keep `#!/bin/bash` shebang  
- Can use bash-specific features
- Validated by CI/CD workflows
- Examples: All scripts in `Starlink-RUTOS-Failover/` folder

## Enforced POSIX Compliance Standards

The `audit-rutos-compatibility.sh` script now enforces these critical POSIX compliance standards:

### CRITICAL Issues (Will Break on RUTOS):
1. **`local` variables** - Not supported in busybox shell
   - ❌ `local var="value"`
   - ✅ `var="value"` (use global variables or function parameters)

2. **`function()` syntax** - Use POSIX function format
   - ❌ `function name() { ... }`
   - ✅ `name() { ... }`

3. **Double brackets `[[ ]]`** - Use single brackets for compatibility
   - ❌ `if [[ condition ]]; then`
   - ✅ `if [ condition ]; then`

4. **Bash arrays** - Not supported in POSIX shell
   - ❌ `declare -a array=("one" "two")`
   - ✅ `list="one two three"` (space-separated strings)

5. **`echo -e`** - Use `printf` for formatted output
   - ❌ `echo -e "Line1\nLine2"`
   - ✅ `printf "Line1\nLine2\n"`

6. **`source` command** - Use dot sourcing for POSIX compliance
   - ❌ `source ./script.sh`
   - ✅ `. ./script.sh`

7. **`$'\n'` constructs** - Use actual newlines or printf
   - ❌ `echo $'Line1\nLine2'`
   - ✅ `printf "Line1\nLine2\n"`

### Audit Script Features

The enhanced `audit-rutos-compatibility.sh` script provides:

- **Comprehensive POSIX checking** for all critical compatibility issues
- **Detailed reporting** with categorized issues (CRITICAL vs WARNING)
- **Exit code enforcement** - Returns 1 if critical issues found
- **Colored output** for easy issue identification
- **Actionable recommendations** for fixing each type of issue

### Running the Audit

```bash
# Run the audit on all scripts
./audit-rutos-compatibility.sh

# Check for critical issues only
./audit-rutos-compatibility.sh | grep CRITICAL

# Get exit code for CI/CD integration
./audit-rutos-compatibility.sh && echo "POSIX compliant" || echo "Issues found"
```

### Implementation Strategy

#### Option 1: Rename Deployment Script
- `deploy-starlink-solution.sh` → `deploy-starlink-solution-rutos.sh`
- Keep original with bash shebang for CI/CD
- New version optimized for RUTOS

#### Option 2: Conditional Shebang Detection
- Scripts detect their runtime environment
- Use appropriate syntax based on available shell

#### Option 3: CI/CD Workflow Updates
- Update shellcheck to handle both bash and POSIX sh
- Add special handling for RUTOS-specific scripts

## Recommended Approach: Option 1

1. **Keep existing scripts as-is** (bash shebangs for CI/CD)
2. **Create RUTOS-specific variants** for deployment
3. **Update CI/CD to validate both versions**

This maintains CI/CD integrity while providing RUTOS compatibility.
