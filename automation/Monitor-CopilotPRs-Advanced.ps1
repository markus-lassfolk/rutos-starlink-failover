param(
    [switch]$VerboseOutput = $false,
    [switch]$SkipValidation = $false,
    [switch]$AutoResolveConflicts = $false,
    [switch]$SkipWorkflowApproval = $false,
    [switch]$ForceValidation = $false,
    [switch]$MonitorOnly = $false,
    [switch]$TestMode = $false,
    [switch]$DebugMode = $false
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
$GRAY = [ConsoleColor]::Gray

# Enhanced Copilot PR detection with multiple strategies
function Get-CopilotPRs {
    Write-StatusMessage "🔍 Fetching open Copilot PRs with enhanced detection..." -Color $BLUE
    
    try {
        # Get all open PRs with comprehensive data
        $prs = gh pr list --state open --json number,title,headRefName,author,labels,createdAt,updatedAt --limit 100
        
        if ($LASTEXITCODE -ne 0) {
            Write-StatusMessage "❌ Failed to fetch PR list" -Color $RED
            return @()
        }
        
        $prData = $prs | ConvertFrom-Json
        
        # Advanced Copilot PR detection with multiple criteria
        $copilotPRs = $prData | Where-Object { 
            # Check author patterns
            ($_.author.login -match "copilot" -or 
             $_.author.login -eq "app/github-copilot" -or 
             $_.author.login -eq "app/copilot-swe-agent" -or
             $_.author.login -match "github-copilot" -or
             $_.author.login -match "swe-agent") -or
            
            # Check title patterns
            ($_.title -match "copilot" -or
             $_.title -match "🔧 Fix" -or
             $_.title -match "automated" -or
             $_.title -match "compatibility") -or
            
            # Check branch patterns
            ($_.headRefName -match "copilot" -or
             $_.headRefName -match "fix-" -or
             $_.headRefName -match "automated") -or
            
            # Check labels
            ($_.labels -and ($_.labels | Where-Object { $_.name -match "copilot" -or $_.name -match "automated" }))
        } | ForEach-Object {
            @{
                Number = $_.number
                Title = $_.title
                HeadRef = $_.headRefName
                Author = $_.author.login
                IsBot = $_.author.is_bot
                CreatedAt = $_.createdAt
                UpdatedAt = $_.updatedAt
                Labels = $_.labels
            }
        }
        
        if ($copilotPRs.Count -eq 0) {
            Write-StatusMessage "ℹ️  No Copilot PRs found using advanced detection" -Color $CYAN
            
            if ($DebugMode) {
                Write-StatusMessage "🔍 Debug: Found $($prData.Count) total PRs, analyzing..." -Color $GRAY
                foreach ($pr in $prData) {
                    Write-StatusMessage "   PR #$($pr.number): Author=$($pr.author.login), IsBot=$($pr.author.is_bot), Title=$($pr.title)" -Color $GRAY
                }
            }
            return @()
        }
        
        Write-StatusMessage "✅ Found $($copilotPRs.Count) Copilot PR(s) using advanced detection" -Color $GREEN
        foreach ($pr in $copilotPRs) {
            $botStatus = if ($pr.IsBot) { "(Bot)" } else { "" }
            Write-StatusMessage "   PR #$($pr.Number): $($pr.Title) by $($pr.Author) $botStatus" -Color $BLUE
        }
        
        return $copilotPRs
        
    } catch {
        Write-StatusMessage "❌ Error in enhanced Copilot PR detection: $($_.Exception.Message)" -Color $RED
        return @()
    }
}

# Advanced workflow management
function Get-WorkflowRuns {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🔍 Checking workflow runs for PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get workflow runs for the specific branch
        $runs = gh run list --branch $HeadRef --json id,status,conclusion,workflowName,createdAt,updatedAt --limit 10 | ConvertFrom-Json
        
        if ($runs.Count -eq 0) {
            Write-StatusMessage "ℹ️  No workflow runs found for PR #$PRNumber" -Color $CYAN
            return @()
        }
        
        Write-StatusMessage "📋 Found $($runs.Count) workflow run(s) for PR #$PRNumber" -Color $BLUE
        foreach ($run in $runs) {
            $status = if ($run.conclusion) { $run.conclusion } else { $run.status }
            Write-StatusMessage "   Run #$($run.id): $($run.workflowName) - $status" -Color $CYAN
        }
        
        return $runs
        
    } catch {
        Write-StatusMessage "❌ Error fetching workflow runs: $($_.Exception.Message)" -Color $RED
        return @()
    }
}

