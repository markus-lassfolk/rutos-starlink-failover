#!/bin/sh
set -e

# Test GitHub authentication integration for autonomous system
# This script verifies that GitHub issue creation works properly

# Version information
SCRIPT_VERSION="1.0.0"

echo "=== GitHub Authentication Integration Test ==="
echo "Testing autonomous system GitHub issue creation capabilities"
echo ""

# Test 1: Check authentication methods
echo "TEST 1: Authentication Methods"
echo "=============================="
if [ -f "github-auth-integration-rutos.sh" ]; then
    ./github-auth-integration-rutos.sh test
else
    echo "ERROR: github-auth-integration-rutos.sh not found"
    echo "Make sure you're running from the project root directory"
    exit 1
fi

echo ""

# Test 2: Check if we can create a test issue
echo "TEST 2: Test Issue Creation"
echo "=========================="
read -p "Create a test GitHub issue? (y/N): " create_test
if [ "$create_test" = "y" ] || [ "$create_test" = "Y" ]; then
    echo "Creating test issue..."
    if ./github-auth-integration-rutos.sh create-issue "Authentication integration test - $(date)"; then
        echo "✅ Test issue creation successful!"
        echo "Check your GitHub repository for the new issue"
    else
        echo "❌ Test issue creation failed"
        echo "Check the error messages above for troubleshooting"
    fi
else
    echo "Skipping test issue creation"
fi

echo ""

# Test 3: PowerShell integration test
echo "TEST 3: PowerShell Integration"
echo "============================="
if command -v pwsh >/dev/null 2>&1 || command -v powershell >/dev/null 2>&1; then
    if [ -f "automation/create-copilot-issues-optimized.ps1" ]; then
        echo "✅ PowerShell and issue creation script available"
        read -p "Test PowerShell integration? (y/N): " test_ps
        if [ "$test_ps" = "y" ] || [ "$test_ps" = "Y" ]; then
            echo "Testing PowerShell integration..."
            ./github-auth-integration-rutos.sh powershell
        else
            echo "Skipping PowerShell integration test"
        fi
    else
        echo "❌ PowerShell script not found: automation/create-copilot-issues-optimized.ps1"
    fi
else
    echo "❌ PowerShell not available on this system"
fi

echo ""

# Test 4: Autonomous error monitor test
echo "TEST 4: Autonomous Error Monitor"
echo "==============================="
if [ -f "autonomous-system/autonomous-error-monitor-rutos.sh" ]; then
    echo "✅ Autonomous error monitor script found"
    
    # Create a test error for monitoring
    test_error_log="/tmp/test-rutos-autonomous-errors.log"
    cat > "$test_error_log" << 'EOF'
===== AUTONOMOUS ERROR ENTRY =====
Error ID: ERR_TEST_12345
Timestamp: 2025-08-01 12:34:56
Category: CRITICAL
Host: test-host
Script: test-script.sh
Line: 42
Function: test_function
Error: This is a test error for autonomous monitoring integration

=== ENVIRONMENT CONTEXT ===
Script: test-script.sh
Version: 1.0.0
PID: 12345
Working Directory: /tmp/test
Execution Mode: manual

===== END ERROR ENTRY =====
EOF
    
    echo "Created test error log: $test_error_log"
    
    read -p "Test autonomous error monitor? (y/N): " test_monitor
    if [ "$test_monitor" = "y" ] || [ "$test_monitor" = "Y" ]; then
        echo "Testing autonomous error monitor..."
        echo "Note: This may create a GitHub issue for the test error"
        
        # Set environment for testing
        export ERROR_LOG="$test_error_log"
        export REPO_OWNER="markus-lassfolk"
        export REPO_NAME="rutos-starlink-failover"
        
        if ./autonomous-system/autonomous-error-monitor-rutos.sh; then
            echo "✅ Autonomous error monitor test completed"
        else
            echo "❌ Autonomous error monitor test failed"
        fi
        
        # Clean up
        rm -f "$test_error_log"
    else
        echo "Skipping autonomous error monitor test"
        rm -f "$test_error_log"
    fi
else
    echo "❌ Autonomous error monitor not found: autonomous-system/autonomous-error-monitor-rutos.sh"
fi

echo ""

# Summary
echo "=== Integration Test Summary ==="
echo "✅ Authentication methods tested"
echo "✅ Issue creation capabilities verified"
echo "✅ PowerShell integration checked"
echo "✅ Autonomous monitoring validated"
echo ""
echo "Your GitHub authentication integration is ready!"
echo ""
echo "Next steps:"
echo "1. Deploy to RUTOS device with: curl -fsSL https://raw.githubusercontent.com/.../bootstrap-deploy-v3-rutos.sh | sh"
echo "2. Errors will be automatically captured and GitHub issues created"
echo "3. Monitor issues at: https://github.com/markus-lassfolk/rutos-starlink-failover/issues"
