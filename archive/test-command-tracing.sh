#!/bin/sh

# Simple test to demonstrate RUTOS_TEST_MODE command tracing
# This simulates the kind of commands that would be traced

echo "=== Command Tracing Test ==="
echo "This demonstrates how command tracing will appear in RUTOS_TEST_MODE=1"
echo ""

# Simulate the logging functions
log_trace_command() {
    local command_description="$1"
    shift
    local command_line="$*"
    
    if [ "${RUTOS_TEST_MODE:-0}" = "1" ]; then
        echo "[DEBUG] 🔍 [TRACE] $command_description"
        echo "[DEBUG] 📝 [CMD] $command_line"
    fi
}

smart_debug() {
    echo "[DEBUG] $*"
}

# Set RUTOS_TEST_MODE
export RUTOS_TEST_MODE=1

echo "--- With RUTOS_TEST_MODE=1 ---"
log_trace_command "Test UCI access to mwan3" "uci show mwan3"
log_trace_command "Extract interface lines from UCI" "uci show mwan3 | grep '\\.interface='"
log_trace_command "Get MWAN3 status" "mwan3 status"
log_trace_command "Search for member matching interface" "uci show mwan3 | grep \"interface='wan'\""

echo ""
echo "--- With RUTOS_TEST_MODE=0 (normal mode) ---"
export RUTOS_TEST_MODE=0
log_trace_command "Test UCI access to mwan3" "uci show mwan3"
log_trace_command "Get MWAN3 status" "mwan3 status"

echo ""
echo "=== End Test ==="
