param(
    [switch]$VerboseOutput = $false,
    [switch]$SkipValidation = $false,
    [switch]$AutoResolveConflicts = $false,
    [switch]$SkipWorkflowApproval = $false,
    [switch]$ForceValidation = $false,
    [switch]$MonitorOnly = $false,
    [switch]$TestMode = $false
)

# Enhanced status message function with color support
function Write-StatusMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# Define color constants
$RED = [ConsoleColor]::Red
$GREEN = [ConsoleColor]::Green
$YELLOW = [ConsoleColor]::Yellow
$BLUE = [ConsoleColor]::Blue
$CYAN = [ConsoleColor]::Cyan
$PURPLE = [ConsoleColor]::Magenta

# Get open Copilot PRs
function Get-CopilotPRs {
    Write-StatusMessage "?? Fetching open Copilot PRs..." -Color $BLUE
    
    try {
        $prs = gh pr list --state open --author "app/github-copilot" --json number,title,headRefName,author --limit 50
        
        if ($LASTEXITCODE -ne 0) {
            Write-StatusMessage "? Failed to fetch PR list" -Color $RED
            return @()
        }
        
        $prData = $prs | ConvertFrom-Json
        
        if ($prData.Count -eq 0) {
            Write-StatusMessage "??  No open Copilot PRs found" -Color $CYAN
            return @()
        }
        
        $copilotPRs = $prData | ForEach-Object {
            @{
                Number = $_.number
                Title = $_.title
                HeadRef = $_.headRefName
                Author = $_.author.login
            }
        }
        
        return $copilotPRs
        
    } catch {
        Write-StatusMessage "? Error fetching Copilot PRs: $($_.Exception.Message)" -Color $RED
        return @()
    }
}

# Get workflow runs for a specific PR
function Get-WorkflowRuns {
    param(
        [string]$PRNumber
    )
    
    Write-StatusMessage "?? Checking workflow runs for PR #$PRNumber..." -Color $BLUE
    
    try {
        $runs = gh run list --json status,conclusion,workflowName,headBranch --limit 20 | ConvertFrom-Json
        return $runs
    } catch {
        Write-StatusMessage "? Error fetching workflow runs: $($_.Exception.Message)" -Color $RED
        return @()
    }
}

# Approve workflow run if needed
function Approve-WorkflowRun {
    param(
        [string]$PRNumber,
        [string]$RunId
    )
    
    Write-StatusMessage "? Approving workflow run $RunId for PR #$PRNumber..." -Color $GREEN
    
    try {
        gh run approve $RunId
        return $true
    } catch {
        Write-StatusMessage "? Error approving workflow run: $($_.Exception.Message)" -Color $RED
        return $false
    }
}