# Smart workflow approval with conditions
function Approve-WorkflowRun {
    param(
        [string]$PRNumber,
        [string]$RunId,
        [string]$WorkflowName
    )
    
    if ($SkipWorkflowApproval) {
        Write-StatusMessage "⏭️  Skipping workflow approval (disabled via parameter)" -Color $YELLOW
        return $false
    }
    
    Write-StatusMessage "🔍 Evaluating workflow run #$RunId for approval..." -Color $BLUE
    
    try {
        # Check if workflow needs approval
        $runDetails = gh run view $RunId --json status,conclusion,workflowName | ConvertFrom-Json
        
        if ($runDetails.status -eq "waiting") {
            Write-StatusMessage "✅ Approving workflow run #$RunId" -Color $GREEN
            gh run approve $RunId 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "✅ Successfully approved workflow run #$RunId" -Color $GREEN
                return $true
            } else {
                Write-StatusMessage "❌ Failed to approve workflow run #$RunId" -Color $RED
                return $false
            }
        } else {
            Write-StatusMessage "ℹ️  Workflow run #$RunId does not need approval (status: $($runDetails.status))" -Color $CYAN
            return $false
        }
        
    } catch {
        Write-StatusMessage "❌ Error approving workflow run: $($_.Exception.Message)" -Color $RED
        return $false
    }
}

# Advanced PR validation with comprehensive RUTOS compatibility checking
function Test-PRValidation {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🔍 Starting comprehensive RUTOS validation for PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get comprehensive PR information
        $prInfo = gh pr view $PRNumber --json files,mergeable,mergeStateStatus,draft,state | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            Write-StatusMessage "❌ Failed to get PR information for #$PRNumber" -Color $RED
            return @{
                IsValid = $false
                Issues = @(@{
                    File = "Unknown"
                    Line = 0
                    Type = "Technical"
                    Issue = "Failed to get PR information"
                    Solution = "Check GitHub API access and PR number"
                })
                Message = "Technical error: Cannot access PR information"
                HasTechnicalIssues = $true
            }
        }
        
        # Check if PR is in valid state for validation
        if ($prInfo.draft -eq $true) {
            Write-StatusMessage "⏸️  PR #$PRNumber is in draft state - skipping validation" -Color $YELLOW
            return @{
                IsValid = $true
                Issues = @()
                Message = "PR is in draft state - validation skipped"
                HasTechnicalIssues = $false
            }
        }
        
        # Extract file paths from PR
        $changedFiles = $prInfo.files | ForEach-Object { $_.path }
        
        # Filter for shell script files with enhanced detection
        $shellFiles = $changedFiles | Where-Object { 
            $_ -match '\.(sh|bash)$' -or
            $_ -match '^[^.]*$' -and (Test-ShellFileContent -FilePath $_)
        }
        
        if ($shellFiles.Count -eq 0) {
            Write-StatusMessage "ℹ️  No shell script files found in PR #$PRNumber" -Color $CYAN
            return @{
                IsValid = $true
                Issues = @()
                Message = "No shell script files to validate"
                HasTechnicalIssues = $false
            }
        }
        
        Write-StatusMessage "📄 Found $($shellFiles.Count) shell script file(s) to validate" -Color $BLUE
        
        $allIssues = @()
        $technicalIssues = @()
        
        # Validate each file with enhanced error handling
        foreach ($file in $shellFiles) {
            Write-StatusMessage "   📄 Validating: $file" -Color $BLUE
            
            try {
                # Multi-method file content retrieval
                $fileContent = Get-FileContentFromPR -PRNumber $PRNumber -FilePath $file -HeadRef $HeadRef
                
                if ($fileContent.Success -eq $false) {
                    $technicalIssues += @{
                        File = $file
                        Line = 0
                        Type = "Technical"
                        Issue = $fileContent.Error
                        Solution = "Manual validation required - GitHub API access issue"
                    }
                    continue
                }
                
                # Comprehensive RUTOS compatibility validation
                $fileIssues = Test-FileRUTOSCompatibility -FilePath $file -FileContent $fileContent.Content
                $allIssues += $fileIssues
                
                # Report validation results
                if ($fileIssues.Count -eq 0) {
                    Write-StatusMessage "   ✅ $file - No issues found" -Color $GREEN
                } else {
                    $critical = ($fileIssues | Where-Object { $_.Type -eq "Critical" }).Count
                    $major = ($fileIssues | Where-Object { $_.Type -eq "Major" }).Count
                    $minor = ($fileIssues | Where-Object { $_.Type -eq "Minor" }).Count
                    Write-StatusMessage "   ❌ $file - $critical critical, $major major, $minor minor issues" -Color $RED
                }
                
            } catch {
                Write-StatusMessage "   ❌ Error validating $file: $_" -Color $RED
                $technicalIssues += @{
                    File = $file
                    Line = 0
                    Type = "Technical"
                    Issue = "Validation error: $($_.Exception.Message)"
                    Solution = "Manual validation required - script error"
                }
            }
        }
        
        # Analyze results and determine response strategy
        $validationIssues = $allIssues | Where-Object { $_.Type -ne "Technical" }
        
        # CRITICAL: Only post validation comments for real RUTOS issues, not technical problems
        if ($technicalIssues.Count -gt 0) {
            Write-StatusMessage "⚠️  Technical issues found - skipping validation comment to avoid unnecessary costs" -Color $YELLOW
            Write-StatusMessage "💰 Cost optimization: Not posting @copilot comment for technical failures" -Color $YELLOW
            
            return @{
                IsValid = $false
                Issues = $technicalIssues
                Message = "Technical issues prevented validation - manual review needed"
                HasTechnicalIssues = $true
            }
        }
        
        if ($validationIssues.Count -eq 0) {
            Write-StatusMessage "✅ All files pass comprehensive RUTOS compatibility validation" -Color $GREEN
            return @{
                IsValid = $true
                Issues = @()
                Message = "All files pass RUTOS compatibility validation"
                HasTechnicalIssues = $false
            }
        }
        
        # Format comprehensive validation results
        $validationMessage = Format-ComprehensiveValidationResults -Issues $validationIssues
        
        return @{
            IsValid = $false
            Issues = $validationIssues
            Message = $validationMessage
            HasTechnicalIssues = $false
        }
        
    } catch {
        Write-StatusMessage "❌ Comprehensive validation failed: $($_.Exception.Message)" -Color $RED
        return @{
            IsValid = $false
            Issues = @(@{
                File = "Unknown"
                Line = 0
                Type = "Technical"
                Issue = "Validation system error: $($_.Exception.Message)"
                Solution = "Check script and GitHub API access"
            })
            Message = "Technical error during validation"
            HasTechnicalIssues = $true
        }
    }
}

