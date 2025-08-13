# Cleanup Script for Issues and PRs
# Clean slate preparation for autonomous system

param(
    [switch]$DryRun = $false,
    [switch]$Force = $false
)

$RED = [ConsoleColor]::Red
$GREEN = [ConsoleColor]::Green
$YELLOW = [ConsoleColor]::Yellow
$BLUE = [ConsoleColor]::Blue
$CYAN = [ConsoleColor]::Cyan
$GRAY = [ConsoleColor]::Gray

function Write-ColorMessage {
    param([string]$Message, [ConsoleColor]$Color)
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorMessage "🧹 Repository Cleanup Script" $BLUE
Write-ColorMessage "================================" $BLUE

if ($DryRun) {
    Write-ColorMessage "🔍 DRY RUN MODE - No actual changes will be made" $YELLOW
} else {
    Write-ColorMessage "⚠️  LIVE MODE - Changes will be applied" $RED
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to proceed? (yes/no)"
        if ($confirm -ne "yes") {
            Write-ColorMessage "❌ Cleanup cancelled" $YELLOW
            exit 0
        }
    }
}

Write-ColorMessage "`n📋 Phase 1: Analyzing Issues and PRs..." $BLUE

# Get current issues and PRs
$openIssues = gh issue list --state open --json number,title | ConvertFrom-Json
$openPRs = gh pr list --state open --json number,title | ConvertFrom-Json

Write-ColorMessage "Current Open Issues: $($openIssues.Count)" $CYAN
Write-ColorMessage "Current Open PRs: $($openPRs.Count)" $CYAN

# Issues to close (old RUTOS compatibility issues)
$issuesToClose = @(
    @{Number=69; Reason="Superseded by autonomous system - test-azure-logging.sh issue"},
    @{Number=65; Reason="Superseded by autonomous system - log-shipper.sh issue"},
    @{Number=59; Reason="Superseded by autonomous system - pushover notification issue"}
)

# PRs to close (stale Copilot PRs)
$prsToClose = @(
    @{Number=70; Reason="Stale Copilot PR - conflicts or superseded"},
    @{Number=66; Reason="Stale Copilot PR - conflicts or superseded"}, 
    @{Number=60; Reason="Stale Copilot PR - conflicts or superseded"}
)

Write-ColorMessage "`n🎯 Phase 2: Issues Cleanup" $BLUE
Write-ColorMessage "Issues planned for closure: $($issuesToClose.Count)" $CYAN

foreach ($issue in $issuesToClose) {
    $issueNum = $issue.Number
    $reason = $issue.Reason
    
    # Check if issue still exists and is open
    $existingIssue = $openIssues | Where-Object { $_.number -eq $issueNum }
    
    if ($existingIssue) {
        Write-ColorMessage "📝 Issue #$issueNum`: $($existingIssue.title)" $YELLOW
        Write-ColorMessage "   Reason: $reason" $GRAY
        
        if (-not $DryRun) {
            # Add a final comment explaining closure
            $closeComment = @"
🧹 **Repository Cleanup - Issue Closure**

This issue is being closed as part of repository cleanup for the following reason:
**$reason**

## Current Status
- ✅ Autonomous conflict resolution system is now operational
- ✅ PR #72 was successfully resolved and merged autonomously
- ✅ Enhanced monitoring and automation systems are in place

## Next Steps
If this specific issue still needs attention, it will be automatically detected and handled by:
- 🤖 Autonomous-copilot workflow (runs every 10 minutes)
- 🔍 Enhanced monitoring scripts with comprehensive error handling
- 🎯 Improved Copilot PR detection and processing

*Closed automatically by repository cleanup script*
"@

            try {
                gh issue comment $issueNum --body $closeComment
                gh issue close $issueNum --reason "completed"
                Write-ColorMessage "✅ Closed issue #$issueNum" $GREEN
            } catch {
                Write-ColorMessage "❌ Failed to close issue #$issueNum`: $($_)" $RED
            }
        } else {
            Write-ColorMessage "   [DRY RUN] Would close issue #$issueNum" $CYAN
        }
    } else {
        Write-ColorMessage "ℹ️  Issue #$issueNum not found or already closed" $GRAY
    }
}

