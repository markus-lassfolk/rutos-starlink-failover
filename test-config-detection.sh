#!/bin/sh
# Quick test script to validate config type detection logic

# Version information (auto-updated by update-version.sh)
SCRIPT_VERSION="2.7.0"
readonly SCRIPT_VERSION

# Display version if requested
if [ "${1:-}" = "--version" ]; then
    echo "test-config-detection.sh v$SCRIPT_VERSION"
    exit 0
fi

# Used for troubleshooting: echo "Configuration version: $SCRIPT_VERSION"
echo "Testing config type detection logic"
echo "=================================="

# Test with basic template
echo "Testing basic template detection:"
if grep -qE "^(DEBUG_MODE|DRY_RUN|CELLULAR_.*_MEMBER|BACKUP_DIR|DATA_LIMIT_.*_THRESHOLD|ENABLE_PERFORMANCE_LOGGING|CELLULAR_BACKUP_IFACE)" config/config.template.sh 2>/dev/null; then
    echo "❌ WRONG: Basic template detected as ADVANCED"
else
    echo "✅ CORRECT: Basic template detected as BASIC"
fi

# Test with advanced template
echo "Testing advanced template detection:"
if grep -qE "^(DEBUG_MODE|DRY_RUN|CELLULAR_.*_MEMBER|BACKUP_DIR|DATA_LIMIT_.*_THRESHOLD|ENABLE_PERFORMANCE_LOGGING|CELLULAR_BACKUP_IFACE)" config/config.advanced.template.sh 2>/dev/null; then
    echo "✅ CORRECT: Advanced template detected as ADVANCED"
    echo "  Advanced markers found:"
    grep -E "^(DEBUG_MODE|DRY_RUN|CELLULAR_.*_MEMBER|BACKUP_DIR|DATA_LIMIT_.*_THRESHOLD|ENABLE_PERFORMANCE_LOGGING|CELLULAR_BACKUP_IFACE)" config/config.advanced.template.sh 2>/dev/null | head -3 | sed 's/^/    /'
else
    echo "❌ WRONG: Advanced template detected as BASIC"
fi

echo ""
echo "Variable counts:"
echo "  Basic template: $(grep -c '^export\|^[A-Z_].*=' config/config.template.sh) variables"
echo "  Advanced template: $(grep -c '^[A-Z_].*=' config/config.advanced.template.sh) variables"