# Multi-method file content retrieval with comprehensive fallbacks
function Get-FileContentFromPR {
    param(
        [string]$PRNumber,
        [string]$FilePath,
        [string]$HeadRef
    )
    
    Write-StatusMessage "   🔄 Fetching file content: $FilePath" -Color $CYAN
    
    try {
        # Method 1: Get head SHA for most reliable access
        $prInfo = gh api repos/:owner/:repo/pulls/$PRNumber --jq '.head.sha' 2>&1
        $headSha = $null
        if ($LASTEXITCODE -eq 0 -and $prInfo) {
            $headSha = $prInfo.Trim()
            Write-StatusMessage "   📋 Head SHA: $headSha" -Color $GRAY
        }
        
        $fileContent = $null
        $decodedContent = $null
        
        # Method 1: Use head SHA (most reliable)
        if ($headSha) {
            Write-StatusMessage "   🔄 Method 1: Using head SHA..." -Color $GRAY
            $fileContent = gh api repos/:owner/:repo/contents/$FilePath --ref $headSha --jq '.content' 2>&1
            if ($LASTEXITCODE -eq 0 -and $fileContent -and $fileContent -ne "null") {
                $decodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($fileContent))
                Write-StatusMessage "   ✅ Method 1 successful" -Color $GREEN
            }
        }
        
        # Method 2: Use branch reference
        if (-not $decodedContent) {
            Write-StatusMessage "   🔄 Method 2: Using branch reference..." -Color $GRAY
            $fileContent = gh api repos/:owner/:repo/contents/$FilePath --ref $HeadRef --jq '.content' 2>&1
            if ($LASTEXITCODE -eq 0 -and $fileContent -and $fileContent -ne "null") {
                $decodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($fileContent))
                Write-StatusMessage "   ✅ Method 2 successful" -Color $GREEN
            }
        }
        
        # Method 3: Use PR files API
        if (-not $decodedContent) {
            Write-StatusMessage "   🔄 Method 3: Using PR files API..." -Color $GRAY
            $prFiles = gh api repos/:owner/:repo/pulls/$PRNumber/files --jq '.[]' 2>&1
            if ($LASTEXITCODE -eq 0) {
                $prFilesData = $prFiles | ConvertFrom-Json
                $targetFile = $prFilesData | Where-Object { $_.filename -eq $FilePath }
                if ($targetFile -and $targetFile.patch) {
                    # Extract file content from patch (limited but better than nothing)
                    $decodedContent = $targetFile.patch
                    Write-StatusMessage "   ⚠️  Method 3: Using patch data (limited)" -Color $YELLOW
                }
            }
        }
        
        # Method 4: Direct file download
        if (-not $decodedContent) {
            Write-StatusMessage "   🔄 Method 4: Direct file download..." -Color $GRAY
            $rawContent = gh api repos/:owner/:repo/contents/$FilePath --ref $HeadRef --jq '.download_url' 2>&1
            if ($LASTEXITCODE -eq 0 -and $rawContent) {
                $downloadUrl = $rawContent.Trim().Replace('"', '')
                $decodedContent = Invoke-WebRequest -Uri $downloadUrl -UseBasicParsing | Select-Object -ExpandProperty Content
                Write-StatusMessage "   ✅ Method 4 successful" -Color $GREEN
            }
        }
        
        if ($decodedContent) {
            return @{
                Success = $true
                Content = $decodedContent
                Error = $null
            }
        } else {
            return @{
                Success = $false
                Content = $null
                Error = "Could not fetch file content using any method"
            }
        }
        
    } catch {
        return @{
            Success = $false
            Content = $null
            Error = "Error fetching file content: $($_.Exception.Message)"
        }
    }
}