# Enhanced validation issue display
function Show-ValidationIssues {
    param(
        [array]$ValidationResults,
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "`n?? Validation Summary for PR #$PRNumber" -Color $CYAN
    Write-StatusMessage "=" * 50 -Color $CYAN
    
    $totalFiles = $ValidationResults.Count
    $passedFiles = ($ValidationResults | Where-Object { $_.Passed -eq $true }).Count
    $failedFiles = $totalFiles - $passedFiles
    
    Write-StatusMessage "?? Total files checked: $totalFiles" -Color $BLUE
    Write-StatusMessage "? Passed: $passedFiles" -Color $GREEN
    Write-StatusMessage "? Failed: $failedFiles" -Color $RED
    
    if ($failedFiles -gt 0) {
        Write-StatusMessage "`n?? Issues found:" -Color $YELLOW
        
        foreach ($result in $ValidationResults) {
            if ($result.Passed -eq $false) {
                Write-StatusMessage "`n?? File: $($result.File)" -Color $BLUE
                
                # Show critical issues
                if ($result.CriticalDetails -and $result.CriticalDetails.Count -gt 0) {
                    Write-StatusMessage "  ?? Critical Issues ($($result.CriticalDetails.Count)):" -Color $RED
                    foreach ($critical in $result.CriticalDetails) {
                        Write-StatusMessage "    ? Line $($critical.LineNumber): $($critical.Issue)" -Color $RED
                        Write-StatusMessage "      Current: $($critical.CurrentCode)" -Color $YELLOW
                        Write-StatusMessage "      Fix: $($critical.Solution)" -Color $GREEN
                    }
                }
                
                # Show major issues
                if ($result.MajorDetails -and $result.MajorDetails.Count -gt 0) {
                    Write-StatusMessage "  ?? Major Issues ($($result.MajorDetails.Count)):" -Color $YELLOW
                    foreach ($major in $result.MajorDetails) {
                        Write-StatusMessage "    ? Line $($major.LineNumber): $($major.Issue)" -Color $YELLOW
                        Write-StatusMessage "      Current: $($major.CurrentCode)" -Color $CYAN
                        Write-StatusMessage "      Fix: $($major.Solution)" -Color $GREEN
                    }
                }
                
                # Show validation output if available
                if ($result.Output -and $result.Output.Trim() -ne "") {
                    Write-StatusMessage "  ?? Validation Output:" -Color $CYAN
                    $result.Output.Split("`n") | ForEach-Object {
                        if ($_.Trim() -ne "") {
                            Write-StatusMessage "    $($_.Trim())" -Color $GRAY
                        }
                    }
                }
            }
        }
    }
    
    Write-StatusMessage "`n" + ("=" * 50) -Color $CYAN
}

# Test PR validation with enhanced server-side approach
function Test-PRValidation {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "?? Starting enhanced validation for PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get list of changed files in the PR
        $changedFiles = gh pr view $PRNumber --json files --jq '.files[].path' 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-StatusMessage "? Failed to get changed files for PR #$PRNumber" -Color $RED
            return @{
                IsValid = $false
                Issues = @(@{
                    File = "Unknown"
                    Line = 0
                    Type = "Technical"
                    Issue = "Failed to get changed files"
                    Solution = "Check GitHub API access"
                })
                Message = "Technical error getting changed files"
            }
        }
        
        # Filter for shell script files
        $filePaths = $changedFiles | Where-Object { $_ -match '\.(sh|bash)$' }
        
        if ($filePaths.Count -eq 0) {
            Write-StatusMessage "??  No shell script files found in PR #$PRNumber" -Color $CYAN
            return @{
                IsValid = $true
                Issues = @()
                Message = "No shell script files to validate"
            }
        }
        
        Write-StatusMessage "?? Found $($filePaths.Count) shell script file(s) to validate" -Color $BLUE
        
        $issues = @()
        
        # Validate each file using server-side approach
        foreach ($file in $filePaths) {
            Write-StatusMessage "   ?? Validating: $file (server-side)" -Color $BLUE
            
            try {
                # Get file content from PR branch via GitHub API
                # First get the PR info to get the head SHA
                $prInfo = gh api repos/:owner/:repo/pulls/$PRNumber --jq '.head.sha' 2>&1
                $headSha = $null
                if ($LASTEXITCODE -eq 0 -and $prInfo) {
                    $headSha = $prInfo.Trim()
                }
                
                $fileContent = $null
                $decodedContent = $null
                
                # Method 1: Use --ref with head SHA (most reliable)
                if ($headSha) {
                    $fileContent = gh api repos/:owner/:repo/contents/$file --ref $headSha --jq '.content' 2>&1
                    if ($LASTEXITCODE -eq 0 -and $fileContent -and $fileContent -ne "null") {
                        $decodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($fileContent))
                    }
                }
                
                # Method 2: If Method 1 fails, try using branch name
                if (-not $decodedContent) {
                    $fileContent = gh api repos/:owner/:repo/contents/$file --ref $HeadRef --jq '.content' 2>&1
                    if ($LASTEXITCODE -eq 0 -and $fileContent -and $fileContent -ne "null") {
                        $decodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($fileContent))
                    }
                }
                
                # Method 3: If still failing, try getting the file content from the PR diff
                if (-not $decodedContent) {
                    $prFiles = gh api repos/:owner/:repo/pulls/$PRNumber/files --jq '.[] | select(.filename == "' + $file + '") | .patch' 2>&1
                    if ($LASTEXITCODE -eq 0 -and $prFiles) {
                        # This is a fallback - we'll indicate we couldn't get the full file
                        Write-StatusMessage "   ??  Could not fetch full file content, using patch data for basic validation" -Color $YELLOW
                        $decodedContent = $prFiles  # Use patch data as fallback
                    }
                }
                
                # If all methods fail, record technical issue
                if (-not $decodedContent) {
                    Write-StatusMessage "   ? Could not fetch file from PR branch - technical issue" -Color $RED
                    $issues += @{
                        File = $file
                        Line = 0
                        Type = "Technical"
                        Issue = "Could not fetch file from PR branch"
                        Solution = "Manual validation required - GitHub API access issue"
                    }
                    continue
                }
                
                # Validate the file content
                $fileIssues = Test-FileRUTOSCompatibility -FilePath $file -FileContent $decodedContent
                $issues += $fileIssues
                
            } catch {
                Write-StatusMessage "   ? Error validating file: $_" -Color $RED
                $issues += @{
                    File = $file
                    Line = 0
                    Type = "Technical"
                    Issue = "Validation error: $_"
                    Solution = "Manual validation required - script error"
                }
            }
        }
        
        # Check for technical issues vs validation issues
        $technicalIssues = $issues | Where-Object { $_.Type -eq "Technical" }
        $validationIssues = $issues | Where-Object { $_.Type -ne "Technical" }
        
        # Only post validation comments if there are actual RUTOS issues, not technical problems
        if ($technicalIssues.Count -gt 0) {
            Write-StatusMessage "??  Technical issues found - skipping validation comment to avoid unnecessary costs" -Color $YELLOW
            return @{
                IsValid = $false
                Issues = $technicalIssues
                Message = "Technical issues prevented validation - manual review needed"
            }
        }
        
        if ($validationIssues.Count -eq 0) {
            Write-StatusMessage "? All files pass RUTOS compatibility validation" -Color $GREEN
            return @{
                IsValid = $true
                Issues = @()
                Message = "All files pass RUTOS compatibility validation"
            }
        }
        
        # Format validation issues for comment
        $validationMessage = Format-ValidationResultsForPR -Issues $validationIssues
        
        return @{
            IsValid = $false
            Issues = $validationIssues
            Message = $validationMessage
        }
    } catch {
        Write-StatusMessage "? Validation failed: $($_.Exception.Message)" -Color $RED
        return @{
            IsValid = $false
            Issues = @(@{
                File = "Unknown"
                Line = 0
                Type = "Technical"
                Issue = "Validation script error: $($_.Exception.Message)"
                Solution = "Check script and GitHub API access"
            })
            Message = "Technical error during validation"
        }
    }
}

