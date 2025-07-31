#!/bin/sh
# Test script to verify configuration debug output and no early exits
# Version: 2.8.0

set -e

# Version information
SCRIPT_VERSION="2.8.0"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

printf "${GREEN}=== RUTOS Configuration Debug Test ===${NC}\n"
printf "Testing all three main scripts with DEBUG=1 and RUTOS_TEST_MODE=1\n\n"

# Create a minimal test config file
TEST_CONFIG="/tmp/test-starlink-config.sh"
printf "${YELLOW}Creating test configuration file: $TEST_CONFIG${NC}\n"

cat >"$TEST_CONFIG" <<'EOF'
# Test configuration for RUTOS Starlink Failover
STARLINK_IP="192.168.100.1"
MWAN_IFACE="starlink"
MWAN_MEMBER="starlink_m1_w1"
ENABLE_GPS_TRACKING="true"
ENABLE_CELLULAR_TRACKING="false"
ENABLE_ENHANCED_FAILOVER="true"
ENABLE_PUSHOVER="false"
LATENCY_THRESHOLD="500"
PACKET_LOSS_THRESHOLD="5"
OBSTRUCTION_THRESHOLD="10"
LOG_DIR="/tmp/starlink-test-logs"
STATE_DIR="/tmp/starlink-test-state"
LOG_TAG="StarlinkTest"
PUSHOVER_TOKEN="test_token_placeholder"
PUSHOVER_USER="test_user_placeholder"
EOF

printf "Test config created with sample values.\n\n"

# Test 1: Starlink Monitor Unified
printf "${YELLOW}Test 1: Testing starlink_monitor_unified-rutos.sh${NC}\n"
if [ -f "Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh" ]; then
    printf "Running with DEBUG=1 RUTOS_TEST_MODE=1 ALLOW_TEST_EXECUTION=1 CONFIG_FILE=$TEST_CONFIG\n"
    DEBUG=1 RUTOS_TEST_MODE=1 ALLOW_TEST_EXECUTION=1 CONFIG_FILE="$TEST_CONFIG" timeout 15s sh Starlink-RUTOS-Failover/starlink_monitor_unified-rutos.sh 2>&1 | head -100 || {
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            printf "${GREEN}✓ Script ran for full timeout with configuration debug output${NC}\n"
        else
            printf "${RED}✗ Script exited with code $exit_code${NC}\n"
        fi
    }
else
    printf "${RED}✗ Script not found${NC}\n"
fi

printf "\n${YELLOW}Test 2: Testing starlink_logger_unified-rutos.sh${NC}\n"
if [ -f "Starlink-RUTOS-Failover/starlink_logger_unified-rutos.sh" ]; then
    printf "Running with DEBUG=1 RUTOS_TEST_MODE=1 ALLOW_TEST_EXECUTION=1 CONFIG_FILE=$TEST_CONFIG\n"
    DEBUG=1 RUTOS_TEST_MODE=1 ALLOW_TEST_EXECUTION=1 CONFIG_FILE="$TEST_CONFIG" timeout 15s sh Starlink-RUTOS-Failover/starlink_logger_unified-rutos.sh 2>&1 | head -100 || {
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            printf "${GREEN}✓ Script ran for full timeout with configuration debug output${NC}\n"
        else
            printf "${RED}✗ Script exited with code $exit_code${NC}\n"
        fi
    }
else
    printf "${RED}✗ Script not found${NC}\n"
fi

printf "\n${YELLOW}Test 3: Testing check_starlink_api-rutos.sh${NC}\n"
if [ -f "Starlink-RUTOS-Failover/check_starlink_api-rutos.sh" ]; then
    printf "Running with DEBUG=1 RUTOS_TEST_MODE=1 ALLOW_TEST_EXECUTION=1 CONFIG_FILE=$TEST_CONFIG\n"
    DEBUG=1 RUTOS_TEST_MODE=1 ALLOW_TEST_EXECUTION=1 CONFIG_FILE="$TEST_CONFIG" timeout 15s sh Starlink-RUTOS-Failover/check_starlink_api-rutos.sh 2>&1 | head -100 || {
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            printf "${GREEN}✓ Script ran for full timeout with configuration debug output${NC}\n"
        else
            printf "${RED}✗ Script exited with code $exit_code${NC}\n"
        fi
    }
else
    printf "${RED}✗ Script not found${NC}\n"
fi

# Cleanup
printf "\n${YELLOW}Cleaning up test files${NC}\n"
rm -f "$TEST_CONFIG"

printf "\n%s=== Test Complete ===%s\n" "$GREEN" "$NC"
printf "Expected behavior:\n"
printf "- Scripts should show comprehensive configuration debug output\n"
printf "- RUTOS_TEST_MODE=1 normally causes early exit (correct for syntax validation)\n"
printf "- ALLOW_TEST_EXECUTION=1 overrides early exit for full testing\n"
printf "- Each script should show all loaded config values when DEBUG=1\n"
printf "- Scripts run normally with enhanced trace logging when allowed\n"
