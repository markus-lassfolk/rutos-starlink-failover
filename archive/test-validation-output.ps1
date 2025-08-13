#!/usr/bin/env pwsh
# Temporary script to test validation output format

param(
    [string]$TestFile = "docs/TROUBLESHOOTING.md"
)

$ErrorActionPreference = "Continue"

Write-Host "🔍 Testing validation output format..." -ForegroundColor Yellow
Write-Host "📄 Test file: $TestFile" -ForegroundColor Cyan

# Create log file with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "validation_output_$timestamp.log"

Write-Host "📝 Log file: $logFile" -ForegroundColor Cyan

# Test 1: Run validation script with summary output (no file specified)
Write-Host "`n=== TEST 1: Summary Output (No file specified) ===" -ForegroundColor Green
try {
    Write-Host "Command: wsl bash -c 'cd /mnt/c/GitHub/rutos-starlink-failover && ./scripts/pre-commit-validation.sh'" -ForegroundColor Gray
    
    $summaryOutput = wsl bash -c 'cd /mnt/c/GitHub/rutos-starlink-failover && ./scripts/pre-commit-validation.sh' 2>&1
    $summaryExitCode = $LASTEXITCODE
    
    Write-Host "Exit Code: $summaryExitCode" -ForegroundColor $(if ($summaryExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "Output Lines: $($summaryOutput.Count)" -ForegroundColor Cyan
    
    # Write to log file
    "=== SUMMARY OUTPUT ===" | Out-File -FilePath $logFile -Encoding UTF8
    "Exit Code: $summaryExitCode" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Output Lines: $($summaryOutput.Count)" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    $summaryOutput | Out-File -FilePath $logFile -Append -Encoding UTF8
    "" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    # Show first few lines
    Write-Host "First 10 lines of summary output:" -ForegroundColor Yellow
    $summaryOutput | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    
    if ($summaryOutput.Count -gt 10) {
        Write-Host "  ... ($($summaryOutput.Count - 10) more lines)" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "❌ Error running summary validation: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Run validation script with specific file
Write-Host "`n=== TEST 2: File-specific Output ===" -ForegroundColor Green
try {
    Write-Host "Command: wsl bash -c 'cd /mnt/c/GitHub/rutos-starlink-failover && ./scripts/pre-commit-validation.sh $TestFile'" -ForegroundColor Gray
    
    $fileOutput = wsl bash -c "cd /mnt/c/GitHub/rutos-starlink-failover && ./scripts/pre-commit-validation.sh $TestFile" 2>&1
    $fileExitCode = $LASTEXITCODE
    
    Write-Host "Exit Code: $fileExitCode" -ForegroundColor $(if ($fileExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "Output Lines: $($fileOutput.Count)" -ForegroundColor Cyan
    
    # Write to log file
    "=== FILE-SPECIFIC OUTPUT ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Test File: $TestFile" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Exit Code: $fileExitCode" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Output Lines: $($fileOutput.Count)" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    $fileOutput | Out-File -FilePath $logFile -Append -Encoding UTF8
    "" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    # Show first few lines
    Write-Host "First 10 lines of file-specific output:" -ForegroundColor Yellow
    $fileOutput | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    
    if ($fileOutput.Count -gt 10) {
        Write-Host "  ... ($($fileOutput.Count - 10) more lines)" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "❌ Error running file-specific validation: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Run validation script with debug mode
Write-Host "`n=== TEST 3: Debug Mode Output ===" -ForegroundColor Green
try {
    Write-Host "Command: wsl bash -c 'cd /mnt/c/GitHub/rutos-starlink-failover && DEBUG=1 ./scripts/pre-commit-validation.sh $TestFile'" -ForegroundColor Gray
    
    $debugOutput = wsl bash -c "cd /mnt/c/GitHub/rutos-starlink-failover && DEBUG=1 ./scripts/pre-commit-validation.sh $TestFile" 2>&1
    $debugExitCode = $LASTEXITCODE
    
    Write-Host "Exit Code: $debugExitCode" -ForegroundColor $(if ($debugExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "Output Lines: $($debugOutput.Count)" -ForegroundColor Cyan
    
    # Write to log file
    "=== DEBUG MODE OUTPUT ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Test File: $TestFile" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Exit Code: $debugExitCode" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Output Lines: $($debugOutput.Count)" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    $debugOutput | Out-File -FilePath $logFile -Append -Encoding UTF8
    "" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    # Show first few lines
    Write-Host "First 10 lines of debug output:" -ForegroundColor Yellow
    $debugOutput | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    
    if ($debugOutput.Count -gt 10) {
        Write-Host "  ... ($($debugOutput.Count - 10) more lines)" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "❌ Error running debug validation: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Look for lines that match the pattern we expect
Write-Host "`n=== TEST 4: Pattern Analysis ===" -ForegroundColor Green
try {
    Write-Host "Analyzing output for pattern: ^\[(CRITICAL|MAJOR|MINOR|WARNING)\]" -ForegroundColor Yellow
    
    "=== PATTERN ANALYSIS ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "Pattern: ^\[(CRITICAL|MAJOR|MINOR|WARNING)\]" | Out-File -FilePath $logFile -Append -Encoding UTF8
    "" | Out-File -FilePath $logFile -Append -Encoding UTF8
    
    $allOutputs = @()
    $allOutputs += $summaryOutput
    $allOutputs += $fileOutput
    $allOutputs += $debugOutput
    
    $matchingLines = $allOutputs | Where-Object { $_ -match "^\[(CRITICAL|MAJOR|MINOR|WARNING)\]" }
    
    if ($matchingLines) {
        Write-Host "Found $($matchingLines.Count) lines matching the pattern:" -ForegroundColor Green
        "Found $($matchingLines.Count) lines matching the pattern:" | Out-File -FilePath $logFile -Append -Encoding UTF8
        
        $matchingLines | Select-Object -First 10 | ForEach-Object { 
            Write-Host "  $_" -ForegroundColor Cyan
            $_ | Out-File -FilePath $logFile -Append -Encoding UTF8
        }
        
        if ($matchingLines.Count -gt 10) {
            Write-Host "  ... ($($matchingLines.Count - 10) more lines)" -ForegroundColor Gray
            "... ($($matchingLines.Count - 10) more lines)" | Out-File -FilePath $logFile -Append -Encoding UTF8
        }
    } else {
        Write-Host "❌ No lines found matching the expected pattern" -ForegroundColor Red
        "❌ No lines found matching the expected pattern" | Out-File -FilePath $logFile -Append -Encoding UTF8
    }
    
} catch {
    Write-Host "❌ Error in pattern analysis: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Check if validation script exists and is executable
Write-Host "`n=== TEST 5: Validation Script Check ===" -ForegroundColor Green
try {
    $scriptPath = "scripts/pre-commit-validation.sh"
    
    if (Test-Path $scriptPath) {
        Write-Host "✅ Validation script exists: $scriptPath" -ForegroundColor Green
        
        # Check if it's executable in WSL
        $isExecutable = wsl bash -c "cd /mnt/c/GitHub/rutos-starlink-failover && test -x ./scripts/pre-commit-validation.sh && echo 'executable' || echo 'not executable'"
        Write-Host "Script executable status: $isExecutable" -ForegroundColor $(if ($isExecutable -eq "executable") { "Green" } else { "Red" })
        
        # Get script info
        $scriptInfo = Get-Item $scriptPath
        Write-Host "Script size: $($scriptInfo.Length) bytes" -ForegroundColor Cyan
        Write-Host "Script modified: $($scriptInfo.LastWriteTime)" -ForegroundColor Cyan
        
    } else {
        Write-Host "❌ Validation script not found: $scriptPath" -ForegroundColor Red
    }
    
} catch {
    Write-Host "❌ Error checking validation script: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n✅ Testing completed! Check the log file for detailed output:" -ForegroundColor Green
Write-Host "   📄 Log file: $logFile" -ForegroundColor Cyan
Write-Host "   📝 To view: Get-Content $logFile" -ForegroundColor Gray

# Also display the log file path at the end
Write-Host "`n💡 Quick commands:" -ForegroundColor Yellow
Write-Host "   View log: Get-Content $logFile" -ForegroundColor Gray
Write-Host "   Filter issues: Get-Content $logFile | Select-String '\[MAJOR\]|\[CRITICAL\]|\[MINOR\]|\[WARNING\]'" -ForegroundColor Gray
Write-Host "   Open in editor: code $logFile" -ForegroundColor Gray
