# Test script for Copilot assignment workflow
# This script tests the enhanced Create-RUTOS-PRs.ps1 Copilot assignment functionality

Write-Host "🧪 **COPILOT ASSIGNMENT TEST SUITE**" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

# Test 1: Check if GitHub CLI is authenticated and working
Write-Host "`n1️⃣ Testing GitHub CLI authentication..." -ForegroundColor Yellow
try {
    $user = gh api user | ConvertFrom-Json
    Write-Host "✅ GitHub CLI authenticated as: $($user.login)" -ForegroundColor Green
} catch {
    Write-Host "❌ GitHub CLI authentication failed!" -ForegroundColor Red
    Write-Host "   Run 'gh auth login' first" -ForegroundColor Yellow
    exit 1
}

# Test 2: Check repository access
Write-Host "`n2️⃣ Testing repository access..." -ForegroundColor Yellow
try {
    $repo = gh repo view --json nameWithOwner | ConvertFrom-Json
    Write-Host "✅ Repository access confirmed: $($repo.nameWithOwner)" -ForegroundColor Green
} catch {
    Write-Host "❌ Repository access failed!" -ForegroundColor Red
    Write-Host "   Make sure you're in a git repository with GitHub remote" -ForegroundColor Yellow
    exit 1
}

# Test 3: Test the enhanced script's assignment workflow
Write-Host "`n3️⃣ Testing Copilot assignment workflow..." -ForegroundColor Yellow
Write-Host "🔍 Running Create-RUTOS-PRs.ps1 with -TestCopilotAssignment flag..." -ForegroundColor Cyan

try {
    & "$PSScriptRoot\Create-RUTOS-PRs.ps1" -TestCopilotAssignment
    Write-Host "✅ Assignment workflow test completed" -ForegroundColor Green
} catch {
    Write-Host "❌ Assignment workflow test failed!" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Test 4: Verify the script can create dry run issues
Write-Host "`n4️⃣ Testing dry run functionality..." -ForegroundColor Yellow
Write-Host "🔍 Running Create-RUTOS-PRs.ps1 with -DryRun flag..." -ForegroundColor Cyan

try {
    & "$PSScriptRoot\Create-RUTOS-PRs.ps1" -DryRun -MaxIssues 1
    Write-Host "✅ Dry run test completed" -ForegroundColor Green
} catch {
    Write-Host "❌ Dry run test failed!" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "🎯 **TEST SUMMARY**" -ForegroundColor Green
Write-Host "✅ All tests completed - check results above" -ForegroundColor Green
Write-Host "💡 If all tests passed, you can run the full script safely" -ForegroundColor Cyan
Write-Host "🤖 The script will create issues with proper Copilot assignment" -ForegroundColor Yellow

Write-Host "`n📝 **NEXT STEPS:**" -ForegroundColor Yellow
Write-Host "1. Review test results above" -ForegroundColor White
Write-Host "2. If successful, run: ./automation/Create-RUTOS-PRs.ps1" -ForegroundColor White
Write-Host "3. Monitor created issues for Copilot assignment" -ForegroundColor White
Write-Host "4. Manually assign to Copilot in GitHub UI if needed" -ForegroundColor White