Write-ColorMessage "`n🎯 Phase 3: PRs Cleanup" $BLUE  
Write-ColorMessage "PRs planned for closure: $($prsToClose.Count)" $CYAN

foreach ($pr in $prsToClose) {
    $prNum = $pr.Number
    $reason = $pr.Reason
    
    # Check if PR still exists and is open
    $existingPR = $openPRs | Where-Object { $_.number -eq $prNum }
    
    if ($existingPR) {
        Write-ColorMessage "📝 PR #$prNum`: $($existingPR.title)" $YELLOW
        Write-ColorMessage "   Reason: $reason" $GRAY
        
        if (-not $DryRun) {
            # Add a final comment explaining closure
            $closeComment = @"
🧹 **Repository Cleanup - PR Closure**

This PR is being closed as part of repository cleanup for the following reason:
**$reason**

## Current Status
- ✅ Autonomous conflict resolution system is operational
- ✅ Enhanced Copilot PR detection and processing is active
- ✅ Repository has been cleaned for fresh autonomous operation

## Autonomous System Features
- 🔄 Runs every 10 minutes via GitHub Actions
- 🤖 Automatically detects and resolves merge conflicts
- 🎯 Enhanced PR detection covers all Copilot patterns
- 📊 Comprehensive monitoring and error handling

If the changes in this PR are still needed, the autonomous system will:
1. Create new issues automatically when problems are detected
2. Generate fresh Copilot PRs with current best practices
3. Handle conflicts and merging autonomously

*Closed automatically by repository cleanup script*
"@

            try {
                gh pr comment $prNum --body $closeComment
                gh pr close $prNum
                Write-ColorMessage "✅ Closed PR #$prNum" $GREEN
            } catch {
                Write-ColorMessage "❌ Failed to close PR #$prNum`: $($_)" $RED
            }
        } else {
            Write-ColorMessage "   [DRY RUN] Would close PR #$prNum" $CYAN
        }
    } else {
        Write-ColorMessage "ℹ️  PR #$prNum not found or already closed" $GRAY
    }
}

Write-ColorMessage "`n📊 Phase 4: Final Status" $BLUE

if (-not $DryRun) {
    # Get updated counts
    $finalOpenIssues = gh issue list --state open --json number | ConvertFrom-Json
    $finalOpenPRs = gh pr list --state open --json number | ConvertFrom-Json
    
    Write-ColorMessage "Final Open Issues: $($finalOpenIssues.Count)" $GREEN
    Write-ColorMessage "Final Open PRs: $($finalOpenPRs.Count)" $GREEN
    
    if ($finalOpenIssues.Count -eq 0 -and $finalOpenPRs.Count -eq 0) {
        Write-ColorMessage "`n🎉 CLEAN SLATE ACHIEVED! 🎉" $GREEN
        Write-ColorMessage "✅ All issues and PRs have been cleaned up" $GREEN
        Write-ColorMessage "✅ Repository is ready for autonomous operation" $GREEN
        Write-ColorMessage "✅ Autonomous-copilot workflow will handle future issues" $GREEN
    } else {
        Write-ColorMessage "`nRemaining open items:" $YELLOW
        if ($finalOpenIssues.Count -gt 0) {
            Write-ColorMessage "Issues: $($finalOpenIssues.Count)" $YELLOW
        }
        if ($finalOpenPRs.Count -gt 0) {
            Write-ColorMessage "PRs: $($finalOpenPRs.Count)" $YELLOW
        }
    }
} else {
    Write-ColorMessage "🔍 Dry run completed - no changes made" $CYAN
    Write-ColorMessage "Run with -Force to apply changes automatically" $CYAN
    Write-ColorMessage "Or run without -DryRun for interactive mode" $CYAN
}

Write-ColorMessage "`n🎯 Next Steps After Cleanup:" $BLUE
Write-ColorMessage "1. 🤖 Autonomous-copilot workflow will continue monitoring" $CYAN
Write-ColorMessage "2. 🔍 Enhanced monitoring scripts are ready for use" $CYAN  
Write-ColorMessage "3. 🎯 Any new issues will be detected and handled automatically" $CYAN
Write-ColorMessage "4. 📊 Clean slate allows for better tracking of future issues" $CYAN

Write-ColorMessage "`n✅ Cleanup script completed!" $GREEN
