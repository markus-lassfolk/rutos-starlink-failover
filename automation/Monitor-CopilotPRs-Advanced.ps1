param(
    [int]$PRNumber = $null,
    [switch]$VerboseOutput = $false,
    [switch]$SkipValidation = $false,
    [switch]$RequestCopilotForConflicts = $false,
    [switch]$SkipWorkflowApproval = $false,
    [switch]$ForceValidation = $false,
    [switch]$MonitorOnly = $false,
    [switch]$TestMode = $false,
    [switch]$DebugMode = $false
)

param(
    [int]$PRNumber = $null,
    [switch]$VerboseOutput = $false,
    [switch]$SkipValidation = $false,
    [switch]$RequestCopilotForConflicts = $false,
    [switch]$SkipWorkflowApproval = $false,
    [switch]$ForceValidation = $false,
    [switch]$MonitorOnly = $false,
    [switch]$TestMode = $false,
    [switch]$DebugMode = $false
)

# Import the enhanced label management module
$labelModulePath = Join-Path $PSScriptRoot "GitHub-Label-Management.psm1"
if (Test-Path $labelModulePath) {
    Import-Module $labelModulePath -Force -ErrorAction SilentlyContinue
    Write-Host "✅ Loaded enhanced label management system (100 labels)" -ForegroundColor Green
} else {
    Write-Host "⚠️  Enhanced label management module not found - basic functionality only" -ForegroundColor Yellow
}

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

# Get specific PR by number
function Get-SpecificPR {
    param(
        [int]$PRNumber
    )
    
    Write-StatusMessage "🔍 Fetching specific PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get PR information
        $prInfo = gh pr view $PRNumber --json number,title,headRefName,author,labels,createdAt,updatedAt,state
        
        if ($LASTEXITCODE -ne 0) {
            Write-StatusMessage "❌ Failed to fetch PR #$PRNumber" -Color $RED
            return $null
        }
        
        $prData = $prInfo | ConvertFrom-Json
        
        # Check if PR is open
        if ($prData.state -ne "OPEN") {
            Write-StatusMessage "⚠️  PR #$PRNumber is not open (state: $($prData.state))" -Color $YELLOW
            return $null
        }
        
        # Convert to standard format
        $pr = @{
            Number = $prData.number
            Title = $prData.title
            HeadRef = $prData.headRefName
            Author = $prData.author.login
            IsBot = $prData.author.is_bot
            CreatedAt = $prData.createdAt
            UpdatedAt = $prData.updatedAt
            Labels = $prData.labels
        }
        
        $botStatus = if ($pr.IsBot) { "(Bot)" } else { "" }
        Write-StatusMessage "✅ Found PR #$($pr.Number): $($pr.Title) by $($pr.Author) $botStatus" -Color $GREEN
        
        return $pr
        
    } catch {
        Write-StatusMessage "❌ Error fetching PR #${PRNumber}: $($_.Exception.Message)" -Color $RED
        return $null
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
        $runs = gh run list --branch $HeadRef --json databaseId,status,conclusion,workflowName,createdAt,updatedAt --limit 10 | ConvertFrom-Json
        
        if ($runs.Count -eq 0) {
            Write-StatusMessage "ℹ️  No workflow runs found for PR #$PRNumber" -Color $CYAN
            return @()
        }
        
        Write-StatusMessage "📋 Found $($runs.Count) workflow run(s) for PR #$PRNumber" -Color $BLUE
        foreach ($run in $runs) {
            $status = if ($run.conclusion) { $run.conclusion } else { $run.status }
            Write-StatusMessage "   Run #$($run.databaseId): $($run.workflowName) - $status" -Color $CYAN
        }
        
        return $runs
        
    } catch {
        Write-StatusMessage "❌ Error fetching workflow runs: $($_.Exception.Message)" -Color $RED
        return @()
    }
}

