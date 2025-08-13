#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Process all files with validation issues using the optimized issue creation script
    
.DESCRIPTION
    This script processes the 14 files identified by validation that have issues.
    It calls the optimized issue creation script for each file individually to ensure
    all issues are addressed systematically.
    
.PARAMETER Production
    Enable production mode to create real issues (default: dry run)
    
.PARAMETER MaxIssuesPerRun
    Maximum issues to create per script execution (default: 5)
    
.PARAMETER PriorityFilter
    Filter by priority: All, Critical, Major, Minor (default: All)
    
.PARAMETER DebugMode
    Enable debug logging
    
.EXAMPLE
    .\process-validation-issues.ps1 -Production -MaxIssuesPerRun 10
    
.EXAMPLE
    .\process-validation-issues.ps1 -DebugMode -PriorityFilter Major
#>

param(
    [switch]$Production = $false,
    [int]$MaxIssuesPerRun = 5,
    [string]$PriorityFilter = "All",
    [switch]$DebugMode = $false
)

# List of files with issues from validation results
$FilesWithIssues = @(
    "./Starlink-RUTOS-Failover/generate_api_docs.sh",
    "./debug-merge-direct.sh", 
    "./debug-simple.sh",
    "./enhanced-maintenance-logic.sh",
    "./fix-markdown-issues.sh",
    "./scripts/comprehensive-validation.sh",
    "./scripts/fix-database-loop-rutos.sh",
    "./scripts/fix-database-spam-rutos.sh",
    "./scripts/format-markdown.sh",
    "./scripts/post-install-check-rutos.sh",
    "./scripts/system-maintenance-rutos.sh",
    "./scripts/update-cron-config-path-rutos.sh",
    "./scripts/validate-markdown.sh",
    "./test-validation-patterns.sh"
)

# Issue counts per file from validation
$IssueStats = @{
    "./Starlink-RUTOS-Failover/generate_api_docs.sh" = 7
    "./debug-merge-direct.sh" = 2
    "./debug-simple.sh" = 5
    "./enhanced-maintenance-logic.sh" = 2
    "./fix-markdown-issues.sh" = 4
    "./scripts/comprehensive-validation.sh" = 7
    "./scripts/fix-database-loop-rutos.sh" = 2
    "./scripts/fix-database-spam-rutos.sh" = 10
    "./scripts/format-markdown.sh" = 2
    "./scripts/post-install-check-rutos.sh" = 40
    "./scripts/system-maintenance-rutos.sh" = 14
    "./scripts/update-cron-config-path-rutos.sh" = 2
    "./scripts/validate-markdown.sh" = 2
    "./test-validation-patterns.sh" = 4
}

# Color functions
function Write-InfoMessage($Message) {
    Write-Host "[INFO] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Green
}

function Write-StepMessage($Message) {
    Write-Host "[STEP] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Blue
}

function Write-SuccessMessage($Message) {
    Write-Host "[SUCCESS] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Green
}

function Write-ErrorMessage($Message) {
    Write-Host "[ERROR] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Red
}

function Write-DebugMessage($Message) {
    if ($DebugMode) {
        Write-Host "[DEBUG] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Cyan
    }
}

# Main processing function
function Invoke-ValidationIssuesProcessing {
    Write-InfoMessage "🔧 Starting batch processing of validation issues"
    Write-InfoMessage "📁 Total files to process: $($FilesWithIssues.Count)"
    Write-InfoMessage "📊 Total issues across all files: $(($IssueStats.Values | Measure-Object -Sum).Sum)"
    
    if ($Production) {
        Write-Host "`n⚠️  PRODUCTION MODE ENABLED - Issues will be created in GitHub" -ForegroundColor Yellow
        Write-Host "Press Ctrl+C to cancel or wait 5 seconds to continue..." -ForegroundColor Yellow
        Start-Sleep 5
    } else {
        Write-InfoMessage "🧪 Running in DRY RUN mode - no issues will be created"
    }
    
    # Sort files by issue count (highest priority first)
    $SortedFiles = $FilesWithIssues | Sort-Object { $IssueStats[$_] } -Descending
    
    Write-InfoMessage "📋 Processing order (by issue count):"
    foreach ($file in $SortedFiles) {
        $issueCount = $IssueStats[$file]
        Write-Host "   • $file ($issueCount issues)" -ForegroundColor Cyan
    }
    
    $totalProcessed = 0
    $totalCreated = 0
    $totalSkipped = 0
    $errors = @()
    
    # Process each file individually
    foreach ($file in $SortedFiles) {
        $issueCount = $IssueStats[$file]
        
        Write-StepMessage "🔍 Processing: $file ($issueCount issues)"
        $totalProcessed++
        
        try {
            # Build command arguments
            $scriptArgs = @()
            if ($Production) { $scriptArgs += "-Production" }
            if ($DebugMode) { $scriptArgs += "-DebugMode" }
            $scriptArgs += "-MaxIssues", $MaxIssuesPerRun
            $scriptArgs += "-PriorityFilter", $PriorityFilter
            $scriptArgs += "-TargetFile", $file
            $scriptArgs += "-SortByPriority"
            
            Write-DebugMessage "Executing: .\create-copilot-issues-optimized.ps1 $($scriptArgs -join ' ')"
            
            # Execute the optimized script for this specific file
            & "$PSScriptRoot\create-copilot-issues-optimized.ps1" @scriptArgs | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMessage "✅ Successfully processed: $file"
                $totalCreated++
            } else {
                Write-ErrorMessage "❌ Failed to process: $file (Exit code: $LASTEXITCODE)"
                $errors += "Failed processing $file (exit code: $LASTEXITCODE)"
                $totalSkipped++
            }
            
        } catch {
            Write-ErrorMessage "❌ Exception processing $file`: $($_.Exception.Message)"
            $errors += "Exception processing ${file}: $($_.Exception.Message)"
            $totalSkipped++
        }
        
        # Small delay between files to avoid overwhelming GitHub API
        if ($Production -and $totalProcessed -lt $SortedFiles.Count) {
            Write-DebugMessage "⏳ Waiting 2 seconds before next file..."
            Start-Sleep 2
        }
    }
    
    # Final summary
    Write-Host "`n" + "="*80 -ForegroundColor Purple
    Write-Host "📊 BATCH PROCESSING SUMMARY" -ForegroundColor Purple
    Write-Host "="*80 -ForegroundColor Purple
    
    Write-InfoMessage "📁 Files Processed: $totalProcessed"
    Write-InfoMessage "✅ Successfully Created: $totalCreated"
    Write-InfoMessage "⏭️  Skipped/Failed: $totalSkipped"
    
    if ($errors.Count -gt 0) {
        Write-ErrorMessage "❌ Errors encountered:"
        foreach ($errorMessage in $errors) {
            Write-Host "   • $errorMessage" -ForegroundColor Red
        }
    } else {
        Write-SuccessMessage "🎉 No errors encountered during batch processing"
    }
    
    Write-SuccessMessage "🎉 Batch processing completed successfully!"
}

# Execute main function
Invoke-ValidationIssuesProcessing