# Test if a file is likely a shell script based on content
function Test-ShellFileContent {
    param([string]$FilePath)
    
    try {
        # This is a placeholder - in a real implementation, you'd check file content
        # For now, return false to avoid false positives
        return $false
    } catch {
        return $false
    }
}

# Comprehensive RUTOS compatibility validation with enhanced rules
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
    
    # Split content into lines for detailed analysis
    $lines = $FileContent -split "`r?`n"
    
    Write-StatusMessage "   🔍 Analyzing $($lines.Count) lines in $FilePath" -Color $GRAY
    
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNumber = $i + 1
        $line = $lines[$i]
        
        # Skip empty lines and comments
        if ($line.Trim() -eq "" -or $line.Trim().StartsWith("#")) {
            continue
        }
        
        # CRITICAL: Bash shebang detection
        if ($line -match '^#!/bin/bash') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Critical"
                Issue = "Uses bash shebang instead of POSIX sh"
                Solution = "Change to: #!/bin/sh"
                Code = $line.Trim()
                ShellCheckCode = "SC3001"
                Description = "RUTOS uses busybox which requires POSIX sh, not bash"
            }
        }
        
        # CRITICAL: Bash-specific [[ ]] syntax
        if ($line -match '\[\[.*\]\]') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Critical"
                Issue = "Uses bash-specific [[ ]] syntax"
                Solution = "Replace [[ ]] with [ ] for POSIX compatibility"
                Code = $line.Trim()
                ShellCheckCode = "SC2007"
                Description = "Double brackets [[ ]] are bash-specific. Use single brackets [ ] for POSIX sh compatibility"
            }
        }
        
        # CRITICAL: Bash arrays
        if ($line -match '\w+\s*=\s*\(' -or $line -match '\$\{[^}]*\[\@\*\]\}') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Critical"
                Issue = "Uses bash arrays (not supported in busybox)"
                Solution = "Convert to space-separated strings or multiple variables"
                Code = $line.Trim()
                ShellCheckCode = "SC3054"
                Description = "Bash arrays are not supported in busybox sh. Use space-separated strings or multiple variables"
            }
        }
        
        # MAJOR: local keyword
        if ($line -match '\blocal\s+\w+') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Uses 'local' keyword (busybox incompatible)"
                Solution = "Remove 'local' keyword. In busybox, all variables are global"
                Code = $line.Trim()
                ShellCheckCode = "SC3043"
                Description = "The 'local' keyword is not supported in busybox sh. All variables are global"
            }
        }
        
        # MAJOR: echo -e usage
        if ($line -match 'echo\s+-e') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Uses 'echo -e' instead of printf"
                Solution = "Replace with printf for better portability"
                Code = $line.Trim()
                ShellCheckCode = "SC2154"
                Description = "echo -e is not portable. Use printf for escape sequences"
            }
        }
        
        # MAJOR: function() syntax
        if ($line -match '^\s*function\s+\w+\s*\(\s*\)') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Uses function() syntax instead of POSIX format"
                Solution = "Change to POSIX format: funcName() {"
                Code = $line.Trim()
                ShellCheckCode = "SC2112"
                Description = "Use name() { } syntax instead of function name() { } for POSIX compatibility"
            }
        }
        
        # MAJOR: source command
        if ($line -match '\bsource\s+') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Uses 'source' command instead of '.'"
                Solution = "Replace 'source' with '.' (dot command)"
                Code = $line.Trim()
                ShellCheckCode = "SC2046"
                Description = "The 'source' command is bash-specific. Use '.' (dot) for POSIX compatibility"
            }
        }
        
        # MAJOR: printf format string issues
        if ($line -match 'printf.*\$\{[^}]*\}.*%[sd]' -or $line -match 'printf.*\$[A-Z_][A-Z0-9_]*.*%[sd]') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Major"
                Issue = "Variables in printf format string (SC2059)"
                Solution = "Move variables to arguments: printf '%s%s%s' `$VAR1 `$VAR2 `$VAR3"
                Code = $line.Trim()
                ShellCheckCode = "SC2059"
                Description = "Variables in printf format strings can cause security issues. Use %s placeholders and pass variables as arguments"
            }
        }
        
        # MINOR: Potential busybox compatibility issues
        if ($line -match '\bexport\s+-f') {
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = "Minor"
                Issue = "Uses 'export -f' which may not be supported in busybox"
                Solution = "Avoid exporting functions in busybox environments"
                Code = $line.Trim()
                ShellCheckCode = "SC3045"
                Description = "Function exporting is not reliable in busybox sh"
            }
        }
    }
    
    Write-StatusMessage "   📊 Found $($issues.Count) issues in $FilePath" -Color $GRAY
    
    return $issues
}

