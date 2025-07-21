#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Simple array-based processing of files with validation issues
    
.DESCRIPTION
    Alternative approach: Process files using the existing script's capabilities
    with direct file targeting and batch processing.
    
.EXAMPLE
    # Process all 14 files with issues in production mode
    .\process-files-array.ps1 -Production
    
.EXAMPLE
    # Dry run with debug output
    .\process-files-array.ps1 -DebugMode
#>

param(
    [switch]$Production = $false,
    [switch]$DebugMode = $false
)

# Array of files with validation issues (from pre-commit validation results)
$ValidationIssueFiles = @(
    "Starlink-RUTOS-Failover/generate_api_docs.sh",
    "debug-merge-direct.sh", 
    "debug-simple.sh",
    "enhanced-maintenance-logic.sh",
    "fix-markdown-issues.sh",
    "scripts/comprehensive-validation.sh",
    "scripts/fix-database-loop-rutos.sh",
    "scripts/fix-database-spam-rutos.sh",
    "scripts/format-markdown.sh",
    "scripts/post-install-check-rutos.sh",
    "scripts/system-maintenance-rutos.sh",
    "scripts/update-cron-config-path-rutos.sh",
    "scripts/validate-markdown.sh",
    "test-validation-patterns.sh"
)

Write-Host "🔧 Processing $($ValidationIssueFiles.Count) files with validation issues" -ForegroundColor Blue

# Option 1: Single command with high MaxIssues to process all files at once
Write-Host "`n📋 OPTION 1: Single execution with high MaxIssues limit" -ForegroundColor Yellow
$singleCommandArgs = @()
if ($Production) { $singleCommandArgs += "-Production" }
if ($DebugMode) { $singleCommandArgs += "-DebugMode" }
$singleCommandArgs += "-MaxIssues", 50  # High enough to cover all 14 files
$singleCommandArgs += "-PriorityFilter", "All"
$singleCommandArgs += "-SortByPriority"

Write-Host "Command: .\create-copilot-issues-optimized.ps1 $($singleCommandArgs -join ' ')" -ForegroundColor Cyan

# Option 2: Individual file processing (safer, more controlled)
Write-Host "`n📋 OPTION 2: Individual file processing" -ForegroundColor Yellow
foreach ($file in $ValidationIssueFiles) {
    $individualArgs = @()
    if ($Production) { $individualArgs += "-Production" }
    if ($DebugMode) { $individualArgs += "-DebugMode" }
    $individualArgs += "-MaxIssues", 1
    $individualArgs += "-TargetFile", $file
    $individualArgs += "-PriorityFilter", "All"
    
    Write-Host "   .\create-copilot-issues-optimized.ps1 $($individualArgs -join ' ')" -ForegroundColor Gray
}

# Option 3: PowerShell foreach execution
Write-Host "`n📋 OPTION 3: Execute individual processing now" -ForegroundColor Yellow

if ($Production) {
    Write-Host "⚠️  PRODUCTION MODE - Will create real GitHub issues!" -ForegroundColor Red
    Write-Host "Press Ctrl+C to cancel or any key to continue..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

$processed = 0
$succeeded = 0
$failed = 0

foreach ($file in $ValidationIssueFiles) {
    $processed++
    Write-Host "`n[$processed/$($ValidationIssueFiles.Count)] Processing: $file" -ForegroundColor Blue
    
    try {
        $scriptArgs = @()
        if ($DebugMode) { $scriptArgs += "-DebugMode" }
        if ($Production) { $scriptArgs += "-Production" }
        $scriptArgs += "-MaxIssues"
        $scriptArgs += 1
        $scriptArgs += "-TargetFile"
        $scriptArgs += $file
        $scriptArgs += "-PriorityFilter"
        $scriptArgs += "All"
        
        # Execute the script
        $scriptPath = Join-Path $PSScriptRoot "create-copilot-issues-optimized.ps1"
        & $scriptPath @scriptArgs
        
        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            Write-Host "✅ Success: $file" -ForegroundColor Green
            $succeeded++
        } else {
            Write-Host "❌ Failed: $file (exit code: $LASTEXITCODE)" -ForegroundColor Red
            $failed++
        }
        
    } catch {
        Write-Host "❌ Exception: $file - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
    
    # Rate limiting for production mode
    if ($Production -and $processed -lt $ValidationIssueFiles.Count) {
        Write-Host "⏳ Waiting 3 seconds..." -ForegroundColor Gray
        Start-Sleep 3
    }
}

# Summary
Write-Host "`n" + "="*60 -ForegroundColor Magenta
Write-Host "📊 PROCESSING SUMMARY" -ForegroundColor Magenta
Write-Host "="*60 -ForegroundColor Magenta
Write-Host "Total Files: $($ValidationIssueFiles.Count)" -ForegroundColor White
Write-Host "Processed: $processed" -ForegroundColor Blue
Write-Host "Succeeded: $succeeded" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red

if ($failed -eq 0) {
    Write-Host "`n🎉 All files processed successfully!" -ForegroundColor Green
} else {
    Write-Host "`n⚠️  Some files had issues. Check the output above." -ForegroundColor Yellow
}
