# Test Suite Documentation

**Version:** 2.6.0 | **Updated:** 2025-07-24

**Version:** 2.5.0 | **Updated:** 2025-07-24

**Version:** 2.4.12 | **Updated:** 2025-07-21

**Version:** 2.4.11 | **Updated:** 2025-07-21

**Version:** 2.4.10 | **Updated:** 2025-07-21

**Version:** 2.4.9 | **Updated:** 2025-07-21

**Version:** 2.4.8 | **Updated:** 2025-07-21

**Version:** 2.4.7 | **Updated:** 2025-07-21

This directory contains all test scripts for the RUTOS Starlink failover solution.

## Test Categories

### Core Functionality Tests

- **test-suite.sh** - Main test suite runner
- **test-core-logic.sh** - Tests core monitoring and failover logic
- **test-comprehensive-scenarios.sh** - Comprehensive scenario testing

### Deployment Tests

- **test-deployment-functions.sh** - Tests deployment script functions
- **test-final-verification.sh** - Final verification tests after deployment

### Compatibility Tests

- **audit-rutos-compatibility.sh** - Audits scripts for RUTOS compatibility
- **rutos-compatibility-test.sh** - Tests RUTOS-specific compatibility

### Validation Tests

- **test-validation-features.sh** - Tests validation system features
- **test-validation-fix.sh** - Tests validation fixes and improvements

### Verification Scripts

- **verify-deployment.sh** - Verifies deployment script compatibility
- **verify-deployment-script.sh** - Alternative deployment verification

## Running Tests

### Individual Tests

```bash
# Run a specific test
./tests/test-suite.sh

# Run with debug output
DEBUG=1 ./tests/test-core-logic.sh
```

### RUTOS Compatibility Tests

```bash
# Check RUTOS compatibility
./tests/audit-rutos-compatibility.sh

# Test on actual RUTOS device
./tests/rutos-compatibility-test.sh
```

### Deployment Verification

```bash
# Verify deployment scripts before use
./tests/verify-deployment.sh
./tests/verify-deployment-script.sh
```

## Test Results

All tests should pass before deployment to production. See `TESTING.md` in the root directory for detailed test results
and history.

## Development

When adding new tests:

1. Follow the naming convention: `test-*.sh`
2. Include proper error handling and exit codes
3. Add debug output support with `DEBUG=1`
4. Update this README with test description
