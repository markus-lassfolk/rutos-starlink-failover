#!/usr/bin/env pwsh
# Test the updated parsing logic

# Import the parsing function (simplified version for testing)
function Parse-ValidationOutput {
    param(
        [string[]]$Output,
        [int]$ExitCode
    )
    
    function Write-DebugMessage {
        param([string]$Message)
        Write-Host "[DEBUG] $Message" -ForegroundColor Cyan
    }
    
    Write-DebugMessage "Parsing validation output..."
    
    $fileIssues = @{}
    
    # Parse detailed output (per-file)
    # First, join any wrapped lines back together
    $joinedOutput = @()
    $currentLine = ""
    
    foreach ($line in $Output) {
        $line = $line.Trim()
        
        # If line starts with [SEVERITY], it's a new issue line
        if ($line -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]") {
            # Save previous line if it exists
            if ($currentLine -ne "") {
                $joinedOutput += $currentLine
            }
            $currentLine = $line
        } else {
            # This might be a continuation of the previous line (PowerShell wrapping)
            if ($currentLine -ne "") {
                $currentLine += " " + $line
            } else {
                $joinedOutput += $line
            }
        }
    }
    
    # Don't forget the last line
    if ($currentLine -ne "") {
        $joinedOutput += $currentLine
    }
    
    Write-DebugMessage "Joined $($Output.Count) lines into $($joinedOutput.Count) lines"
    
    foreach ($line in $joinedOutput) {
        $line = $line.Trim()
        Write-DebugMessage "Processing line: $line"
        
        # Handle the specific format: [SEVERITY] filepath:line description [optional context]
        if ($line -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]\s+(.+?):(\d+)\s+(.+)$") {
            $severity = $Matches[1]
            $filepath = $Matches[2]
            $lineNumber = $Matches[3]
            $description = $Matches[4]
            
            # Clean up filepath (remove ./ prefix if present)
            $filepath = $filepath -replace "^\.\/", ""
            
            # Initialize file if not exists
            if (-not $fileIssues.ContainsKey($filepath)) {
                $fileIssues[$filepath] = @()
            }
            
            # Determine issue type and severity level
            $issueType = switch ($severity) {
                "CRITICAL" { "Critical" }
                "MAJOR" { "Major" }
                "MINOR" { "Minor" }
                "WARNING" { "Warning" }
                default { "Minor" }
            }
            
            $severityLevel = switch ($severity) {
                "CRITICAL" { "High" }
                "MAJOR" { "Medium" }
                "MINOR" { "Low" }
                "WARNING" { "Medium" }
                default { "Low" }
            }
            
            $issueInfo = @{
                Line = [int]$lineNumber
                Description = $description
                Type = $issueType
                Severity = $severityLevel
            }
            
            $fileIssues[$filepath] += $issueInfo
            Write-DebugMessage "Added $issueType issue for $filepath line ${lineNumber}: $description"
        }
    }
    
    Write-DebugMessage "Parsed issues for $($fileIssues.Count) files"
    
    return @{
        Success = $ExitCode -eq 0
        FileIssues = $fileIssues
        ExitCode = $ExitCode
        TotalFiles = $fileIssues.Count
        TotalIssues = ($fileIssues.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    }
}

# Test with sample output from the log file
Write-Host "🧪 Testing parsing logic..." -ForegroundColor Yellow

# Get some sample lines from the validation output
$sampleOutput = @(
    "[MAJOR] ./docs/TROUBLESHOOTING.md:55 MD031:/blanks-around-fences Fenced code blocks should be surrounded by",
    "blank lines [Context: `"```bash`"]",
    "[CRITICAL] ./Starlink-RUTOS-Failover/99-pushover_notify-rutos.sh:36 Uses 'local' keyword - not supported in",
    "busybox",
    "[MAJOR] ./docs/TROUBLESHOOTING.md:57 MD031:/blanks-around-fences Fenced code blocks should be surrounded by",
    "blank lines [Context: `"```]"
)

Write-Host "Sample input:" -ForegroundColor Green
$sampleOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

Write-Host "`nParsing..." -ForegroundColor Blue
$result = Parse-ValidationOutput -Output $sampleOutput -ExitCode 1

Write-Host "`nResults:" -ForegroundColor Green
Write-Host "  Success: $($result.Success)" -ForegroundColor Cyan
Write-Host "  Total Files: $($result.TotalFiles)" -ForegroundColor Cyan
Write-Host "  Total Issues: $($result.TotalIssues)" -ForegroundColor Cyan

Write-Host "`nFile Issues:" -ForegroundColor Yellow
foreach ($file in $result.FileIssues.Keys) {
    Write-Host "  📄 ${file}:" -ForegroundColor Cyan
    foreach ($issue in $result.FileIssues[$file]) {
        Write-Host "    Line $($issue.Line): [$($issue.Type)] $($issue.Description)" -ForegroundColor Gray
    }
}

Write-Host "`n🧪 Testing with actual validation output..." -ForegroundColor Yellow

# Test with actual output from the log file
$actualOutput = Get-Content "validation_output_20250717_214900.log" | Where-Object { $_ -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]" -or ($_ -match "^(blank lines|busybox|RUTOS compatibility)" -and $_ -notmatch "^\[") } | Select-Object -First 10

Write-Host "Actual input (first 10 relevant lines):" -ForegroundColor Green
$actualOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

Write-Host "`nParsing actual output..." -ForegroundColor Blue
$actualResult = Parse-ValidationOutput -Output $actualOutput -ExitCode 1

Write-Host "`nActual Results:" -ForegroundColor Green
Write-Host "  Success: $($actualResult.Success)" -ForegroundColor Cyan
Write-Host "  Total Files: $($actualResult.TotalFiles)" -ForegroundColor Cyan
Write-Host "  Total Issues: $($actualResult.TotalIssues)" -ForegroundColor Cyan

Write-Host "`nActual File Issues:" -ForegroundColor Yellow
foreach ($file in $actualResult.FileIssues.Keys) {
    Write-Host "  📄 ${file}:" -ForegroundColor Cyan
    foreach ($issue in $actualResult.FileIssues[$file]) {
        Write-Host "    Line $($issue.Line): [$($issue.Type)] $($issue.Description)" -ForegroundColor Gray
    }
}

Write-Host "`n✅ Testing completed!" -ForegroundColor Green
