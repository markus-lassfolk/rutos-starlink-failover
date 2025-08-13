#!/usr/bin/env pwsh

# Test script to check duplicate detection logic
param([string]$FilePath = "docs/BRANCH_TESTING.md")

Write-Host "Testing duplicate detection for: $FilePath" -ForegroundColor Cyan

# Test current open issues search
Write-Host "`n=== TESTING OPEN ISSUES ===" -ForegroundColor Yellow
$openResult = & gh issue list --search "$FilePath" --state "open" --json "number,title,state,updatedAt" 2>$null

if ($LASTEXITCODE -eq 0 -and $openResult -and $openResult.Trim()) {
    Write-Host "Raw GitHub CLI result:" -ForegroundColor Gray
    Write-Host $openResult -ForegroundColor White
    
    try {
        $openIssues = $openResult | ConvertFrom-Json
        Write-Host "`nParsed issues:" -ForegroundColor Gray
        foreach ($issue in $openIssues) {
            Write-Host "  Issue #$($issue.number): $($issue.title)" -ForegroundColor White
        }
        
        Write-Host "`nTesting regex match logic:" -ForegroundColor Gray
        $existingOpenIssue = $openIssues | Where-Object { $_.title -match [regex]::Escape($FilePath) }
        
        if ($existingOpenIssue) {
            Write-Host "✅ MATCH FOUND: Issue #$($existingOpenIssue.number)" -ForegroundColor Green
            Write-Host "   Title: $($existingOpenIssue.title)" -ForegroundColor Green
        } else {
            Write-Host "❌ NO MATCH FOUND" -ForegroundColor Red
            Write-Host "   Escaped search pattern: $([regex]::Escape($FilePath))" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ JSON parsing failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "❌ No results from GitHub CLI" -ForegroundColor Red
    Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor Red
}

# Test recently closed issues
Write-Host "`n=== TESTING RECENTLY CLOSED ISSUES ===" -ForegroundColor Yellow
$cutoffTime = (Get-Date).AddHours(-8).ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Host "Looking for issues closed after: $cutoffTime" -ForegroundColor Gray

$closedResult = & gh issue list --search "$FilePath" --state "closed" --json "number,title,state,closedAt" 2>$null

if ($LASTEXITCODE -eq 0 -and $closedResult -and $closedResult.Trim()) {
    Write-Host "Raw GitHub CLI result:" -ForegroundColor Gray
    Write-Host $closedResult -ForegroundColor White
    
    try {
        $closedIssues = $closedResult | ConvertFrom-Json
        Write-Host "`nParsed closed issues:" -ForegroundColor Gray
        foreach ($issue in $closedIssues) {
            Write-Host "  Issue #$($issue.number): $($issue.title) (closed: $($issue.closedAt))" -ForegroundColor White
        }
        
        Write-Host "`nTesting recent closure logic:" -ForegroundColor Gray
        $recentlyClosedIssue = $closedIssues | Where-Object { 
            $_.title -match [regex]::Escape($FilePath) -and
            $_.closedAt -and
            [DateTime]::Parse($_.closedAt) -gt [DateTime]::Parse($cutoffTime)
        }
        
        if ($recentlyClosedIssue) {
            $timeSinceClosed = [DateTime]::Now - [DateTime]::Parse($recentlyClosedIssue.closedAt)
            $hoursAgo = [Math]::Round($timeSinceClosed.TotalHours, 1)
            Write-Host "✅ RECENT CLOSURE FOUND: Issue #$($recentlyClosedIssue.number)" -ForegroundColor Green
            Write-Host "   Closed $hoursAgo hours ago" -ForegroundColor Green
        } else {
            Write-Host "✅ NO RECENT CLOSURES (this is good)" -ForegroundColor Green
        }
    } catch {
        Write-Host "❌ JSON parsing failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "ℹ️ No closed issues found (this is normal)" -ForegroundColor Cyan
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Magenta
Write-Host "The script should detect existing open issues and prevent duplicates."
Write-Host "If you see 'MATCH FOUND' above, the duplicate detection should work."
Write-Host "If you see 'NO MATCH FOUND', there's a bug in the matching logic."
