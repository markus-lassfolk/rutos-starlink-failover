# RUTOS Issue Automation Script for GitHub Copilot
# Run in PowerShell (Windows) with GH CLI authenticated

Write-Host "🔍 Starting RUTOS Issue automation script for GitHub Copilot..." -ForegroundColor Cyan
Write-Host "📁 Working directory: $(Get-Location)" -ForegroundColor Gray

# Step 1: Run validation in WSL and capture output
Write-Host "🔧 Running pre-commit validation in WSL..." -ForegroundColor Yellow
$validationOutput = wsl ./scripts/pre-commit-validation.sh --all 2>&1
Write-Host "✅ Validation complete. Output lines: $($validationOutput.Count)" -ForegroundColor Green

# Step 2: Parse output for files with errors (assumes lines like: "[MAJOR] ./scripts/install.sh: ...")
Write-Host "🔍 Parsing validation output for MAJOR/CRITICAL errors..." -ForegroundColor Yellow
$filesWithErrors = $validationOutput | Select-String -Pattern "\[MAJOR\] |\[CRITICAL\] " | ForEach-Object {
    # Extract filename between "] " and ":"
    if ($_ -match '\[(?:MAJOR|CRITICAL)\] (.*?):') {
        $matches[1].Trim()
    }
} | Where-Object { $_ -ne $null } | Select-Object -Unique

Write-Host "📊 Found $($filesWithErrors.Count) files with errors:" -ForegroundColor Cyan
$filesWithErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

# Step 3: Prioritize shell scripts (.sh files) for RUTOS compatibility
Write-Host "🎯 Prioritizing shell scripts for RUTOS compatibility..." -ForegroundColor Magenta
$shellScripts = $filesWithErrors | Where-Object { $_ -match '\.sh$' }
$otherFiles = $filesWithErrors | Where-Object { $_ -notmatch '\.sh$' }

# Take first 5 shell scripts, then other files if needed
$targetFiles = @()
if ($shellScripts.Count -gt 0) {
    $targetFiles += $shellScripts | Select-Object -First 5
    Write-Host "🔧 Selected shell scripts: $($targetFiles -join ', ')" -ForegroundColor Green
} else {
    $targetFiles += $otherFiles | Select-Object -First 5
    Write-Host "📄 No shell scripts found, selected other files: $($targetFiles -join ', ')" -ForegroundColor Yellow
}

Write-Host "🎯 Processing $($targetFiles.Count) files for RUTOS compatibility" -ForegroundColor Magenta