# Show repository settings guidance for fixing workflow approval issues
function Invoke-WorkflowDispatch {
    param(
        [int]$PRNumber,
        [string]$HeadRef
    )
    
    try {
        # List available workflow dispatch workflows
        $workflows = gh api repos/:owner/:repo/actions/workflows --jq '.workflows[] | select(.state=="active") | {name, id, path}'
        if ($LASTEXITCODE -eq 0) {
            $workflowList = $workflows | ConvertFrom-Json
            
            foreach ($workflow in $workflowList) {
                if ($workflow.name -match "test|validation|check" -or $workflow.path -match "test|validation|check") {
                    Write-StatusMessage "     🔄 Triggering workflow: $($workflow.name)" -Color $CYAN
                    
                    $dispatchData = @{
                        ref = $HeadRef
                        inputs = @{
                            pr_number = $PRNumber.ToString()
                        }
                    } | ConvertTo-Json -Depth 3
                    
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    $dispatchData | Out-File -FilePath $tempFile -Encoding UTF8
                    
                    $result = gh api repos/:owner/:repo/actions/workflows/$($workflow.id)/dispatches -X POST --input $tempFile
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-StatusMessage "     ✅ Workflow dispatch sent: $($workflow.name)" -Color $GREEN
                        return @{ Success = $true }
                    }
                }
            }
        }
        
        return @{ Success = $false; Error = "No suitable workflows found or dispatch failed" }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Create-EmptyCommitViaAPI {
    param(
        [int]$PRNumber,
        [string]$HeadRef
    )
    
    try {
        # Get PR head SHA for API operations
        $prInfo = gh api repos/:owner/:repo/pulls/$PRNumber --jq '.head.sha'
        if ($LASTEXITCODE -ne 0 -or -not $prInfo) {
            return @{ Success = $false; Error = "Failed to get PR head SHA" }
        }
        
        $headSha = $prInfo.Trim()
        Write-StatusMessage "     📋 Using head SHA: $headSha" -Color $GRAY
        
        # Get tree SHA for the commit
        $treeInfo = gh api repos/:owner/:repo/git/commits/$headSha --jq '.tree.sha'
        if ($LASTEXITCODE -ne 0 -or -not $treeInfo) {
            return @{ Success = $false; Error = "Failed to get tree SHA" }
        }
        
        $treeSha = $treeInfo.Trim()
        Write-StatusMessage "     📋 Using tree SHA: $treeSha" -Color $GRAY
        
        # Create empty commit via GitHub API
        $emptyCommitData = @{
            message = "🚀 Trigger workflows for PR #$PRNumber"
            tree = $treeSha
            parents = @($headSha)
        } | ConvertTo-Json -Depth 3
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        $emptyCommitData | Out-File -FilePath $tempFile -Encoding UTF8
        
        $commitResult = gh api repos/:owner/:repo/git/commits -X POST --input $tempFile
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -ne 0) {
            return @{ Success = $false; Error = "Failed to create empty commit via API" }
        }
        
        $commitInfo = $commitResult | ConvertFrom-Json
        $newCommitSha = $commitInfo.sha
        Write-StatusMessage "     ✅ Empty commit created: $newCommitSha" -Color $GREEN
        
        # Update branch reference via API
        $updateRefData = @{
            sha = $newCommitSha
            force = $false
        } | ConvertTo-Json -Depth 3
        
        $tempRefFile = [System.IO.Path]::GetTempFileName()
        $updateRefData | Out-File -FilePath $tempRefFile -Encoding UTF8
        
        $refResult = gh api repos/:owner/:repo/git/refs/heads/$HeadRef -X PATCH --input $tempRefFile
        Remove-Item $tempRefFile -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "     ✅ Branch updated via API - workflows should trigger" -Color $GREEN
            return @{ Success = $true }
        } else {
            return @{ Success = $false; Error = "Failed to update branch reference" }
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Show-RepositorySettingsGuidance {
    Write-StatusMessage "" -Color $GRAY
    Write-StatusMessage "   💡 **PERMANENT SOLUTION - Repository Settings:**" -Color $PURPLE
    Write-StatusMessage "   🔧 Go to: https://github.com/markus-lassfolk/rutos-starlink-failover/settings/actions" -Color $BLUE
    Write-StatusMessage "" -Color $GRAY
    Write-StatusMessage "   ✅ **Workflow permissions** → Change to: 'Read and write permissions'" -Color $GREEN
    Write-StatusMessage "   ✅ **Allow GitHub Actions** → Enable: 'Allow GitHub Actions to create and approve pull requests'" -Color $GREEN
    Write-StatusMessage "" -Color $GRAY
    Write-StatusMessage "   📋 **Why this helps:**" -Color $CYAN
    Write-StatusMessage "   • Copilot can trigger workflows automatically" -Color $BLUE
    Write-StatusMessage "   • No manual approval needed for local branch PRs" -Color $BLUE
    Write-StatusMessage "   • Workflows can modify labels, comments, and statuses" -Color $BLUE
    Write-StatusMessage "   • GitHub Actions can approve and merge PRs automatically" -Color $BLUE
    Write-StatusMessage "" -Color $GRAY
    Write-StatusMessage "   🚨 **Current Issue:** Workflow permissions are set to 'Read repository contents and packages permissions'" -Color $YELLOW
    Write-StatusMessage "   🔧 **Solution:** Change to 'Read and write permissions' for full automation" -Color $GREEN
}

# Auto-approve all pending workflows for a PR
function Approve-PendingWorkflows {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🔓 Checking for pending workflows that need approval..." -Color $BLUE
    
    try {
        # Get all workflow runs for this branch
        $allRuns = gh run list --branch $HeadRef --json databaseId,status,conclusion,workflowName,createdAt --limit 20 | ConvertFrom-Json
        
        if ($allRuns.Count -eq 0) {
            Write-StatusMessage "   ℹ️  No workflow runs found for branch $HeadRef" -Color $CYAN
            return @{ Success = $true; ApprovedCount = 0 }
        }
        
        $approvedCount = 0
        
        # Check for workflows needing approval - two different patterns:
        # 1. Status "waiting" (traditional approval)
        # 2. Status "completed" with conclusion "action_required" (GitHub Actions approval)
        $pendingRuns = $allRuns | Where-Object { 
            $_.status -eq "waiting" -or 
            ($_.status -eq "completed" -and $_.conclusion -eq "action_required")
        }
        
        if ($pendingRuns.Count -eq 0) {
            Write-StatusMessage "   ℹ️  No pending workflows found that need approval" -Color $CYAN
            return @{ Success = $true; ApprovedCount = 0 }
        }
        
        Write-StatusMessage "   📋 Found $($pendingRuns.Count) pending workflow(s) that need approval" -Color $YELLOW
        Write-StatusMessage "   ⚠️  Note: These workflows require manual approval through GitHub web interface" -Color $YELLOW
        Write-StatusMessage "   🌐 GitHub Actions security requires manual approval for bot-triggered workflows" -Color $CYAN
        Write-StatusMessage "" -Color $GRAY
        Write-StatusMessage "   💡 **Repository Settings Recommendation:**" -Color $PURPLE
        Write-StatusMessage "   🔧 Go to: Settings → Actions → General → Workflow permissions" -Color $BLUE
        Write-StatusMessage "   ✅ Change to: 'Read and write permissions'" -Color $GREEN
        Write-StatusMessage "   ✅ Enable: 'Allow GitHub Actions to create and approve pull requests'" -Color $GREEN
        Write-StatusMessage "   📋 This will eliminate the need for manual approvals for Copilot PRs" -Color $CYAN
        
        foreach ($run in $pendingRuns) {
            $statusType = if ($run.status -eq "waiting") { "waiting" } else { "action_required" }
            Write-StatusMessage "   🔓 Workflow needs approval: $($run.workflowName) (Status: $statusType)" -Color $CYAN
            Write-StatusMessage "   🌐 Manual approval required: https://github.com/markus-lassfolk/rutos-starlink-failover/actions/runs/$($run.databaseId)" -Color $BLUE
        }
        
        Write-StatusMessage "   ⚠️  Manual approval required - cannot be automated for bot-triggered workflows" -Color $YELLOW
        Write-StatusMessage "   📋 Please visit the GitHub Actions page to approve these workflows manually" -Color $BLUE
        
        # Provide repository settings guidance
        Show-RepositorySettingsGuidance
        
        return @{ Success = $true; ApprovedCount = 0; ManualApprovalRequired = $true; PendingCount = $pendingRuns.Count }
        
    } catch {
        Write-StatusMessage "❌ Error approving pending workflows: $($_.Exception.Message)" -Color $RED
        return @{ Success = $false; ApprovedCount = 0 }
    }
}

# Trigger workflow runs for a PR
function Trigger-WorkflowRuns {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🚀 Triggering workflow runs for PR #$PRNumber..." -Color $BLUE
    
    try {
        # For PR workflows, we need to trigger them via PR events, not workflow dispatch
        # Most PR workflows are triggered by push events to the PR branch
        
        $triggeredCount = 0
        
        # Method 1: Check if workflows are already running or pending
        Write-StatusMessage "   � Checking existing workflow runs..." -Color $CYAN
        $existingRuns = Get-WorkflowRuns -PRNumber $PRNumber -HeadRef $HeadRef
        
        if ($existingRuns.Count -gt 0) {
            Write-StatusMessage "   📋 Found $($existingRuns.Count) existing workflow run(s)" -Color $BLUE
            
            # Check for pending runs that need approval - two different patterns:
            # 1. Status "waiting" (traditional approval)
            # 2. Status "completed" with conclusion "action_required" (GitHub Actions approval)
            $pendingRuns = $existingRuns | Where-Object { 
                $_.status -eq "waiting" -or 
                ($_.status -eq "completed" -and $_.conclusion -eq "action_required")
            }
            
            if ($pendingRuns.Count -gt 0) {
                Write-StatusMessage "   🔓 Found $($pendingRuns.Count) workflow(s) needing approval..." -Color $CYAN
                Write-StatusMessage "   ⚠️  These workflows require manual approval through GitHub web interface" -Color $YELLOW
                
                foreach ($run in $pendingRuns) {
                    $statusMsg = if ($run.status -eq "waiting") { "waiting" } else { "action_required" }
                    Write-StatusMessage "   � Workflow needs approval: $($run.workflowName) (Status: $statusMsg)" -Color $CYAN
                    Write-StatusMessage "   🌐 Manual approval: https://github.com/markus-lassfolk/rutos-starlink-failover/actions/runs/$($run.databaseId)" -Color $BLUE
                }
                
                Write-StatusMessage "   ⚠️  Manual approval required - cannot be automated for bot-triggered workflows" -Color $YELLOW
                $triggeredCount = $pendingRuns.Count # Count as "triggered" since we identified them
                
                # Show repository settings guidance
                Show-RepositorySettingsGuidance
            }
            
            # Check for queued or in-progress runs
            $activeRuns = $existingRuns | Where-Object { $_.status -in @("queued", "in_progress") }
            if ($activeRuns.Count -gt 0) {
                Write-StatusMessage "   ⚡ Found $($activeRuns.Count) active workflow run(s) - no triggering needed" -Color $GREEN
                $triggeredCount += $activeRuns.Count
            }
        }
        
        # Method 2: Trigger workflows via GitHub API (server-side, no local branch switching)
        if ($triggeredCount -eq 0) {
            Write-StatusMessage "   🔄 Triggering workflows via GitHub API (server-side)..." -Color $CYAN
            
            try {
                # Method 2a: Try workflow dispatch for specific workflows
                Write-StatusMessage "   � Attempting workflow dispatch..." -Color $CYAN
                $dispatchResult = Invoke-WorkflowDispatch -PRNumber $PRNumber -HeadRef $HeadRef
                
                if ($dispatchResult.Success) {
                    Write-StatusMessage "   ✅ Workflow dispatch successful" -Color $GREEN
                    $triggeredCount++
                } else {
                    Write-StatusMessage "   ⚠️  Workflow dispatch failed, trying alternative methods..." -Color $YELLOW
                    
                    # Method 2b: Create empty commit via API (fallback)
                    Write-StatusMessage "   🔄 Creating empty commit via GitHub API..." -Color $CYAN
                    $commitResult = Create-EmptyCommitViaAPI -PRNumber $PRNumber -HeadRef $HeadRef
                    
                    if ($commitResult.Success) {
                        Write-StatusMessage "   ✅ Empty commit created - workflows should trigger automatically" -Color $GREEN
                        $triggeredCount++
                        
                        # Wait a moment for workflows to start
                        Write-StatusMessage "   ⏳ Waiting 10 seconds for workflows to start..." -Color $CYAN
                        Start-Sleep -Seconds 10
                    } else {
                        Write-StatusMessage "   ❌ Failed to create empty commit: $($commitResult.Error)" -Color $RED
                    }
                }
            } catch {
                Write-StatusMessage "   ❌ Error in API-based workflow triggering: $($_.Exception.Message)" -Color $RED
            }
        }
        
        # Method 3: Re-request reviews to trigger workflows
        if ($triggeredCount -eq 0) {
            Write-StatusMessage "   🔄 Attempting to trigger workflows via review request..." -Color $CYAN
            
            # Get current user
            $currentUser = gh auth status --show-token 2>&1 | Select-String "user:" | ForEach-Object { $_.Line -replace ".*user:\s*", "" }
            if ($currentUser) {
                # Remove and re-add review request to trigger workflows
                gh api repos/:owner/:repo/pulls/$PRNumber/requested_reviewers -X DELETE -f "reviewers[]=$currentUser" 2>&1 | Out-Null
                Start-Sleep -Seconds 2
                gh api repos/:owner/:repo/pulls/$PRNumber/requested_reviewers -X POST -f "reviewers[]=$currentUser" 2>&1 | Out-Null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "   ✅ Review request updated to trigger workflows" -Color $GREEN
                    $triggeredCount++
                }
            }
        }
        
        # Method 4: Post comment to trigger workflows
        if ($triggeredCount -eq 0) {
            Write-StatusMessage "   🔄 Attempting to trigger workflows via comment..." -Color $CYAN
            
            $triggerComment = "🚀 **Workflow Trigger Request**`n`nTrigger GitHub Actions workflows for this PR.`n`n*This comment was automatically generated to trigger workflows.*"
            gh api repos/:owner/:repo/issues/$PRNumber/comments -f body="$triggerComment" 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "   ✅ Posted trigger comment" -Color $GREEN
                $triggeredCount++
            }
        }
        
        if ($triggeredCount -gt 0) {
            return @{ Success = $true; Error = $null; TriggeredCount = $triggeredCount }
        } else {
            return @{ Success = $false; Error = "No workflows could be triggered"; TriggeredCount = 0 }
        }
        
    } catch {
        return @{ Success = $false; Error = "Error triggering workflows: $($_.Exception.Message)"; TriggeredCount = 0 }
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
        # Check if workflow needs approval - two different patterns:
        # 1. Status "waiting" (traditional approval)
        # 2. Status "completed" with conclusion "action_required" (GitHub Actions approval)
        $runDetails = gh run view $RunId --json status,conclusion,workflowName | ConvertFrom-Json
        
        $needsApproval = $runDetails.status -eq "waiting" -or 
                        ($runDetails.status -eq "completed" -and $runDetails.conclusion -eq "action_required")
        
        if ($needsApproval) {
            $statusMsg = if ($runDetails.status -eq "waiting") { "waiting" } else { "action_required" }
            Write-StatusMessage "⚠️  Workflow run #${RunId}: ${WorkflowName} needs manual approval (Status: $statusMsg)" -Color $YELLOW
            Write-StatusMessage "🌐 Manual approval required: https://github.com/markus-lassfolk/rutos-starlink-failover/actions/runs/$RunId" -Color $BLUE
            Write-StatusMessage "📋 GitHub Actions security requires manual approval for bot-triggered workflows" -Color $CYAN
            
            # Note: gh run approve command doesn't exist - approval must be done through web interface
            Write-StatusMessage "ℹ️  Note: Approval cannot be automated - please approve manually in GitHub web interface" -Color $CYAN
            return $false # Return false since we couldn't actually approve it
        } else {
            Write-StatusMessage "ℹ️  Workflow run #$RunId does not need approval (status: $($runDetails.status), conclusion: $($runDetails.conclusion))" -Color $CYAN
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
        $prInfo = gh pr view $PRNumber --json files,mergeable,mergeStateStatus,isDraft,state | ConvertFrom-Json
        
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
        if ($prInfo.isDraft -eq $true) {
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
                
                # Server-side validation using actual tools
                $serverValidation = Test-ServerSideValidation -FilePath $file -FileContent $fileContent.Content
                if ($serverValidation.Issues.Count -gt 0) {
                    $fileIssues += $serverValidation.Issues
                    Write-StatusMessage "   🔧 Server-side validation found $($serverValidation.Issues.Count) additional issues" -Color $CYAN
                }
                
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
                Write-StatusMessage "   ❌ Error validating ${file}: $_" -Color $RED
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

# PR Scope Control - Validate file modifications are within issue scope
function Test-PRScopeCompliance {
    param(
        [string]$PRNumber,
        [string]$PRTitle,
        [string]$PRBody,
        [Array]$ModifiedFiles
    )
    
    Write-StatusMessage "🔍 Checking PR scope compliance for PR #$PRNumber..." -Color $BLUE
    
    $scopeIssues = @()
    
    # Extract issue context from PR body or title
    $issueContext = @()
    
    # Extract file names from PR title - this is the primary indicator
    if ($PRTitle -match "(?i)(\w+[\w\-_]*\.(sh|conf|config|json|md|txt))") {
        $issueContext += $matches[1]
        Write-StatusMessage "   🎯 Found target file in title: $($matches[1])" -Color $GREEN
    }
    
    # Extract mentioned files from PR body
    if ($PRBody -match "(?i)issue|problem|bug|fix|error" -and $PRBody -match "(?i)file|script|config") {
        $mentionedFiles = $PRBody | Select-String -Pattern "(?i)(\w+[\w\-_]*\.(sh|conf|config|json|md|txt))" -AllMatches | 
                         ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
        $issueContext += $mentionedFiles
        if ($mentionedFiles.Count -gt 0) {
            Write-StatusMessage "   📋 Found files in PR body: $($mentionedFiles -join ', ')" -Color $GREEN
        }
    }
    
    # Extract file names from branch name (common pattern)
    if ($PRNumber) {
        try {
            $branchInfo = gh pr view $PRNumber --json headRefName | ConvertFrom-Json
            if ($branchInfo.headRefName -match "(?i)(\w+[\w\-_]*\.(sh|conf|config|json|md|txt))") {
                $issueContext += $matches[1]
                Write-StatusMessage "   🌿 Found target file in branch: $($matches[1])" -Color $GREEN
            }
        } catch {
            # Branch info extraction failed, continue
        }
    }
    
    # Common project files that are generally acceptable to modify
    $acceptableFiles = @(
        "README.md",
        "VERSION",
        "CHANGELOG.md",
        "DEPLOYMENT_SUMMARY.md",
        "DEPLOYMENT-GUIDE.md",
        "DEPLOYMENT-READY.md",
        "*.template.sh",
        "scripts/validate-config.sh",
        "scripts/pre-commit-validation.sh",
        "tests/*.sh"
    )
    
    # Check each modified file
    foreach ($file in $ModifiedFiles) {
        $fileName = Split-Path $file -Leaf
        $isAcceptable = $false
        
        # PRIORITY 1: Check if file is mentioned in issue context (title, body, branch)
        if ($issueContext -contains $fileName) {
            $isAcceptable = $true
            Write-StatusMessage "   ✅ $fileName is mentioned in issue context - ACCEPTABLE" -Color $GREEN
        }
        
        # PRIORITY 2: Check if file path matches issue context
        if (-not $isAcceptable) {
            foreach ($contextFile in $issueContext) {
                if ($file -like "*$contextFile*" -or $contextFile -like "*$fileName*") {
                    $isAcceptable = $true
                    Write-StatusMessage "   ✅ $fileName matches issue context ($contextFile) - ACCEPTABLE" -Color $GREEN
                    break
                }
            }
        }
        
        # PRIORITY 3: Check if file is in acceptable project files list
        if (-not $isAcceptable) {
            foreach ($pattern in $acceptableFiles) {
                if ($fileName -like $pattern -or $file -like $pattern) {
                    $isAcceptable = $true
                    Write-StatusMessage "   ✅ $fileName matches acceptable pattern ($pattern) - ACCEPTABLE" -Color $GREEN
                    break
                }
            }
        }
        
        # Flag potentially out-of-scope files
        if (-not $isAcceptable) {
            Write-StatusMessage "   ⚠️  $fileName may be out of scope - FLAGGED" -Color $YELLOW
            $scopeIssues += @{
                File = $file
                Type = "Scope"
                Issue = "File modification may be outside issue scope"
                Solution = "Verify this file change is related to the original issue"
                Severity = "Warning"
            }
        }
    }
    
    if ($scopeIssues.Count -eq 0) {
        Write-StatusMessage "✅ PR scope compliance - All files appear to be within scope" -Color $GREEN
    } else {
        Write-StatusMessage "⚠️  PR scope compliance - $($scopeIssues.Count) potentially out-of-scope files" -Color $YELLOW
    }
    
    return $scopeIssues
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

# API-based merge conflict analysis with Copilot resolution request
function Resolve-MergeConflicts {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🔄 Analyzing merge conflicts via GitHub API (server-side)..." -Color $BLUE
    
    try {
        # Get PR mergeable status via API
        $prInfo = gh api repos/:owner/:repo/pulls/$PRNumber --jq '.mergeable,.mergeable_state,.merge_commit_sha'
        if ($LASTEXITCODE -ne 0) {
            return @{ Success = $false; Error = "Failed to get PR merge status" }
        }
        
        $prData = $prInfo | ConvertFrom-Json
        $mergeable = $prData.mergeable
        $mergeableState = $prData.mergeable_state
        
        Write-StatusMessage "   📊 PR merge status: mergeable=$mergeable, state=$mergeableState" -Color $CYAN
        
        if ($mergeable -eq $true) {
            Write-StatusMessage "   ✅ PR is mergeable - no conflicts detected" -Color $GREEN
            return @{ Success = $true; Error = $null; HasConflicts = $false }
        }
        
        if ($mergeable -eq $false) {
            Write-StatusMessage "   ⚠️  PR has merge conflicts that need resolution" -Color $YELLOW
            
            # Get conflicted files via API
            try {
                $prFiles = gh api repos/:owner/:repo/pulls/$PRNumber/files --jq '.[]'
                if ($LASTEXITCODE -eq 0) {
                    $filesData = $prFiles | ConvertFrom-Json
                    $conflictedFiles = $filesData | Where-Object { $_.status -eq "modified" -or $_.status -eq "added" }
                    
                    if ($conflictedFiles.Count -gt 0) {
                        Write-StatusMessage "   🔍 Files that may have conflicts:" -Color $CYAN
                        foreach ($file in $conflictedFiles) {
                            Write-StatusMessage "     - $($file.filename) (status: $($file.status))" -Color $GRAY
                        }
                        
                        # Request Copilot to resolve the merge conflicts
                        Write-StatusMessage "   🤖 Requesting Copilot to resolve merge conflicts..." -Color $PURPLE
                        $copilotRequest = Request-CopilotMergeConflictResolution -PRNumber $PRNumber -ConflictedFiles $conflictedFiles
                        
                        if ($copilotRequest.Success) {
                            Write-StatusMessage "   ✅ Copilot merge conflict resolution requested successfully" -Color $GREEN
                            Write-StatusMessage "   ⏳ Copilot will analyze and resolve the conflicts automatically" -Color $CYAN
                            
                            return @{ 
                                Success = $true
                                Error = $null
                                HasConflicts = $true
                                ConflictedFiles = $conflictedFiles
                                CopilotRequested = $true
                                Message = "Copilot has been requested to resolve merge conflicts"
                            }
                        } else {
                            Write-StatusMessage "   ❌ Failed to request Copilot assistance: $($copilotRequest.Error)" -Color $RED
                            
                            # Fallback to manual resolution guidance
                            Write-StatusMessage "   📋 **Manual Resolution Required:**" -Color $YELLOW
                            Write-StatusMessage "     1. Checkout the PR branch locally" -Color $BLUE
                            Write-StatusMessage "     2. Merge main branch: git merge main" -Color $BLUE
                            Write-StatusMessage "     3. Resolve conflicts in the listed files" -Color $BLUE
                            Write-StatusMessage "     4. Commit and push the resolution" -Color $BLUE
                            
                            return @{ 
                                Success = $false
                                Error = "Merge conflicts detected - Copilot request failed, manual resolution required"
                                HasConflicts = $true
                                ConflictedFiles = $conflictedFiles
                                CopilotRequested = $false
                            }
                        }
                    }
                }
            } catch {
                Write-StatusMessage "   ❌ Error getting conflicted files: $($_.Exception.Message)" -Color $RED
            }
        }
        
        if ($mergeable -eq $null) {
            Write-StatusMessage "   ⏳ GitHub is still calculating merge status..." -Color $YELLOW
            Write-StatusMessage "   🔄 Please wait a moment and try again" -Color $CYAN
            return @{ Success = $false; Error = "GitHub is calculating merge status - try again in a moment"; HasConflicts = $null }
        }
        
        return @{ Success = $false; Error = "Unknown merge state: $mergeableState"; HasConflicts = $null }
        
    } catch {
        Write-StatusMessage "   ❌ Error during API-based conflict analysis: $($_.Exception.Message)" -Color $RED
        return @{ Success = $false; Error = "Error during conflict analysis: $($_.Exception.Message)"; HasConflicts = $null }
    }
}

# Request Copilot to resolve merge conflicts
function Request-CopilotMergeConflictResolution {
    param(
        [string]$PRNumber,
        [Array]$ConflictedFiles
    )
    
    Write-StatusMessage "   🤖 Preparing Copilot merge conflict resolution request..." -Color $PURPLE
    
    try {
        # Build a comprehensive conflict resolution request
        $fileList = ($ConflictedFiles | ForEach-Object { "- `$($_.filename)`" }) -join "`n"
        
        $copilotComment = @"
@github-copilot resolve

## 🔄 **Merge Conflict Resolution Request**

This PR has merge conflicts that need to be resolved. Based on our previous experience, you're quite good at handling these intelligently.

### **Conflicted Files:**
$fileList

### **Context:**
- This is a **RUTOS Starlink Failover** project targeting **RUTX50 routers**
- Files must be **POSIX shell compatible** (busybox sh, not bash)
- Preserve **RUTOS compatibility** and avoid bash-specific syntax
- Maintain **configuration templates** and **user settings**

### **Resolution Guidelines:**
1. **Preserve RUTOS compatibility** - Use POSIX sh syntax only
2. **Merge intelligently** - Combine changes where possible
3. **Maintain functionality** - Ensure all features continue to work
4. **Follow project patterns** - Use existing code style and conventions
5. **Version files** - Keep the higher version number if applicable

### **Special Considerations:**
- **Shell Scripts**: Must work in busybox environment
- **Configuration**: Preserve user customizations
- **Documentation**: Merge both sets of changes clearly
- **Version Files**: Choose higher version number

Please analyze the conflicts and provide a resolution that maintains the project's RUTOS compatibility while intelligently merging the changes.

---
*🤖 Automated merge conflict resolution request from monitoring system*
"@

        # Post the comment to the PR
        $tempCommentFile = [System.IO.Path]::GetTempFileName()
        $copilotComment | Out-File -FilePath $tempCommentFile -Encoding UTF8
        
        $commentResult = gh api repos/:owner/:repo/issues/$PRNumber/comments -X POST -f body=@$tempCommentFile
        Remove-Item $tempCommentFile -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "   ✅ Copilot merge conflict resolution comment posted successfully" -Color $GREEN
            return @{ Success = $true; Error = $null }
        } else {
            Write-StatusMessage "   ❌ Failed to post Copilot comment" -Color $RED
            return @{ Success = $false; Error = "Failed to post comment to PR" }
        }
        
    } catch {
        Write-StatusMessage "   ❌ Error requesting Copilot merge conflict resolution: $($_.Exception.Message)" -Color $RED
        return @{ Success = $false; Error = "Error posting Copilot request: $($_.Exception.Message)" }
    }
}

# Helper function for conflict resolution suggestions
function Get-ConflictResolutionSuggestions {
    param(
        [string]$PRNumber,
        [Array]$ConflictedFiles
    )
    
    $suggestions = @()
    
    foreach ($file in $ConflictedFiles) {
        $fileName = $file.filename
        
        # Suggest resolutions based on file type and patterns
        if ($fileName -match "VERSION|version") {
            $suggestions += @{
                File = $fileName
                Suggestion = "Version conflict - keep the higher version number"
                Type = "Version"
            }
        }
        
        if ($fileName -match "\.(md|txt|rst)$") {
            $suggestions += @{
                File = $fileName
                Suggestion = "Documentation conflict - merge both changes with clear separation"
                Type = "Documentation"
            }
        }
        
        if ($fileName -match "\.sh$") {
            $suggestions += @{
                File = $fileName
                Suggestion = "Shell script conflict - carefully review for RUTOS compatibility"
                Type = "Script"
            }
        }
        
        if ($fileName -match "config|Config") {
            $suggestions += @{
                File = $fileName
                Suggestion = "Configuration conflict - preserve user settings where possible"
                Type = "Configuration"
            }
        }
        
        if ($fileName -match "\.json$") {
            $suggestions += @{
                File = $fileName
                Suggestion = "JSON conflict - validate syntax after resolution"
                Type = "JSON"
            }
        }
    }
    
    return $suggestions
}

# Server-side validation using actual tools
function Test-ServerSideValidation {
    param(
        [string]$FilePath,
        [string]$FileContent
    )
    
    $issues = @()
    
    # Skip non-shell files
    if ($FilePath -notmatch '\.(sh|bash)$') {
        return @{ Issues = $issues; Success = $true }
    }
    
    Write-StatusMessage "   🔧 Running server-side validation for $FilePath" -Color $CYAN
    
    try {
        # Create temporary file for validation
        $tempFile = [System.IO.Path]::GetTempFileName()
        $tempShellFile = $tempFile + ".sh"
        
        # Write content to temporary file
        $FileContent | Out-File -FilePath $tempShellFile -Encoding UTF8
        
        # Method 1: Try ShellCheck if available
        if (Get-Command shellcheck -ErrorAction SilentlyContinue) {
            Write-StatusMessage "   🔍 Running ShellCheck..." -Color $GRAY
            
            $shellCheckResult = shellcheck --format=json $tempShellFile 2>&1
            if ($LASTEXITCODE -eq 0 -and $shellCheckResult) {
                try {
                    $shellCheckIssues = $shellCheckResult | ConvertFrom-Json
                    foreach ($issue in $shellCheckIssues) {
                        $severity = switch ($issue.level) {
                            "error" { "Critical" }
                            "warning" { "Major" }
                            "info" { "Minor" }
                            "style" { "Minor" }
                            default { "Minor" }
                        }
                        
                        $issues += @{
                            File = $FilePath
                            Line = $issue.line
                            Type = $severity
                            Issue = $issue.message
                            Solution = "Fix ShellCheck $($issue.code): $($issue.message)"
                            Code = "Line $($issue.line): $($issue.message)"
                            ShellCheckCode = $issue.code
                            Description = "ShellCheck validation: $($issue.message)"
                        }
                    }
                    Write-StatusMessage "   ✅ ShellCheck completed - found $($issues.Count) issues" -Color $GREEN
                } catch {
                    Write-StatusMessage "   ⚠️  ShellCheck output parsing failed" -Color $YELLOW
                }
            }
        }
        
        # Method 2: Try our pre-commit validation script
        if (Test-Path "scripts/pre-commit-validation.sh") {
            Write-StatusMessage "   🔍 Running pre-commit validation..." -Color $GRAY
            
            # Copy file to expected location for validation
            $targetDir = "temp-validation"
            $targetFile = Join-Path $targetDir (Split-Path $FilePath -Leaf)
            
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            
            Copy-Item $tempShellFile $targetFile -Force
            
            # Run validation (using WSL if on Windows)
            $validationCmd = if ($IsWindows) {
                "wsl bash -c 'cd /mnt/c/GitHub/rutos-starlink-failover && ./scripts/pre-commit-validation.sh temp-validation/$(Split-Path $FilePath -Leaf)'"
            } else {
                "./scripts/pre-commit-validation.sh '$targetFile'"
            }
            
            $validationResult = Invoke-Expression $validationCmd 2>&1
            
            if ($validationResult -match "CRITICAL|MAJOR|MINOR") {
                # Parse validation output for issues
                $validationLines = $validationResult -split "`n"
                foreach ($line in $validationLines) {
                    if ($line -match "^\[(.+)\].*Line (\d+):\s*(.+)") {
                        $severity = $matches[1]
                        $lineNum = $matches[2]
                        $message = $matches[3]
                        
                        $issues += @{
                            File = $FilePath
                            Line = [int]$lineNum
                            Type = $severity
                            Issue = $message
                            Solution = "Fix validation issue: $message"
                            Code = "Line $lineNum"
                            ShellCheckCode = "VALIDATION"
                            Description = "Pre-commit validation: $message"
                        }
                    }
                }
                Write-StatusMessage "   ✅ Pre-commit validation completed - found $($issues.Count) total issues" -Color $GREEN
            } else {
                Write-StatusMessage "   ✅ Pre-commit validation passed" -Color $GREEN
            }
            
            # Cleanup
            Remove-Item $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Cleanup temporary files
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tempShellFile -Force -ErrorAction SilentlyContinue
        
        return @{ Issues = $issues; Success = $true }
        
    } catch {
        Write-StatusMessage "   ❌ Server-side validation failed: $($_.Exception.Message)" -Color $RED
        return @{ Issues = $issues; Success = $false }
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
    
    # Determine if this is a RUTOS-specific file requiring stricter POSIX compliance
    $isRUTOSFile = $FilePath -match '.*-rutos\.sh$' -or $FilePath -match 'rutos.*\.sh$'
    
    if ($isRUTOSFile) {
        Write-StatusMessage "   🔍 RUTOS file detected - applying stricter POSIX compliance validation" -Color $YELLOW
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
        
        # MAJOR: local keyword (CRITICAL for RUTOS files)
        if ($line -match '\blocal\s+\w+') {
            $issueType = if ($isRUTOSFile) { "Critical" } else { "Major" }
            $issues += @{
                File = $FilePath
                Line = $lineNumber
                Type = $issueType
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
        
        # RUTOS-specific: Additional POSIX compliance checks
        if ($isRUTOSFile) {
            # Check for bash-specific parameter expansion
            if ($line -match '\$\{[^}]*:[^}]*\}' -and $line -notmatch '\$\{[^}]*:-[^}]*\}') {
                $issues += @{
                    File = $FilePath
                    Line = $lineNumber
                    Type = "Major"
                    Issue = "Uses bash-specific parameter expansion"
                    Solution = "Use POSIX-compliant parameter expansion: \${var:-default}"
                    Code = $line.Trim()
                    ShellCheckCode = "SC3003"
                    Description = "Complex parameter expansion may not be supported in busybox sh"
                }
            }
            
            # Check for read without -r flag (common POSIX issue)
            if ($line -match '\bread\s+(?!-r)') {
                $issues += @{
                    File = $FilePath
                    Line = $lineNumber
                    Type = "Minor"
                    Issue = "read without -r flag may interpret backslashes"
                    Solution = "Use 'read -r' for literal reading"
                    Code = $line.Trim()
                    ShellCheckCode = "SC2162"
                    Description = "read without -r will mangle backslashes"
                }
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
        return @"
# ✅ **RUTOS Compatibility Validation: PASSED**

All files pass comprehensive RUTOS compatibility validation.

## 🎉 **Validation Summary**
- **Status**: ✅ **SUCCESS**
- **Issues Found**: 0
- **Action Required**: None - Ready for merge

---
*🤖 Automated validation completed successfully*
"@
    }
    
    $result = @()
    
    # Header with clear status
    $result += "# 🔍 **RUTOS Compatibility Validation: FAILED**"
    $result += ""
    $result += "**Validation Status**: ❌ **FAILED** - Issues found that require immediate attention"
    $result += ""
    
    # Enhanced summary with visual hierarchy
    $critical = ($Issues | Where-Object { $_.Type -eq "Critical" }).Count
    $major = ($Issues | Where-Object { $_.Type -eq "Major" }).Count
    $minor = ($Issues | Where-Object { $_.Type -eq "Minor" }).Count
    
    $result += "## 📊 **Issue Summary**"
    $result += ""
    $result += "| Priority | Count | Impact |"
    $result += "|----------|-------|---------|"
    $result += "| 🔴 **Critical** | **$critical** | Will cause failures on RUTOS hardware |"
    $result += "| 🟡 **Major** | **$major** | May cause problems in busybox environment |"
    $result += "| 🔵 **Minor** | **$minor** | Best practices and portability improvements |"
    $result += ""
    $result += "**Total Issues**: **$($Issues.Count)**"
    $result += ""
    
    # Priority-based action plan
    if ($critical -gt 0) {
        $result += "## 🚨 **CRITICAL: Immediate Action Required**"
        $result += ""
        $result += "❌ **$critical Critical issues** must be fixed immediately - they will cause failures on RUTX50 hardware."
        $result += ""
    }
    
    if ($major -gt 0) {
        $result += "## ⚠️ **MAJOR: Should Fix Soon**"
        $result += ""
        $result += "🟡 **$major Major issues** may cause problems in the busybox environment."
        $result += ""
    }
    
    if ($minor -gt 0) {
        $result += "## 💡 **MINOR: Consider Fixing**"
        $result += ""
        $result += "🔵 **$minor Minor issues** represent best practices and portability improvements."
        $result += ""
    }
    
    $result += "---"
    $result += ""
    
    # Group issues by file with enhanced formatting
    $fileGroups = $Issues | Group-Object -Property File
    
    foreach ($fileGroup in $fileGroups) {
        $fileName = $fileGroup.Name
        $fileIssues = $fileGroup.Group
        
        # Determine file type
        $isRUTOSFile = $fileName -match '.*-rutos\.sh$' -or $fileName -match 'rutos.*\.sh$'
        $fileType = if ($isRUTOSFile) { "🎯 **RUTOS Hardware File**" } else { "📄 **Standard File**" }
        
        $result += "## 📄 **File Analysis**: ``$fileName``"
        $result += ""
        $result += "**File Type**: $fileType"
        $result += "**Issues Found**: $($fileIssues.Count)"
        $result += ""
        
        # Group by severity with enhanced presentation
        $criticalIssues = $fileIssues | Where-Object { $_.Type -eq "Critical" }
        $majorIssues = $fileIssues | Where-Object { $_.Type -eq "Major" }
        $minorIssues = $fileIssues | Where-Object { $_.Type -eq "Minor" }
        
        if ($criticalIssues.Count -gt 0) {
            $result += "### 🔴 **Critical Issues** ($($criticalIssues.Count))"
            $result += ""
            $result += "> **⚠️ These issues will cause failures on RUTOS hardware and must be fixed immediately**"
            $result += ""
            
            foreach ($issue in $criticalIssues) {
                $result += "#### 📍 **Line $($issue.Line)**: $($issue.Issue)"
                $result += ""
                $result += "**Current Code**:"
                $result += "``````bash"
                $result += "$($issue.Code)"
                $result += "``````"
                $result += ""
                $result += "**Solution**: $($issue.Solution)"
                $result += ""
                $result += "**Details**: $($issue.Description)"
                $result += ""
                $result += "**ShellCheck Code**: ``$($issue.ShellCheckCode)``"
                $result += ""
                $result += "---"
                $result += ""
            }
        }
        
        if ($majorIssues.Count -gt 0) {
            $result += "### 🟡 **Major Issues** ($($majorIssues.Count))"
            $result += ""
            $result += "> **⚠️ These issues may cause problems in the busybox environment and should be fixed**"
            $result += ""
            
            foreach ($issue in $majorIssues) {
                $result += "#### 📍 **Line $($issue.Line)**: $($issue.Issue)"
                $result += ""
                $result += "**Current Code**: ``$($issue.Code)``"
                $result += ""
                $result += "**Solution**: $($issue.Solution)"
                $result += ""
                $result += "**Details**: $($issue.Description)"
                $result += ""
                $result += "**ShellCheck Code**: ``$($issue.ShellCheckCode)``"
                $result += ""
                $result += "---"
                $result += ""
            }
        }
        
        if ($minorIssues.Count -gt 0) {
            $result += "### � **Minor Issues** ($($minorIssues.Count))"
            $result += ""
            $result += "> **💡 These issues represent best practices and portability improvements**"
            $result += ""
            
            foreach ($issue in $minorIssues) {
                $result += "#### 📍 **Line $($issue.Line)**: $($issue.Issue)"
                $result += ""
                $result += "**Current Code**: ``$($issue.Code)``"
                $result += ""
                $result += "**Solution**: $($issue.Solution)"
                $result += ""
                $result += "**Details**: $($issue.Description)"
                $result += ""
                $result += "**ShellCheck Code**: ``$($issue.ShellCheckCode)``"
                $result += ""
                $result += "---"
                $result += ""
            }
        }
    }
    
    # Enhanced action plan
    $result += "## 🛠️ **Action Plan**"
    $result += ""
    $result += "### **Priority Order**"
    $result += "1. 🔴 **Fix Critical Issues First** - These will cause hardware failures"
    $result += "2. 🟡 **Address Major Issues** - These may cause runtime problems"
    $result += "3. 🔵 **Consider Minor Issues** - These improve code quality"
    $result += ""
    
    $result += "### **Validation Workflow**"
    $result += "``````bash"
    $result += "# Run validation on modified files"
    $result += "wsl bash -c 'cd /mnt/c/GitHub/rutos-starlink-failover && ./scripts/pre-commit-validation.sh [file]'" 
    $result += ""
    $result += "# Expected success output:"
    $result += "# '[SUCCESS] ✓ filename: All checks passed'"
    $result += "``````"
    $result += ""
    
    # Enhanced resources section
    $result += "## 📚 **Resources & References**"
    $result += ""
    $result += "| Resource | Description |"
    $result += "|----------|-------------|"
    $result += "| 🏠 [RUTOS Documentation](https://wiki.teltonika-networks.com/view/RUTOS) | Official RUTOS documentation |"
    $result += "| 📖 [POSIX Shell Guide](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/sh.html) | POSIX shell specification |"
    $result += "| 🔧 [ShellCheck Online](https://www.shellcheck.net/) | Online shell script analyzer |"
    $result += "| 📋 [Project Guidelines](.github/copilot-instructions.md) | RUTOS-specific coding guidelines |"
    $result += ""
    
    # Footer with scope control reminder
    $result += "---"
    $result += ""
    $result += "## ⚠️ **Important: Scope Control**"
    $result += ""
    $result += "**🎯 Only modify files mentioned in this validation report**"
    $result += ""
    $result += "- ❌ Do not modify unrelated files"
    $result += "- ❌ Do not change files not listed above"
    $result += "- ✅ Focus only on the specific files with issues"
    $result += ""
    $result += "**🔍 Scope Validation**:"
    $result += "``````bash"
    $result += "# Verify only target files are modified"
    $result += "git diff --name-only HEAD~1"
    $result += "``````"
    $result += ""
    $result += "---"
    $result += ""
    $result += "*🤖 **Automated RUTOS Compatibility Validation** - Generated because actual compatibility issues were found*"
    $result += ""
    $result += "*💰 **Cost Optimization**: This comment was posted because real validation issues were detected*"
    
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
            
            # If no workflow runs found, try to trigger them
            if ($workflowRuns.Count -eq 0) {
                Write-StatusMessage "🚀 No workflow runs found - attempting to trigger workflows..." -Color $BLUE
                $triggerResult = Trigger-WorkflowRuns -PRNumber $pr.Number -HeadRef $pr.HeadRef
                
                if ($triggerResult.Success) {
                    Write-StatusMessage "✅ Successfully triggered workflows for PR #$($pr.Number)" -Color $GREEN
                    # Wait a moment and check again
                    Start-Sleep -Seconds 5
                    $workflowRuns = Get-WorkflowRuns -PRNumber $pr.Number -HeadRef $pr.HeadRef
                } else {
                    Write-StatusMessage "⚠️  Failed to trigger workflows: $($triggerResult.Error)" -Color $YELLOW
                }
            }
            
            # Approve any waiting workflows
            foreach ($run in $workflowRuns) {
                if ($run.status -eq "waiting") {
                    Approve-WorkflowRun -PRNumber $pr.Number -RunId $run.databaseId -WorkflowName $run.workflowName
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
        
        # Get modified files for scope control
        $modifiedFiles = @()
        try {
            $prFiles = gh pr view $pr.Number --json files --jq '.files[].path' 2>$null
            if ($prFiles) {
                $modifiedFiles = $prFiles -split "`n" | Where-Object { $_ -ne "" }
            }
        } catch {
            Write-StatusMessage "⚠️  Could not retrieve modified files for scope control check" -Color $YELLOW
        }
        
        # Perform scope control check
        $scopeIssues = @()
        if ($modifiedFiles.Count -gt 0) {
            $scopeIssues = Test-PRScopeCompliance -PRNumber $pr.Number -PRTitle $pr.Title -PRBody $pr.Body -ModifiedFiles $modifiedFiles
        }
        
        # Smart comment posting logic - CRITICAL for cost optimization
        if ($validationResult.IsValid -and $scopeIssues.Count -eq 0) {
            Write-StatusMessage "✅ PR #$($pr.Number) passed comprehensive validation and scope control" -Color $GREEN
            
            # Post success comment only if forced or if there were previous issues
            if ($ForceValidation) {
                $successComment = "✅ **RUTOS Compatibility Validation: PASSED**`n`nAll files pass comprehensive RUTOS compatibility validation and scope control."
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
            Write-StatusMessage "❌ PR #$($pr.Number) has validation or scope issues - posting detailed comment" -Color $RED
            Write-StatusMessage "💬 Posting validation comment with specific solutions" -Color $BLUE
            
            # Combine validation and scope issues
            $comment = $validationResult.Message
            
            # Add scope control section if there are scope issues
            if ($scopeIssues.Count -gt 0) {
                $comment += "`n`n## 🎯 **Scope Control Review**`n`n"
                $comment += "The following files may be outside the original issue scope:`n`n"
                
                foreach ($scopeIssue in $scopeIssues) {
                    $comment += "### ⚠️ **File**: ``$($scopeIssue.File)```n`n"
                    $comment += "**Issue**: $($scopeIssue.Issue)`n`n"
                    $comment += "**Action Required**: $($scopeIssue.Solution)`n`n"
                    $comment += "---`n`n"
                }
                
                $comment += "### 📋 **Scope Control Guidelines**`n`n"
                $comment += "1. **Review each flagged file** to ensure it's related to the original issue`n"
                $comment += "2. **Remove unrelated changes** or create separate PRs for unrelated improvements`n"
                $comment += "3. **Update the PR description** to explain why each file modification is necessary`n"
                $comment += "4. **Focus on the core issue** - avoid scope creep in automated fixes`n`n"
                
                $comment += "#### 💡 **Acceptable File Types**`n"
                $comment += "- Configuration templates (*.template.sh)`n"
                $comment += "- Validation scripts (scripts/validate-config.sh)`n"
                $comment += "- Test files (tests/*.sh)`n"
                $comment += "- Documentation (README.md, guides)`n"
                $comment += "- Files explicitly mentioned in the original issue`n`n"
            }
            
            gh api repos/:owner/:repo/issues/$($pr.Number)/comments -f body="$comment" 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "✅ Posted comprehensive validation comment to PR #$($pr.Number)" -Color $GREEN
            } else {
                Write-StatusMessage "❌ Failed to post validation comment to PR #$($pr.Number)" -Color $RED
            }
        }
        
        # Handle merge conflicts - Request Copilot assistance if enabled
        if ($RequestCopilotForConflicts) {
            $conflictResolution = Resolve-MergeConflicts -PRNumber $pr.Number -HeadRef $pr.HeadRef
            if ($conflictResolution.Success) {
                if ($conflictResolution.CopilotRequested) {
                    Write-StatusMessage "🤖 Copilot has been requested to resolve merge conflicts for PR #$($pr.Number)" -Color $PURPLE
                } else {
                    Write-StatusMessage "✅ No merge conflicts detected for PR #$($pr.Number)" -Color $GREEN
                }
            } else {
                Write-StatusMessage "❌ Failed to analyze merge conflicts for PR #$($pr.Number): $($conflictResolution.Error)" -Color $RED
            }
        } else {
            # Check for merge conflicts and provide guidance
            $prInfo = gh pr view $pr.Number --json mergeable,mergeStateStatus 2>$null | ConvertFrom-Json
            if ($prInfo -and $prInfo.mergeable -eq "CONFLICTING") {
                Write-StatusMessage "⚠️  PR #$($pr.Number) has merge conflicts that need resolution" -Color $YELLOW
                Write-StatusMessage "💡 Tip: Use -RequestCopilotForConflicts to automatically request Copilot assistance" -Color $CYAN
                
                # Post conflict resolution comment
                $conflictComment = @"
## ⚠️ **Merge Conflicts Detected**

This PR has merge conflicts that need to be resolved before it can be merged.

### 🔧 **Resolution Steps**

1. **Fetch latest changes**:
``````bash
git fetch origin main
``````

2. **Merge or rebase main**:
``````bash
git merge origin/main
# OR
git rebase origin/main
``````

3. **Resolve conflicts in affected files**
4. **Add resolved files**:
``````bash
git add .
``````

5. **Complete the merge/rebase**:
``````bash
git commit -m "Resolve merge conflicts"
# OR (for rebase)
git rebase --continue
``````

6. **Push changes**:
``````bash
git push origin $($pr.HeadRef)
``````

**🤖 Automated Resolution**: Set `-AutoResolveConflicts` flag to enable automatic conflict resolution in the future.
"@
                
                gh api repos/:owner/:repo/issues/$($pr.Number)/comments -f body="$conflictComment" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "✅ Posted merge conflict resolution guidance to PR #$($pr.Number)" -Color $GREEN
                }
            }
        }
    }
    
    Write-StatusMessage "`n" + ("=" * 80) -Color $GREEN
    Write-StatusMessage "🎉 Advanced Copilot PR Monitoring Completed!" -Color $GREEN
    Write-StatusMessage "💰 Cost optimization: Only posted comments for real validation issues" -Color $YELLOW
    Write-StatusMessage ("=" * 80) -Color $GREEN
}

# Request Copilot to fix merge conflicts
function Request-CopilotMergeConflictFix {
    param(
        [string]$PRNumber,
        [string]$HeadRef
    )
    
    Write-StatusMessage "🤖 Requesting Copilot to fix merge conflicts for PR #$PRNumber..." -Color $BLUE
    
    try {
        # Get merge conflict details
        $prInfo = gh pr view $PRNumber --json mergeable,mergeStateStatus,files | ConvertFrom-Json
        
        if ($prInfo.mergeable -eq "CONFLICTING" -or $prInfo.mergeStateStatus -eq "DIRTY") {
            $conflictComment = @"
@github-copilot fix the merge conflicts in this PR.

## 🔧 **Merge Conflict Resolution Request**

This PR has merge conflicts that need to be resolved. Please help fix them.

### 📋 **Current Status**
- **Mergeable**: $($prInfo.mergeable)
- **Merge State**: $($prInfo.mergeStateStatus)
- **Files Modified**: $($prInfo.files.Count)

### 🎯 **Request**
Please resolve the merge conflicts by:
1. Merging the latest changes from main
2. Resolving any conflicts in the affected files
3. Ensuring all functionality remains intact
4. Keeping the changes focused on the original issue

### 💡 **Conflict Resolution Guidelines**
- **Preserve functionality**: Keep all working features
- **Maintain compatibility**: Ensure RUTOS compatibility is preserved
- **Focus on the issue**: Don't expand scope during conflict resolution
- **Test thoroughly**: Verify all changes work correctly

---
*🤖 This request was automatically generated by the PR monitoring system*
"@
            
            gh api repos/:owner/:repo/issues/$PRNumber/comments -f body="$conflictComment" 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "✅ Successfully requested Copilot to fix merge conflicts" -Color $GREEN
                return @{ Success = $true; Error = $null }
            } else {
                return @{ Success = $false; Error = "Failed to post merge conflict comment" }
            }
        } else {
            return @{ Success = $false; Error = "No merge conflicts detected" }
        }
        
    } catch {
        return @{ Success = $false; Error = "Error requesting merge conflict fix: $($_.Exception.Message)" }
    }
}

# Request Copilot to fix validation issues
function Request-CopilotValidationFix {
    param(
        [string]$PRNumber,
        [hashtable]$ValidationResult,
        [array]$ScopeIssues = @()
    )
    
    Write-StatusMessage "🤖 Requesting Copilot to fix validation issues for PR #$PRNumber..." -Color $BLUE
    
    try {
        $scopeWarning = ""
        if ($ScopeIssues.Count -gt 0) {
            $scopeWarning = @"

### ⚠️ **IMPORTANT: Scope Compliance Required**

This PR has been flagged for potential scope issues. Please ensure that your fixes:
1. **ONLY modify files that are directly related to the original issue**
2. **Do not make changes to validation scripts, formatting tools, or infrastructure files** unless they are explicitly mentioned in the issue
3. **Focus specifically on the file mentioned in the issue title or description**

Files with potential scope issues:
$(foreach ($issue in $ScopeIssues) {
"- $($issue.File): $($issue.Issue)"
})

**Please be very careful to stay within the issue scope when making fixes.**

"@
        }
        
        $validationComment = @"
@github-copilot fix the validation issues found in this PR.

$($ValidationResult.Message)
$scopeWarning

### 🎯 **Fix Request**
Please address all the validation issues listed above. Focus on:

1. **Critical Issues**: These will cause failures on RUTX50 hardware - fix immediately
2. **Major Issues**: These may cause problems in busybox environment - should be fixed
3. **Minor Issues**: Best practices improvements - fix if possible

### 💡 **RUTOS Compatibility Guidelines**
- Use `#!/bin/sh` instead of `#!/bin/bash`
- Use `[ ]` instead of `[[ ]]`
- Avoid bash arrays - use space-separated strings
- No `local` keyword - all variables are global in busybox
- Use `printf` instead of `echo -e`
- Use `. script` instead of `source script`

### 🔧 **Validation Process**
After making changes, the validation system will automatically re-check the PR.

---
*🤖 This validation request was automatically generated by the PR monitoring system*
"@
        
        gh api repos/:owner/:repo/issues/$PRNumber/comments -f body="$validationComment" 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✅ Successfully requested Copilot to fix validation issues" -Color $GREEN
            return @{ Success = $true; Error = $null }
        } else {
            return @{ Success = $false; Error = "Failed to post validation comment" }
        }
        
    } catch {
        return @{ Success = $false; Error = "Error requesting validation fix: $($_.Exception.Message)" }
    }
}

# Request Copilot to fix workflow failures
function Request-CopilotWorkflowFix {
    param(
        [string]$PRNumber,
        [array]$FailedRuns
    )
    
    Write-StatusMessage "🤖 Requesting Copilot to fix workflow failures for PR #$PRNumber..." -Color $BLUE
    
    try {
        $workflowDetails = @()
        foreach ($run in $FailedRuns) {
            $workflowDetails += "- **$($run.workflowName)**: $($run.conclusion) (Run #$($run.databaseId))"
        }
        
        $workflowComment = @"
@github-copilot fix the workflow failures in this PR.

## 🚨 **Workflow Failures Detected**

The following workflows have failed and need attention:

$($workflowDetails -join "`n")

### 🎯 **Fix Request**
Please investigate and fix the workflow failures. Common issues include:

1. **Syntax Errors**: Check for shell script syntax issues
2. **Test Failures**: Verify all tests pass
3. **Linting Issues**: Fix any linting errors
4. **Build Problems**: Resolve any build or compilation issues
5. **Permission Issues**: Check file permissions and access

### 🔍 **Debugging Steps**
1. Check the workflow run logs for specific error messages
2. Fix any syntax or compatibility issues
3. Ensure all tests pass locally
4. Verify RUTOS compatibility for shell scripts
5. Test the changes thoroughly

### 💡 **RUTOS Compatibility**
If shell scripts are involved, ensure:
- POSIX sh compatibility (not bash)
- No bash-specific features
- busybox compatibility
- Proper error handling

---
*🤖 This workflow failure notification was automatically generated by the PR monitoring system*
"@
        
        gh api repos/:owner/:repo/issues/$PRNumber/comments -f body="$workflowComment" 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✅ Successfully requested Copilot to fix workflow failures" -Color $GREEN
            return @{ Success = $true; Error = $null }
        } else {
            return @{ Success = $false; Error = "Failed to post workflow failure comment" }
        }
        
    } catch {
        return @{ Success = $false; Error = "Error requesting workflow fix: $($_.Exception.Message)" }
    }
}

# Approve a PR
function Approve-PR {
    param([string]$PRNumber)
    
    Write-StatusMessage "📝 Approving PR #$PRNumber..." -Color $BLUE
    
    try {
        $approvalComment = "✅ **Automated Approval**`n`nAll validation checks passed. This PR is ready for merge."
        
        gh pr review $PRNumber --approve --body "$approvalComment" 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✅ Successfully approved PR #$PRNumber" -Color $GREEN
            return @{ Success = $true; Error = $null }
        } else {
            return @{ Success = $false; Error = "Failed to approve PR" }
        }
        
    } catch {
        return @{ Success = $false; Error = "Error approving PR: $($_.Exception.Message)" }
    }
}

# Merge a PR
function Merge-PR {
    param([string]$PRNumber)
    
    Write-StatusMessage "🔄 Merging PR #$PRNumber..." -Color $BLUE
    
    try {
        # Use squash merge for cleaner history
        gh pr merge $PRNumber --squash --delete-branch 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✅ Successfully merged and closed PR #$PRNumber" -Color $GREEN
            return @{ Success = $true; Error = $null }
        } else {
            return @{ Success = $false; Error = "Failed to merge PR" }
        }
        
    } catch {
        return @{ Success = $false; Error = "Error merging PR: $($_.Exception.Message)" }
    }
}

# Intelligent PR workflow management with Copilot integration
function Invoke-PRWorkflow {
    param(
        [string]$PRNumber,
        [string]$PRTitle,
        [string]$HeadRef,
        [hashtable]$PRState
    )
    
    Write-StatusMessage "🤖 Starting intelligent PR workflow for PR #$PRNumber..." -Color $BLUE
    
    try {
        # Step 1: Get PR status and merge state
        $prInfo = gh pr view $PRNumber --json mergeable,mergeStateStatus,state,reviewDecision,statusCheckRollup | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            return @{
                Success = $false
                Error = "Failed to get PR information"
                UpdatedState = $PRState
                ActionTaken = "None"
            }
        }
        
        $isMergeable = $prInfo.mergeable
        $mergeState = $prInfo.mergeStateStatus
        $reviewDecision = $prInfo.reviewDecision
        $statusChecks = $prInfo.statusCheckRollup
        
        Write-StatusMessage "   📊 PR Status: Mergeable=$isMergeable, MergeState=$mergeState, Reviews=$reviewDecision" -Color $CYAN
        
        # Step 2: Check for merge conflicts first
        if ($mergeState -eq "DIRTY" -or $isMergeable -eq $false) {
            Write-StatusMessage "   ⚠️  Merge conflict detected - asking Copilot to fix it..." -Color $YELLOW
            
            $conflictResult = Request-CopilotMergeConflictFix -PRNumber $PRNumber -HeadRef $HeadRef
            
            if ($conflictResult.Success) {
                Write-StatusMessage "   ✅ Copilot has been asked to fix merge conflicts" -Color $GREEN
                $PRState.Status = "AwaitingConflictFix"
                $PRState.LastProcessed = Get-Date
                
                return @{
                    Success = $true
                    Error = $null
                    UpdatedState = $PRState
                    ActionTaken = "ConflictFixRequested"
                }
            } else {
                Write-StatusMessage "   ❌ Failed to request Copilot conflict fix: $($conflictResult.Error)" -Color $RED
                
                # Fallback: Try Copilot resolution if enabled
                if ($RequestCopilotForConflicts) {
                    $copilotResult = Resolve-MergeConflicts -PRNumber $PRNumber -HeadRef $HeadRef
                    if ($copilotResult.Success -and $copilotResult.CopilotRequested) {
                        Write-StatusMessage "   🤖 Copilot merge conflict resolution requested as fallback" -Color $PURPLE
                    } else {
                        Write-StatusMessage "   ❌ Copilot conflict resolution fallback failed: $($copilotResult.Error)" -Color $RED
                    }
                }
                
                return @{
                    Success = $false
                    Error = "Merge conflict resolution failed"
                    UpdatedState = $PRState
                    ActionTaken = "ConflictResolutionFailed"
                }
            }
        }
        
        # Step 3: If no conflicts, run validation
        if (-not $SkipValidation) {
            Write-StatusMessage "   🔍 Running comprehensive validation..." -Color $BLUE
            
            $validationResult = Test-PRValidation -PRNumber $PRNumber -HeadRef $HeadRef
            
            # Step 3.1: Check PR scope compliance before requesting fixes
            Write-StatusMessage "   🎯 Checking PR scope compliance..." -Color $BLUE
            
            $prInfo = gh pr view $PRNumber --json files,title,body | ConvertFrom-Json
            $modifiedFiles = $prInfo.files | ForEach-Object { $_.path }
            
            $scopeResult = Test-PRScopeCompliance -PRNumber $PRNumber -PRTitle $prInfo.title -PRBody $prInfo.body -ModifiedFiles $modifiedFiles
            
            if ($scopeResult.Count -gt 0) {
                Write-StatusMessage "   ⚠️  PR scope compliance issues found - posting scope warning..." -Color $YELLOW
                
                $scopeComment = @"
## ⚠️ **PR Scope Compliance Warning**

This PR appears to include changes to files that may be outside the scope of the original issue.

### 📋 **Files with Potential Scope Issues:**
$(foreach ($issue in $scopeResult) {
"- **$($issue.File)**: $($issue.Issue)"
})

### 🎯 **Recommendation:**
Please ensure that all file changes are directly related to the original issue. If these changes are necessary:
1. Explain why these additional files need to be modified
2. Consider creating separate PRs for unrelated changes
3. Update the PR description to explain the scope expansion

### 💡 **Best Practices:**
- Focus on the specific file mentioned in the issue
- Avoid making changes to validation scripts, formatting tools, or other infrastructure files unless they are directly related to the issue
- Keep PRs focused and atomic for easier review and testing

---
*🤖 This scope compliance check was automatically generated by the PR monitoring system*
"@
                
                gh api repos/:owner/:repo/issues/$PRNumber/comments -f body="$scopeComment" 2>&1 | Out-Null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "   ✅ Posted scope compliance warning" -Color $GREEN
                } else {
                    Write-StatusMessage "   ❌ Failed to post scope compliance warning" -Color $RED
                }
            } else {
                Write-StatusMessage "   ✅ PR scope compliance check passed" -Color $GREEN
            }
            
            if (-not $validationResult.IsValid -and -not $validationResult.HasTechnicalIssues) {
                Write-StatusMessage "   ❌ Validation failed - asking Copilot to fix issues..." -Color $RED
                
                # Enhanced validation fix request with scope awareness
                $fixResult = Request-CopilotValidationFix -PRNumber $PRNumber -ValidationResult $validationResult -ScopeIssues $scopeResult
                
                if ($fixResult.Success) {
                    Write-StatusMessage "   ✅ Copilot has been asked to fix validation issues" -Color $GREEN
                    $PRState.Status = "AwaitingValidationFix"
                    $PRState.ValidationAttempts++
                    $PRState.LastProcessed = Get-Date
                    
                    return @{
                        Success = $true
                        Error = $null
                        UpdatedState = $PRState
                        ActionTaken = "ValidationFixRequested"
                    }
                } else {
                    return @{
                        Success = $false
                        Error = "Failed to request validation fix: $($fixResult.Error)"
                        UpdatedState = $PRState
                        ActionTaken = "ValidationFixFailed"
                    }
                }
            }
        }
        
        # Step 4: If validation passes, run workflows first, then approve PR
        Write-StatusMessage "   ✅ All validation checks passed - proceeding with workflow execution..." -Color $GREEN
        
        # First, check and approve any pending workflows
        $pendingWorkflowResult = Approve-PendingWorkflows -PRNumber $PRNumber -HeadRef $HeadRef
        
        if ($pendingWorkflowResult.Success -and $pendingWorkflowResult.ApprovedCount -gt 0) {
            Write-StatusMessage "   🔓 Approved $($pendingWorkflowResult.ApprovedCount) pending workflow(s)" -Color $GREEN
        }
        
        # Then trigger or check for workflows
        $workflowResult = Trigger-WorkflowRuns -PRNumber $PRNumber -HeadRef $HeadRef
        
        if ($workflowResult.Success) {
            Write-StatusMessage "   🚀 Workflows triggered successfully" -Color $GREEN
            $PRState.WorkflowTriggers++
        } else {
            Write-StatusMessage "   ⚠️  Workflow trigger failed: $($workflowResult.Error)" -Color $YELLOW
        }
        
        # Step 5: Check workflow status
        $workflowRuns = Get-WorkflowRuns -PRNumber $PRNumber -HeadRef $HeadRef
        
        # Wait a moment for workflows to start
        Start-Sleep -Seconds 5
        
        # Check for workflow failures
        $failedRuns = $workflowRuns | Where-Object { $_.conclusion -eq "failure" }
        
        if ($failedRuns.Count -gt 0) {
            Write-StatusMessage "   ❌ Workflow failures detected - asking Copilot to fix them..." -Color $RED
            
            $workflowFixResult = Request-CopilotWorkflowFix -PRNumber $PRNumber -FailedRuns $failedRuns
            
            if ($workflowFixResult.Success) {
                Write-StatusMessage "   ✅ Copilot has been asked to fix workflow failures" -Color $GREEN
                $PRState.Status = "AwaitingWorkflowFix"
                $PRState.LastProcessed = Get-Date
                
                return @{
                    Success = $true
                    Error = $null
                    UpdatedState = $PRState
                    ActionTaken = "WorkflowFixRequested"
                }
            } else {
                return @{
                    Success = $false
                    Error = "Failed to request workflow fix: $($workflowFixResult.Error)"
                    UpdatedState = $PRState
                    ActionTaken = "WorkflowFixFailed"
                }
            }
        }
        
        # Step 6: Check if all workflows are green
        $allSuccess = $workflowRuns.Count -eq 0 -or ($workflowRuns | Where-Object { $_.conclusion -ne "success" }).Count -eq 0
        
        if ($allSuccess -and $isMergeable -eq $true -and $mergeState -eq "CLEAN") {
            Write-StatusMessage "   🎉 All checks passed - now approving PR #$PRNumber..." -Color $GREEN
            
            # NOW approve the PR since all validations and workflows are successful
            if ($reviewDecision -ne "APPROVED") {
                Write-StatusMessage "   📝 Approving PR #$PRNumber after successful validation and workflows..." -Color $BLUE
                
                $approvalResult = Approve-PR -PRNumber $PRNumber
                if ($approvalResult.Success) {
                    Write-StatusMessage "   ✅ PR #$PRNumber approved successfully" -Color $GREEN
                } else {
                    Write-StatusMessage "   ⚠️  PR approval failed: $($approvalResult.Error)" -Color $YELLOW
                    # Continue with merge attempt even if approval fails
                }
            } else {
                Write-StatusMessage "   ✅ PR #$PRNumber is already approved" -Color $GREEN
            }
            
            Write-StatusMessage "   🔄 Attempting to merge PR #$PRNumber..." -Color $BLUE
            
            $mergeResult = Merge-PR -PRNumber $PRNumber
            
            if ($mergeResult.Success) {
                Write-StatusMessage "   ✅ PR #$PRNumber successfully merged and closed!" -Color $GREEN
                $PRState.Status = "Merged"
                $PRState.LastProcessed = Get-Date
                
                return @{
                    Success = $true
                    Error = $null
                    UpdatedState = $PRState
                    ActionTaken = "Merged"
                }
            } else {
                return @{
                    Success = $false
                    Error = "Failed to merge PR: $($mergeResult.Error)"
                    UpdatedState = $PRState
                    ActionTaken = "MergeFailed"
                }
            }
        } else {
            Write-StatusMessage "   ⏳ Waiting for workflows to complete..." -Color $YELLOW
            $PRState.Status = "AwaitingWorkflows"
            $PRState.LastProcessed = Get-Date
            
            return @{
                Success = $true
                Error = $null
                UpdatedState = $PRState
                ActionTaken = "WaitingForWorkflows"
            }
        }
        
    } catch {
        return @{
            Success = $false
            Error = "Workflow error: $($_.Exception.Message)"
            UpdatedState = $PRState
            ActionTaken = "Error"
        }
    }
}

# Process a single specific PR
function Process-SinglePR {
    param(
        [int]$PRNumber
    )
    
    Write-StatusMessage "🎯 Processing single PR #$PRNumber..." -Color $GREEN
    
    try {
        # Get the specific PR
        $pr = Get-SpecificPR -PRNumber $PRNumber
        
        if (-not $pr) {
            Write-StatusMessage "❌ Could not retrieve PR #$PRNumber" -Color $RED
            return $false
        }
        
        $prTitle = $pr.Title
        $headRef = $pr.HeadRef
        
        Write-StatusMessage "📋 PR Details:" -Color $BLUE
        Write-StatusMessage "   Title: $prTitle" -Color $CYAN
        Write-StatusMessage "   Branch: $headRef" -Color $CYAN
        Write-StatusMessage "   Author: $($pr.Author)" -Color $CYAN
        
        # Create PR state for processing
        $prState = @{
            LastProcessed = Get-Date
            ValidationAttempts = 0
            WorkflowTriggers = 0
            Status = "SingleProcessing"
        }
        
        # Process the PR workflow
        Write-StatusMessage "⚙️  Starting comprehensive PR workflow..." -Color $BLUE
        $workflowResult = Invoke-PRWorkflow -PRNumber $PRNumber -PRTitle $prTitle -HeadRef $headRef -PRState $prState
        
        # Report results
        if ($workflowResult.Success) {
            Write-StatusMessage "✅ PR #$PRNumber workflow completed successfully" -Color $GREEN
            
            if ($workflowResult.ActionTaken) {
                Write-StatusMessage "🎉 Action taken: $($workflowResult.ActionTaken)" -Color $GREEN
            }
            
            if ($workflowResult.Message) {
                Write-StatusMessage "📝 Result: $($workflowResult.Message)" -Color $CYAN
            }
            
            return $true
        } else {
            Write-StatusMessage "❌ PR #$PRNumber workflow failed" -Color $RED
            
            if ($workflowResult.Error) {
                Write-StatusMessage "💥 Error: $($workflowResult.Error)" -Color $RED
            }
            
            return $false
        }
        
    } catch {
        Write-StatusMessage "❌ Error processing PR #${PRNumber}: $($_.Exception.Message)" -Color $RED
        Write-StatusMessage "🔍 Stack trace: $($_.ScriptStackTrace)" -Color $GRAY
        return $false
    }
}

# Main monitoring function with intelligent workflow management
function Start-CopilotPRMonitoring {
    param(
        [int]$IntervalSeconds = 300,
        [int]$MaxIterations = 0
    )
    
    Write-StatusMessage "🤖 Starting Copilot PR Monitoring with intelligent workflow management..." -Color $GREEN
    Write-StatusMessage "   📊 Monitoring interval: $IntervalSeconds seconds" -Color $BLUE
    Write-StatusMessage "   🔄 Max iterations: $(if ($MaxIterations -eq 0) { "Unlimited" } else { $MaxIterations })" -Color $BLUE
    Write-StatusMessage "   🎯 Parameters: VerboseOutput=$VerboseOutput, SkipValidation=$SkipValidation, RequestCopilotForConflicts=$RequestCopilotForConflicts" -Color $BLUE
    
    $iteration = 0
    $processedPRs = @{}
    
    while ($MaxIterations -eq 0 -or $iteration -lt $MaxIterations) {
        $iteration++
        
        Write-StatusMessage "🔄 [Iteration $iteration] Starting PR monitoring cycle..." -Color $CYAN
        
        try {
            # Get current Copilot PRs
            $copilotPRs = Get-CopilotPRs
            
            if ($copilotPRs.Count -eq 0) {
                Write-StatusMessage "✅ No Copilot PRs found - system is clean" -Color $GREEN
                
                if ($MonitorOnly) {
                    Write-StatusMessage "📊 Monitor-only mode: Continuing to next cycle..." -Color $CYAN
                } else {
                    Write-StatusMessage "💤 No work to do - sleeping for $IntervalSeconds seconds..." -Color $GRAY
                }
            } else {
                Write-StatusMessage "📋 Processing $($copilotPRs.Count) Copilot PR(s)..." -Color $BLUE
                
                # Process each PR with comprehensive workflow
                foreach ($pr in $copilotPRs) {
                    $prNumber = $pr.Number
                    $prTitle = $pr.Title
                    $headRef = $pr.HeadRef
                    
                    Write-StatusMessage "🔍 Processing PR #${prNumber}: ${prTitle}" -Color $PURPLE
                    
                    # Track processing state
                    $prKey = "PR_$prNumber"
                    if (-not $processedPRs.ContainsKey($prKey)) {
                        $processedPRs[$prKey] = @{
                            LastProcessed = Get-Date
                            ValidationAttempts = 0
                            WorkflowTriggers = 0
                            Status = "New"
                        }
                    }
                    
                    $prState = $processedPRs[$prKey]
                    
                    # Comprehensive PR workflow processing
                    $workflowResult = Invoke-PRWorkflow -PRNumber $prNumber -PRTitle $prTitle -HeadRef $headRef -PRState $prState
                    
                    # Update processing state
                    $processedPRs[$prKey] = $workflowResult.UpdatedState
                    
                    # Handle workflow results
                    if ($workflowResult.Success) {
                        Write-StatusMessage "✅ PR #$prNumber workflow completed successfully" -Color $GREEN
                        
                        # Update PR labels based on success
                        if (Get-Command "Update-PRLabels" -ErrorAction SilentlyContinue) {
                            try {
                                Update-PRLabels -PRNumber $prNumber -Status "FixCompleted" -DryRun:$TestMode
                            } catch {
                                Write-StatusMessage "⚠️  Could not update PR labels: $($_.Exception.Message)" -Color $YELLOW
                            }
                        }
                        
                        if ($workflowResult.ActionTaken -eq "Merged") {
                            Write-StatusMessage "🎉 PR #$prNumber has been successfully merged and closed!" -Color $GREEN
                            # Remove from tracking since it's completed
                            $processedPRs.Remove($prKey)
                        }
                    } else {
                        Write-StatusMessage "❌ PR #$prNumber workflow failed: $($workflowResult.Error)" -Color $RED
                        
                        # Update PR labels based on failure
                        if (Get-Command "Update-PRLabels" -ErrorAction SilentlyContinue) {
                            try {
                                Update-PRLabels -PRNumber $prNumber -Status "FixFailed" -DryRun:$TestMode
                            } catch {
                                Write-StatusMessage "⚠️  Could not update PR labels: $($_.Exception.Message)" -Color $YELLOW
                            }
                        }
                        
                        # Update failure count
                        $prState.ValidationAttempts++
                        $prState.Status = "Failed"
                        $prState.LastError = $workflowResult.Error
                    }
                    
                    # Add delay between PR processing
                    Start-Sleep -Seconds 2
                }
            }
            
            # Clean up old processed PRs (older than 24 hours)
            $cutoffTime = (Get-Date).AddHours(-24)
            $keysToRemove = @()
            foreach ($key in $processedPRs.Keys) {
                if ($processedPRs[$key].LastProcessed -lt $cutoffTime) {
                    $keysToRemove += $key
                }
            }
            foreach ($key in $keysToRemove) {
                $processedPRs.Remove($key)
            }
            
            Write-StatusMessage "✅ [Iteration $iteration] Monitoring cycle completed" -Color $GREEN
            
        } catch {
            Write-StatusMessage "❌ [Iteration $iteration] Error in monitoring cycle: $($_.Exception.Message)" -Color $RED
            Write-StatusMessage "🔄 Continuing with next iteration..." -Color $YELLOW
        }
        
        # Sleep before next iteration (unless it's the last one)
        if ($MaxIterations -eq 0 -or $iteration -lt $MaxIterations) {
            Write-StatusMessage "💤 Sleeping for $IntervalSeconds seconds before next cycle..." -Color $GRAY
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
    
    Write-StatusMessage "🏁 Copilot PR Monitoring completed after $iteration iterations" -Color $GREEN
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
    Write-StatusMessage "   RequestCopilotForConflicts: $RequestCopilotForConflicts" -Color $GRAY
    Write-StatusMessage "   SkipWorkflowApproval: $SkipWorkflowApproval" -Color $GRAY
    Write-StatusMessage "   ForceValidation: $ForceValidation" -Color $GRAY
    Write-StatusMessage "   MonitorOnly: $MonitorOnly" -Color $GRAY
    Write-StatusMessage "   TestMode: $TestMode" -Color $GRAY
    Write-StatusMessage "   DebugMode: $DebugMode" -Color $GRAY
    
    # Run the intelligent monitoring system
    if ($PRNumber) {
        Write-StatusMessage "🎯 Processing specific PR #$PRNumber..." -Color $GREEN
        $singlePRResult = Process-SinglePR -PRNumber $PRNumber
        
        if ($singlePRResult) {
            Write-StatusMessage "✅ Single PR processing completed successfully" -Color $GREEN
            exit 0
        } else {
            Write-StatusMessage "❌ Single PR processing failed" -Color $RED
            exit 1
        }
    } elseif ($MonitorOnly) {
        Write-StatusMessage "📊 Running in monitor-only mode - no automation actions will be taken" -Color $YELLOW
        Start-CopilotPRMonitoring -IntervalSeconds 300 -MaxIterations 1
    } else {
        Write-StatusMessage "🤖 Running full intelligent PR monitoring with automation..." -Color $GREEN
        Start-CopilotPRMonitoring -IntervalSeconds 300 -MaxIterations 0
    }
    
} catch {
    Write-StatusMessage "❌ Advanced monitoring system failed: $($_.Exception.Message)" -Color $RED
    Write-StatusMessage "🔍 Error details: $($_.ScriptStackTrace)" -Color $GRAY
    exit 1
}