# Format validation results for PR comment
function Format-ValidationResultsForPR {
    param(
        [Array]$Issues
    )
    
    if ($Issues.Count -eq 0) {
        return "? All files pass RUTOS compatibility validation"
    }
    
    $result = @()
    $result += "## RUTOS Compatibility Validation Results"
    $result += ""
    
    # Group issues by file
    $fileGroups = $Issues | Group-Object -Property File
    
    foreach ($fileGroup in $fileGroups) {
        $fileName = $fileGroup.Name
        $fileIssues = $fileGroup.Group
        
        $result += "### File: $fileName"
        $result += ""
        
        # Group by severity
        $criticalIssues = $fileIssues | Where-Object { $_.Type -eq "Critical" }
        $majorIssues = $fileIssues | Where-Object { $_.Type -eq "Major" }
        
        if ($criticalIssues.Count -gt 0) {
            $result += "#### Critical Issues ($($criticalIssues.Count))"
            foreach ($issue in $criticalIssues) {
                $result += "- **Line $($issue.Line)**: $($issue.Issue)"
                $result += "  - **Solution**: $($issue.Solution)"
                $result += ""
            }
        }
        
        if ($majorIssues.Count -gt 0) {
            $result += "#### Major Issues ($($majorIssues.Count))"
            foreach ($issue in $majorIssues) {
                $result += "- **Line $($issue.Line)**: $($issue.Issue)"
                $result += "  - **Solution**: $($issue.Solution)"
                $result += ""
            }
        }
    }
    
    $result += "---"
    $result += "*Validation performed by RUTOS Compatibility Checker*"
    
    return $result -join "`n"
}

# Test file compatibility function
function Test-FileRUTOSCompatibility {
    param(
        [string]$FilePath,
        [string]$FileContent
    )
    
    $issues = @()
    
    # Skip non-shell files
    if ($FilePath -notmatch '\.(sh|bash)$') {
        return $issues
    }
    
    # Split content into lines for line number analysis
    $lines = $FileContent -split "`r?`n"
    
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNumber = $i + 1
        $line = $lines[$i]
        
        # Check for bash shebang (CRITICAL)
        if ($line -match '#!/bin/bash') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Critical"
                Issue = "Uses bash shebang instead of POSIX sh"
                Solution = "Change to: #!/bin/sh"
            }
        }
        
        # Check for bash-specific [[ ]] syntax (CRITICAL)
        if ($line -match '\[\[.*\]\]') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Critical"
                Issue = "Uses bash-specific [[ ]] syntax"
                Solution = "Replace [[ ]] with [ ] for POSIX compatibility"
            }
        }
        
        # Check for local keyword (MAJOR)
        if ($line -match '\blocal\s+\w+') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Uses 'local' keyword (busybox incompatible)"
                Solution = "Remove 'local' keyword. In busybox, all variables are global"
            }
        }
        
        # Check for echo -e (MAJOR)
        if ($line -match 'echo\s+-e') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Uses 'echo -e' instead of printf"
                Solution = "Replace with printf for better portability"
            }
        }
        
        # Check for array usage (CRITICAL)
        if ($line -match '\w+\s*=\s*\(' -or $line -match '\$\{[^}]*\[\@\*\]\}') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Critical"
                Issue = "Uses bash arrays (not supported in busybox)"
                Solution = "Convert to space-separated strings or multiple variables"
            }
        }
        
        # Check for function() syntax (MAJOR)
        if ($line -match '^\s*function\s+\w+\s*\(\s*\)') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Uses function() syntax instead of POSIX format"
                Solution = "Change to POSIX format: funcName() {"
            }
        }
        
        # Check for source command (MAJOR)
        if ($line -match '\bsource\s+') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Uses 'source' command instead of '.'"
                Solution = "Replace 'source' with '.' (dot command)"
            }
        }
    }
    
    return $issues
}