# Format comprehensive validation results with enhanced markdown
function Format-ComprehensiveValidationResults {
    param([Array]$Issues)
    
    if ($Issues.Count -eq 0) {
        return "✅ All files pass comprehensive RUTOS compatibility validation"
    }
    
    $result = @()
    $result += "## 🔍 RUTOS Compatibility Validation Results"
    $result += ""
    $result += "**Validation Status**: ❌ **FAILED** - Issues found that need attention"
    $result += ""
    
    # Summary statistics
    $critical = ($Issues | Where-Object { $_.Type -eq "Critical" }).Count
    $major = ($Issues | Where-Object { $_.Type -eq "Major" }).Count
    $minor = ($Issues | Where-Object { $_.Type -eq "Minor" }).Count
    
    $result += "### 📊 Summary"
    $result += "- 🔴 **Critical Issues**: $critical (Must fix - will cause failures)"
    $result += "- 🟡 **Major Issues**: $major (Should fix - may cause problems)"
    $result += "- 🟠 **Minor Issues**: $minor (Consider fixing - best practices)"
    $result += ""
    
    # Group issues by file
    $fileGroups = $Issues | Group-Object -Property File
    
    foreach ($fileGroup in $fileGroups) {
        $fileName = $fileGroup.Name
        $fileIssues = $fileGroup.Group
        
        $result += "### 📄 File: ``$fileName``"
        $result += ""
        
        # Group by severity
        $criticalIssues = $fileIssues | Where-Object { $_.Type -eq "Critical" }
        $majorIssues = $fileIssues | Where-Object { $_.Type -eq "Major" }
        $minorIssues = $fileIssues | Where-Object { $_.Type -eq "Minor" }
        
        if ($criticalIssues.Count -gt 0) {
            $result += "#### 🔴 Critical Issues ($($criticalIssues.Count))"
            $result += "*These issues will cause failures on RUTOS and must be fixed*"
            $result += ""
            foreach ($issue in $criticalIssues) {
                $result += "**Line $($issue.Line)**: $($issue.Issue)"
                $result += "- **Current Code**: ``$($issue.Code)``"
                $result += "- **Solution**: $($issue.Solution)"
                $result += "- **ShellCheck**: $($issue.ShellCheckCode)"
                $result += "- **Why**: $($issue.Description)"
                $result += ""
            }
        }
        
        if ($majorIssues.Count -gt 0) {
            $result += "#### 🟡 Major Issues ($($majorIssues.Count))"
            $result += "*These issues may cause problems and should be fixed*"
            $result += ""
            foreach ($issue in $majorIssues) {
                $result += "**Line $($issue.Line)**: $($issue.Issue)"
                $result += "- **Current Code**: ``$($issue.Code)``"
                $result += "- **Solution**: $($issue.Solution)"
                $result += "- **ShellCheck**: $($issue.ShellCheckCode)"
                $result += "- **Why**: $($issue.Description)"
                $result += ""
            }
        }
        
        if ($minorIssues.Count -gt 0) {
            $result += "#### 🟠 Minor Issues ($($minorIssues.Count))"
            $result += "*These issues represent best practices and should be considered*"
            $result += ""
            foreach ($issue in $minorIssues) {
                $result += "**Line $($issue.Line)**: $($issue.Issue)"
                $result += "- **Current Code**: ``$($issue.Code)``"
                $result += "- **Solution**: $($issue.Solution)"
                $result += "- **ShellCheck**: $($issue.ShellCheckCode)"
                $result += "- **Why**: $($issue.Description)"
                $result += ""
            }
        }
    }
    
    $result += "---"
    $result += "### 🛠️ Next Steps"
    $result += "1. Fix all **Critical** issues first (they will cause failures)"
    $result += "2. Address **Major** issues (they may cause problems)"
    $result += "3. Consider **Minor** issues for best practices"
    $result += ""
    $result += "### 📚 Resources"
    $result += "- [RUTOS Documentation](https://wiki.teltonika-networks.com/view/RUTOS)"
    $result += "- [POSIX Shell Guide](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/sh.html)"
    $result += "- [ShellCheck Online](https://www.shellcheck.net/)"
    $result += ""
    $result += "*Validation performed by Advanced RUTOS Compatibility Checker*"
    $result += "*🤖 This comment was generated because actual compatibility issues were found*"
    
    return $result -join "`n"
}