foreach ($file in $targetFiles) {
    Write-Host "`n🔄 Processing file: $file" -ForegroundColor Yellow
    
    # Get specific validation issues for this file
    Write-Host "🔍 Running validation to get specific issues..." -ForegroundColor Cyan
    $fileValidation = wsl ./scripts/pre-commit-validation.sh $file 2>&1
    $fileValidationPassed = $LASTEXITCODE -eq 0
    
    if ($fileValidationPassed) {
        Write-Host "✅ File already passes validation - skipping" -ForegroundColor Green
        continue
    }
    
    # Extract specific issues from validation output
    $specificIssues = $fileValidation | Select-String -Pattern "\[MAJOR\]|\[CRITICAL\]" | ForEach-Object { $_.Line.Trim() }
    $issueCount = $specificIssues.Count
    
    Write-Host "📊 Found $issueCount specific issues in $file" -ForegroundColor Yellow
    $specificIssues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

    # Create GitHub Issue with Copilot instructions
    $issueTitle = "🤖 RUTOS Compatibility Fix Required: $file"
    $issueBody = @"
@copilot Please fix the RUTOS/busybox compatibility issues in ``$file``.

## 🎯 **Autonomous Fix Instructions**

### **Context**
This is a shell script that must run on RUTX50 routers with RUTOS (busybox shell environment). The script needs to be POSIX sh compatible, NOT bash.

### **Specific Issues Found**
$($specificIssues -join "`n")

### **Requirements**
1. **Follow Project Guidelines**: Review ``.github/copilot-instructions.md`` for RUTOS compatibility requirements
2. **POSIX Shell Compliance**: Use busybox sh syntax only (no bash-specific features)
3. **Fix All Issues**: Address every MAJOR and CRITICAL issue found by validation
4. **Maintain Functionality**: Preserve the original script's purpose and behavior

### **Common RUTOS Compatibility Fixes Needed**
- ``SC2164``: Add ``|| exit`` to cd commands: ``cd /path || exit``
- ``SC2002``: Remove useless cat: ``grep pattern file`` instead of ``cat file | grep pattern``
- ``SC2034``: Add ``# shellcheck disable=SC2034`` for intentionally unused variables
- ``SC2059``: Fix printf format strings - use ``%s`` placeholders for variables
- ``SC3043``: Replace ``local`` keyword (busybox doesn't support it)
- Remove bash-specific syntax like ``[[]]``, arrays, ``function()`` syntax

### **Validation Workflow** 
Please iterate and test your changes up to 3 times:

``````bash
# Run validation for this specific file
wsl ./scripts/pre-commit-validation.sh $file

# If issues remain, fix them and run again
# Repeat until validation passes (max 3 attempts)
``````

### **GitHub Actions Workflow**
✅ **Good News**: The workflow has been updated to only check changed files in PRs, not all repository files. This means your PR will only be validated against the file you're fixing, avoiding conflicts with other unfixed files.

### **Success Criteria**
- All ShellCheck issues resolved
- RUTOS busybox compatibility confirmed
- Pre-commit validation passes: ``wsl ./scripts/pre-commit-validation.sh $file``
- No MAJOR or CRITICAL issues remain
- GitHub Actions workflow passes (only validates your changed file)

### **Final Step**
Once all validations pass, add a comment: **"✅ RUTOS compatibility validation passed - Ready for review"**

---
**Priority**: High - RUTOS hardware compatibility required  
**Auto-generated**: PowerShell automation script  
**Target Environment**: RUTX50 router with RUTOS RUT5_R_00.07.09.7 (armv7l busybox)  
**Workflow**: Only changed files are validated in PRs
"@
    # Create GitHub Issue with Copilot AI
    Write-Host "🤖 Creating GitHub Issue for Copilot AI to fix..." -ForegroundColor Magenta
    $issueResult = gh issue create --title $issueTitle --body $issueBody 2>&1
    Write-Host "GitHub Issue output: $issueResult" -ForegroundColor DarkGray
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Issue created successfully for $file" -ForegroundColor Green
        $issueUrl = ($issueResult | Select-String -Pattern "https://github.com/.*" | ForEach-Object { $_.Line.Trim() })
        if ($issueUrl) {
            Write-Host "🔗 Issue URL: $issueUrl" -ForegroundColor Blue
        }
        Write-Host "🤖 Copilot AI has been assigned to autonomously fix the issues" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Issue creation failed for $file" -ForegroundColor Red
        Write-Host "Error details: $issueResult" -ForegroundColor Red
    }
}

Write-Host "`n🎉 Script completed!" -ForegroundColor Green
Write-Host "✅ RUTOS compatibility PR automation finished" -ForegroundColor Cyan
Write-Host "📊 Total files with errors: $($filesWithErrors.Count)" -ForegroundColor Gray
Write-Host "🎯 Shell scripts prioritized for RUTOS hardware compatibility" -ForegroundColor Gray
Write-Host "� Each PR includes detailed fix instructions and validation workflow" -ForegroundColor Gray
Write-Host "`n🔗 Check your PRs: https://github.com/markus-lassfolk/rutos-starlink-failover/pulls" -ForegroundColor Blue
Write-Host "📖 Remember: Follow copilot-instructions.md for RUTOS compatibility guidelines" -ForegroundColor Yellow