# Check if PR is ready for validation
function Test-PRReady {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "?? Checking if PR #$PRNumber is ready for validation..." -Color $BLUE
    
    # Check if PR is in draft state
    $prInfo = gh api repos/:owner/:repo/pulls/$PRNumber --jq '.draft' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "? Failed to get PR information" -Color $RED
        return $false
    }
    
    $isDraft = $prInfo.Trim() -eq "true"
    if ($isDraft) {
        Write-StatusMessage "??  PR #$PRNumber is in draft state - skipping validation" -Color $YELLOW
        return $false
    }
    
    # Check if there are any recent commits
    $commits = gh api repos/:owner/:repo/pulls/$PRNumber/commits --jq '.[].sha' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "? Failed to get PR commits" -Color $RED
        return $false
    }
    
    $commitCount = ($commits | Measure-Object).Count
    if ($commitCount -eq 0) {
        Write-StatusMessage "??  PR #$PRNumber has no commits - skipping validation" -Color $YELLOW
        return $false
    }
    
    Write-StatusMessage "? PR #$PRNumber is ready for validation ($commitCount commits)" -Color $GREEN
    return $true
}

# Main processing function
function Start-CopilotPRs {
    Write-StatusMessage "?? Starting Copilot PR monitoring..." -Color $GREEN
    
    # Get open PRs from Copilot
    $openPRs = Get-CopilotPRs
    
    if ($openPRs.Count -eq 0) {
        Write-StatusMessage "??  No open Copilot PRs found" -Color $CYAN
        return
    }
    
    Write-StatusMessage "?? Found $($openPRs.Count) open Copilot PR(s)" -Color $BLUE
    
    foreach ($pr in $openPRs) {
        Write-StatusMessage "`n?? Processing PR #$($pr.Number): $($pr.Title)" -Color $PURPLE
        
        # Check if PR is ready for validation
        if (-not (Test-PRReady -PRNumber $pr.Number -HeadRef $pr.HeadRef)) {
            continue
        }
        
        # Validate the PR
        $validationResult = Test-PRValidation -PRNumber $pr.Number -HeadRef $pr.HeadRef
        
        # Only post comments if there are actual validation issues (not technical problems)
        if ($validationResult.IsValid) {
            Write-StatusMessage "? PR #$($pr.Number) passed validation" -Color $GREEN
        } elseif ($validationResult.Issues.Count -gt 0 -and $validationResult.Issues[0].Type -eq "Technical") {
            Write-StatusMessage "??  PR #$($pr.Number) has technical issues - skipping comment to save costs" -Color $YELLOW
        } else {
            Write-StatusMessage "? PR #$($pr.Number) has validation issues - posting comment" -Color $RED
            
            # Post validation comment
            $comment = $validationResult.Message
            gh api repos/:owner/:repo/issues/$($pr.Number)/comments -f body="$comment" 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "? Posted validation comment to PR #$($pr.Number)" -Color $GREEN
            } else {
                Write-StatusMessage "? Failed to post comment to PR #$($pr.Number)" -Color $RED
            }
        }
    }
    
    Write-StatusMessage "`n?? Copilot PR monitoring completed!" -Color $GREEN
}

# Main execution
try {
    # Validate we're in the correct directory
    if (-not (Test-Path ".git")) {
        Write-StatusMessage "? This script must be run from the repository root" -Color $RED
        exit 1
    }
    
    # Check GitHub CLI is available
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-StatusMessage "? GitHub CLI (gh) is not installed or not in PATH" -Color $RED
        exit 1
    }
    
    # Check authentication
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "? GitHub CLI is not authenticated. Run 'gh auth login' first." -Color $RED
        exit 1
    }
    
    # Run the main processing
    Start-CopilotPRs
    
} catch {
    Write-StatusMessage "? Script execution failed: $($_.Exception.Message)" -Color $RED
    exit 1
}