# Enhanced PR processing with comprehensive workflow management
function Start-CopilotPRs {
    Write-StatusMessage "🚀 Starting Advanced Copilot PR Monitoring System..." -Color $GREEN
    Write-StatusMessage "💰 Cost optimization: Only posting validation comments for real issues" -Color $YELLOW
    
    # Get Copilot PRs using advanced detection
    $openPRs = Get-CopilotPRs
    
    if ($openPRs.Count -eq 0) {
        Write-StatusMessage "ℹ️  No Copilot PRs found using advanced detection" -Color $CYAN
        return
    }
    
    Write-StatusMessage "📋 Processing $($openPRs.Count) Copilot PR(s) with advanced monitoring..." -Color $BLUE
    
    foreach ($pr in $openPRs) {
        Write-StatusMessage "`n" + ("=" * 80) -Color $PURPLE
        Write-StatusMessage "🔍 Processing PR #$($pr.Number): $($pr.Title)" -Color $PURPLE
        Write-StatusMessage "📝 Author: $($pr.Author) | Branch: $($pr.HeadRef)" -Color $BLUE
        Write-StatusMessage ("=" * 80) -Color $PURPLE
        
        # Check workflow runs and approve if needed
        if (-not $SkipWorkflowApproval) {
            $workflowRuns = Get-WorkflowRuns -PRNumber $pr.Number -HeadRef $pr.HeadRef
            foreach ($run in $workflowRuns) {
                if ($run.status -eq "waiting") {
                    Approve-WorkflowRun -PRNumber $pr.Number -RunId $run.id -WorkflowName $run.workflowName
                }
            }
        }
        
        # Skip validation if requested
        if ($SkipValidation) {
            Write-StatusMessage "⏭️  Skipping validation (disabled via parameter)" -Color $YELLOW
            continue
        }
        
        # Perform comprehensive validation
        $validationResult = Test-PRValidation -PRNumber $pr.Number -HeadRef $pr.HeadRef
        
        # Smart comment posting logic - CRITICAL for cost optimization
        if ($validationResult.IsValid) {
            Write-StatusMessage "✅ PR #$($pr.Number) passed comprehensive validation" -Color $GREEN
            
            # Post success comment only if forced or if there were previous issues
            if ($ForceValidation) {
                $successComment = "✅ **RUTOS Compatibility Validation: PASSED**`n`nAll files pass comprehensive RUTOS compatibility validation."
                gh api repos/:owner/:repo/issues/$($pr.Number)/comments -f body="$successComment" 2>&1 | Out-Null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "✅ Posted success comment to PR #$($pr.Number)" -Color $GREEN
                } else {
                    Write-StatusMessage "❌ Failed to post success comment to PR #$($pr.Number)" -Color $RED
                }
            }
            
        } elseif ($validationResult.HasTechnicalIssues) {
            Write-StatusMessage "⚠️  PR #$($pr.Number) has technical issues - NOT posting comment to save costs" -Color $YELLOW
            Write-StatusMessage "💰 Cost optimization: Avoided unnecessary @copilot mention" -Color $YELLOW
            
            # Log technical issues for debugging
            foreach ($issue in $validationResult.Issues) {
                Write-StatusMessage "   🔧 Technical: $($issue.Issue)" -Color $GRAY
            }
            
        } else {
            Write-StatusMessage "❌ PR #$($pr.Number) has validation issues - posting detailed comment" -Color $RED
            Write-StatusMessage "💬 Posting validation comment with specific solutions" -Color $BLUE
            
            # Post comprehensive validation comment
            $comment = $validationResult.Message
            gh api repos/:owner/:repo/issues/$($pr.Number)/comments -f body="$comment" 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "✅ Posted comprehensive validation comment to PR #$($pr.Number)" -Color $GREEN
            } else {
                Write-StatusMessage "❌ Failed to post validation comment to PR #$($pr.Number)" -Color $RED
            }
        }
        
        # Handle merge conflicts if enabled
        if ($AutoResolveConflicts) {
            # This would be implemented based on specific requirements
            Write-StatusMessage "🔄 Auto-resolve conflicts is enabled but not yet implemented" -Color $YELLOW
        }
    }
    
    Write-StatusMessage "`n" + ("=" * 80) -Color $GREEN
    Write-StatusMessage "🎉 Advanced Copilot PR Monitoring Completed!" -Color $GREEN
    Write-StatusMessage "💰 Cost optimization: Only posted comments for real validation issues" -Color $YELLOW
    Write-StatusMessage ("=" * 80) -Color $GREEN
}

