#!/usr/bin/env pwsh
# Live test for Copilot assignment functionality
param(
    [switch]$Live = $false
)

Write-Host "Testing Copilot Assignment Workflow..." -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

if (-not $Live) {
    Write-Host "This is a DRY RUN. Use -Live flag to create actual test issue." -ForegroundColor Yellow
    Write-Host "Command: .\test-copilot-live.ps1 -Live" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# Load the enhanced script functions
Write-Host "Loading enhanced script functions..." -ForegroundColor Yellow
$scriptPath = ".\automation\Create-RUTOS-PRs.ps1"

# Extract just the functions we need without running the main script
$scriptContent = Get-Content $scriptPath -Raw

# Find the New-CopilotIssue function
$functionStart = $scriptContent.IndexOf("function New-CopilotIssue")
$functionEnd = $scriptContent.IndexOf("function ", $functionStart + 1)
if ($functionEnd -eq -1) {
    $functionEnd = $scriptContent.Length
}

$newCopilotIssueFunction = $scriptContent.Substring($functionStart, $functionEnd - $functionStart)

# Find the Test-IssueAssignmentStructure function
$functionStart = $scriptContent.IndexOf("function Test-IssueAssignmentStructure")
$functionEnd = $scriptContent.IndexOf("function ", $functionStart + 1)
if ($functionEnd -eq -1) {
    $functionEnd = $scriptContent.Length
}

$testIssueAssignmentFunction = $scriptContent.Substring($functionStart, $functionEnd - $functionStart)

# Execute the functions
Invoke-Expression $newCopilotIssueFunction
Invoke-Expression $testIssueAssignmentFunction

Write-Host "Functions loaded successfully!" -ForegroundColor Green

# Test the New-CopilotIssue function
Write-Host "Testing New-CopilotIssue function..." -ForegroundColor Yellow

$testTitle = "TEST: Copilot Assignment Workflow"
$testBody = @"
This is a test issue for Copilot assignment workflow validation.

@copilot Please help validate the two-step assignment process:

1. Issue creation with labels
2. Copilot assignment via gh issue edit

**Expected Behavior:**
- Issue should be created successfully
- Copilot should be assigned via gh issue edit command
- Assignment should be verified

**Auto-Close:** This is a test issue and will be closed automatically.
"@

$testLabels = @("automation", "copilot", "test")

Write-Host "Creating test issue..." -ForegroundColor Cyan
try {
    $result = New-CopilotIssue -Title $testTitle -Body $testBody -PreferredAssignee "markus-lassfolk" -Labels $testLabels
    
    Write-Host "Test Results:" -ForegroundColor Green
    Write-Host "  Success: $($result.Success)" -ForegroundColor $(if ($result.Success) {"Green"} else {"Red"})
    Write-Host "  Issue Number: $($result.IssueNumber)" -ForegroundColor Cyan
    Write-Host "  Assignee: $($result.Assignee)" -ForegroundColor Yellow
    Write-Host "  Verified: $($result.Verified)" -ForegroundColor $(if ($result.Verified) {"Green"} else {"Yellow"})
    Write-Host "  Copilot Mentioned: $($result.CopilotMentioned)" -ForegroundColor $(if ($result.CopilotMentioned) {"Green"} else {"Yellow"})
    
    if ($result.Success -and $result.IssueNumber) {
        Write-Host "Cleaning up test issue..." -ForegroundColor Yellow
        $closeResult = gh issue close $result.IssueNumber --comment "Test completed successfully. Closing test issue."
        Write-Host "Test issue closed." -ForegroundColor Green
    }
    
} catch {
    Write-Host "Test failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host "Copilot assignment test completed!" -ForegroundColor Cyan
