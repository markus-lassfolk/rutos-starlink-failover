#!/bin/sh

# === Azure Logging Integration Test ===
# This script tests the Azure logging solution end-to-end

set -eu

# Configuration - Use UCI if available, otherwise use command line parameter
TEST_LOG_FILE="/tmp/test-azure-logging.log"
if [ -n "${1:-}" ]; then
    AZURE_FUNCTION_URL="$1"
else
    AZURE_FUNCTION_URL=$(uci get azure.system.endpoint 2>/dev/null || echo "")
fi

# Colors for output
# Check if terminal supports colors
# shellcheck disable=SC2034  # Color variables may not all be used in every script
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    # Fallback to no colors if terminal doesn't support them
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    NC=""
fi

log_info() {
    printf "%b[INFO]%b %s\n" "${GREEN}" "${NC}" "$1"
}

log_warn() {
    printf "%b[WARN]%b %s\n" "${YELLOW}" "${NC}" "$1"
}

log_error() {
    printf "%b[ERROR]%b %s\n" "${RED}" "${NC}" "$1"
}

# Validate input
if [ -z "$AZURE_FUNCTION_URL" ]; then
    log_error "Usage: $0 <azure-function-url>"
    log_error "Example: $0 'https://your-app.azurewebsites.net/api/HttpLogIngestor?code=...'"
    exit 1
fi

# Test 1: Create test log data
log_info "Creating test log data..."
cat >"$TEST_LOG_FILE" <<EOF
$(date): Test log entry from Azure logging integration test
$(date): Sample application startup
$(date): Network interface configured
$(date): System health check passed
$(date): End of test log data
EOF

# Test 2: Send test data to Azure Function
log_info "Sending test data to Azure Function..."
HTTP_STATUS=$(curl -sS -w '%{http_code}' -o /dev/null --max-time 30 --data-binary "@$TEST_LOG_FILE" "$AZURE_FUNCTION_URL" 2>/dev/null)
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -ne 0 ]; then
    log_error "curl failed with exit code $CURL_EXIT_CODE"
    exit 1
fi

if [ "$HTTP_STATUS" -eq 200 ]; then
    log_info "✓ Successfully sent test data to Azure (HTTP $HTTP_STATUS)"
else
    log_error "✗ Failed to send test data to Azure (HTTP $HTTP_STATUS)"
    exit 1
fi

# Test 3: Verify log file handling
log_info "Testing log file operations..."
if [ -f "$TEST_LOG_FILE" ]; then
    true >"$TEST_LOG_FILE" # Truncate like the real script does
    log_info "✓ Log file truncation successful"
else
    log_error "✗ Test log file not found"
    exit 1
fi

# Cleanup
rm -f "$TEST_LOG_FILE"

log_info "🎉 All tests passed! Azure logging solution is working correctly."