# Main execution with enhanced error handling
try {
    # Validate environment
    if (-not (Test-Path ".git")) {
        Write-StatusMessage "❌ This script must be run from the repository root" -Color $RED
        exit 1
    }
    
    # Check GitHub CLI availability
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-StatusMessage "❌ GitHub CLI (gh) is not installed or not in PATH" -Color $RED
        Write-StatusMessage "📋 Install: https://cli.github.com/" -Color $CYAN
        exit 1
    }
    
    # Verify GitHub CLI authentication
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "❌ GitHub CLI is not authenticated" -Color $RED
        Write-StatusMessage "🔐 Run: gh auth login" -Color $CYAN
        exit 1
    }
    
    # Display configuration
    Write-StatusMessage "🔧 Configuration:" -Color $CYAN
    Write-StatusMessage "   VerboseOutput: $VerboseOutput" -Color $GRAY
    Write-StatusMessage "   SkipValidation: $SkipValidation" -Color $GRAY
    Write-StatusMessage "   AutoResolveConflicts: $AutoResolveConflicts" -Color $GRAY
    Write-StatusMessage "   SkipWorkflowApproval: $SkipWorkflowApproval" -Color $GRAY
    Write-StatusMessage "   ForceValidation: $ForceValidation" -Color $GRAY
    Write-StatusMessage "   MonitorOnly: $MonitorOnly" -Color $GRAY
    Write-StatusMessage "   TestMode: $TestMode" -Color $GRAY
    Write-StatusMessage "   DebugMode: $DebugMode" -Color $GRAY
    
    # Run the advanced monitoring system
    Start-CopilotPRs
    
} catch {
    Write-StatusMessage "❌ Advanced monitoring system failed: $($_.Exception.Message)" -Color $RED
    Write-StatusMessage "🔍 Error details: $($_.ScriptStackTrace)" -Color $GRAY
    exit 1
}
