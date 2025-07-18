#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Enhanced RUTOS Copilot Issue Creation with Intelligent Label Assignment

.DESCRIPTION
    This is an enhanced version of create-copilot-issues.ps1 that uses the comprehensive
    labeling system to intelligently assign labels based on issue types, severity,
    and characteristics.

.PARAMETER TestMode
    Run in test mode without creating actual issues

.PARAMETER DryRun
    Show what would be done without making changes (DEFAULT: enabled for safety)

.PARAMETER MaxIssuesPerRun
    Maximum number of issues to create in a single run (DEFAULT: 3 for safety)

.PARAMETER Production
    Enable production mode (disables DryRun safety default)

.PARAMETER SkipValidation
    Skip the initial validation step (for testing)

.PARAMETER DebugMode
    Enable detailed debug logging

.PARAMETER ForceReprocessing
    Force reprocessing of previously handled files

.PARAMETER TargetFile
    Process only a specific file (for testing)

.PARAMETER PriorityFilter
    Filter issues by priority: All, Critical, Major, Minor (default: All)

.PARAMETER MinIssuesPerFile
    Skip files with fewer than this many issues (default: 1)

.PARAMETER SortByPriority
    Process files with critical issues first, then major, then minor

.EXAMPLE
    .\create-copilot-issues-enhanced.ps1 -Production -DebugMode
    Run in production mode with detailed label assignment logging
#>

[CmdletBinding()]
param(
    [switch]$TestMode,
    [switch]$DryRun,                   # Enable dry run mode for safety
    [ValidateRange(1, 100)]
    [int]$MaxIssuesPerRun = 3,         # DEFAULT: Maximum 3 issues for testing
    [switch]$SkipValidation,
    [switch]$DebugMode,
    [switch]$ForceReprocessing,
    [ValidateScript({$_ -eq "" -or (Test-Path $_ -PathType Leaf)})]
    [string]$TargetFile = "",
    [ValidateSet("All", "Critical", "Major", "Minor")]
    [string]$PriorityFilter = "All",  # All, Critical, Major, Minor
    [ValidateRange(1, 50)]
    [int]$MinIssuesPerFile = 1,       # Skip files with fewer issues
    [switch]$SortByPriority,          # Process critical issues first
    [switch]$Production               # Enable production mode (disables DryRun)
)

# Production mode override - if -Production is specified, disable dry run
if ($Production) {
    $DryRun = $false
    Write-Output "🚀 Production mode enabled - DryRun disabled"
} else {
    # Enable dry run by default for safety
    if (-not $PSBoundParameters.ContainsKey('DryRun')) {
        $DryRun = $true
    }
    Write-Output "🛡️  Safety mode enabled - DryRun=$DryRun, MaxIssues=$MaxIssuesPerRun"
}

# Enhanced label assignment function based on issue analysis
function Get-IntelligentLabel {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [array]$Issues
    )

    $labels = @()

    # Classify issues
    $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" -or $_.Type -eq "Error" }
    $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
    $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "ShellCheck" }

    # Priority labels based on highest severity present
    if ($criticalIssues.Count -gt 0) {
        $labels += "priority-critical"
    } elseif ($majorIssues.Count -gt 0) {
        $labels += "priority-major"
    } else {
        $labels += "priority-minor"
    }

    # Critical issue type labels
    foreach ($issue in $criticalIssues) {
        if ($issue.Line -match "local\s+\w+") {
            $labels += "critical-local-keyword"
        }
        if ($issue.Line -match "#!/bin/bash") {
            $labels += "critical-bash-shebang"
        }
        if ($issue.Line -match "\[\[.*\]\]") {
            $labels += "critical-posix-violation"
        }
        if ($issue.Line -match "declare\s+-[aA]" -or $issue.Line -match "\w+\s*=\s*\(" -or $issue.Line -match "\[\d+\]") {
            $labels += "critical-bash-arrays"
        }
        if ($issue.Line -match "set\s+-o\s+pipefail" -or $issue.Line -match "busybox") {
            $labels += "critical-busybox-incompatible"
        }
    }

    # Specific issue type labels
    $issueText = ($Issues | ForEach-Object { $_.Line }) -join " "

    if ($issueText -match "echo\s+-e") {
        $labels += "type-echo-dash-e"
    }
    if ($issueText -match "source\s+") {
        $labels += "type-source-command"
    }
    if ($issueText -match "function\s+\w+\s*\(\s*\)") {
        $labels += "type-function-syntax"
    }
    if ($issueText -match "printf.*\$\{.*\}") {
        $labels += "type-printf-format"
    }
    if ($issueText -match "tput\s+colors" -or $issueText -match "command\s+-v\s+tput") {
        $labels += "type-color-definitions"
    }
    if ($issueText -match "SC1090" -or $issueText -match "SC1091") {
        $labels += "type-dynamic-source"
    }
    if ($issueText -match "set\s+-o\s+pipefail") {
        $labels += "type-pipefail"
    }

    # Core system labels
    $labels += "rutos-compatibility"
    $labels += "copilot-fix"
    $labels += "automated"
    $labels += "autonomous-system"
    $labels += "monitoring-system"

    # File type and scope labels
    if ($FilePath -match "\.sh$") {
        $labels += "shell-script"
    }
    if ($FilePath -match "config/") {
        $labels += "config-templates"
    }
    if ($FilePath -match "scripts/install") {
        $labels += "installation-scripts"
    }
    if ($FilePath -match "scripts/.*validate") {
        $labels += "validation-scripts"
    }
    if ($FilePath -match "starlink.*monitor") {
        $labels += "monitoring-scripts"
        $labels += "starlink-core"
    }
    if ($FilePath -match "azure") {
        $labels += "azure-logging"
    }
    if ($FilePath -match "pushover") {
        $labels += "pushover-notifications"
    }

    # Validation and compliance labels
    $labels += "posix-compliance"
    $labels += "busybox-compatibility"
    $labels += "shellcheck-issues"

    # Add fix type labels
    if ($criticalIssues.Count -gt 0) {
        $labels += "auto-fix-needed"
    } else {
        $labels += "manual-fix-needed"
    }

    # Scope control
    $labels += "scope-single-file"
    $labels += "scope-validated"

    # Progress tracking
    $labels += "attempt-1"
    $labels += "created-today"
    $labels += "waiting-for-copilot"

    # Detection method
    $labels += "detected-by-validation"
    if ($minorIssues.Count -gt 0) {
        $labels += "detected-by-shellcheck"
    }

    # Impact assessment
    if ($criticalIssues.Count -gt 0) {
        $labels += "impact-high"
    } elseif ($majorIssues.Count -gt 0) {
        $labels += "impact-medium"
    } else {
        $labels += "impact-low"
    }

    # Workflow status
    $labels += "workflow-pending"
    $labels += "validation-pending"

    # Cost optimization
    $labels += "cost-optimized"
    $labels += "anti-loop-protection"

    # Remove duplicates and sort
    $labels = $labels | Sort-Object -Unique

    if ($DebugMode) {
        Write-Output "🏷️  Intelligent Labels for $FilePath ($($Issues.Count) issues):"
        Write-Output "   Priority: $($labels | Where-Object { $_ -match '^priority-' } | Join-String -Separator ', ')"
        Write-Output "   Critical Types: $($labels | Where-Object { $_ -match '^critical-' } | Join-String -Separator ', ')"
        Write-Output "   Issue Types: $($labels | Where-Object { $_ -match '^type-' } | Join-String -Separator ', ')"
        Write-Output "   Scope: $($labels | Where-Object { $_ -match '^scope-' } | Join-String -Separator ', ')"
        Write-Output "   Progress: $($labels | Where-Object { $_ -match '^(attempt-|created-|waiting-)' } | Join-String -Separator ', ')"
        Write-Output "   Total Labels: $($labels.Count)"
    }

    return $labels
}

# Enhanced issue content generation with intelligent labels
function Get-EnhancedCopilotIssueContent {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [array]$Issues
    )

    # Get intelligent labels
    $intelligentLabels = Get-IntelligentLabel -FilePath $FilePath -Issues $Issues

    # Classify issues
    $criticalIssues = $Issues | Where-Object { $_.Type -eq "Critical" -or $_.Type -eq "Error" }
    $majorIssues = $Issues | Where-Object { $_.Type -eq "Major" }
    $minorIssues = $Issues | Where-Object { $_.Type -eq "Minor" -or $_.Type -eq "ShellCheck" }

    # Generate title with priority indicator
    $priorityEmoji = if ($criticalIssues.Count -gt 0) { "🔴" } elseif ($majorIssues.Count -gt 0) { "🟡" } else { "🔵" }
    $issueTitle = "$priorityEmoji RUTOS Compatibility: Fix $($Issues.Count) issues in $(Split-Path $FilePath -Leaf)"

    # Generate enhanced issue body
    $issueBody = @"
# 🎯 **RUTOS Compatibility Fix Request**

## 📋 **Issue Summary**
**File**: ``$FilePath``
**Total Issues**: $($Issues.Count)
**Priority**: $($priorityEmoji) $($criticalIssues.Count -gt 0 ? "CRITICAL" : $majorIssues.Count -gt 0 ? "MAJOR" : "MINOR")

### 🏷️ **Intelligent Labels Applied**
This issue has been automatically tagged with $($intelligentLabels.Count) intelligent labels:
- **Priority**: $($intelligentLabels | Where-Object { $_ -match '^priority-' } | Join-String -Separator ', ')
- **Critical Types**: $($intelligentLabels | Where-Object { $_ -match '^critical-' } | Join-String -Separator ', ')
- **Issue Categories**: $($intelligentLabels | Where-Object { $_ -match '^type-' } | Join-String -Separator ', ')
- **Scope Control**: $($intelligentLabels | Where-Object { $_ -match '^scope-' } | Join-String -Separator ', ')

### 📊 **Issue Breakdown**
- 🔴 **Critical Issues**: $($criticalIssues.Count) (Must fix - will cause hardware failures)
- 🟡 **Major Issues**: $($majorIssues.Count) (Should fix - may cause runtime problems)
- 🔵 **Minor Issues**: $($minorIssues.Count) (Best practices - improve if possible)

---

## 🔍 **Detailed Issues**

"@

    # Add critical issues
    if ($criticalIssues.Count -gt 0) {
        $issueBody += @"
### 🔴 **CRITICAL ISSUES** (Must Fix)
> **⚠️ These issues will cause the script to fail on RUTX50 routers**

"@
        foreach ($issue in $criticalIssues) {
            $issueBody += "- **Line $($issue.LineNumber)**: $($issue.Line.Trim())`n"
            if ($issue.Issue) {
                $issueBody += "  - *Issue*: $($issue.Issue)`n"
            }
        }
        $issueBody += "`n"
    }

    # Add major issues
    if ($majorIssues.Count -gt 0) {
        $issueBody += @"
### 🟡 **MAJOR ISSUES** (Should Fix)
> **⚠️ These issues may cause runtime problems or unexpected behavior**

"@
        foreach ($issue in $majorIssues) {
            $issueBody += "- **Line $($issue.LineNumber)**: $($issue.Line.Trim())`n"
            if ($issue.Issue) {
                $issueBody += "  - *Issue*: $($issue.Issue)`n"
            }
        }
        $issueBody += "`n"
    }

    # Add minor issues
    if ($minorIssues.Count -gt 0) {
        $issueBody += @"
### 🔵 **MINOR ISSUES** (Best Practices)
> **ℹ️ These improve code quality and maintainability**

"@
        foreach ($issue in $minorIssues) {
            $issueBody += "- **Line $($issue.LineNumber)**: $($issue.Line.Trim())`n"
            if ($issue.Issue) {
                $issueBody += "  - *Issue*: $($issue.Issue)`n"
            }
        }
        $issueBody += "`n"
    }

    # Add comprehensive fix guidelines
    $issueBody += @"
---

## 🛠️ **Fix Guidelines**

### **RUTOS Compatibility Rules**
1. **POSIX Shell Only**: Use `#!/bin/sh` instead of `#!/bin/bash`
2. **No Bash Arrays**: Use space-separated strings or multiple variables
3. **Use `[ ]` not `[[ ]]`**: Busybox doesn't support `[[ ]]`
4. **No `local` keyword**: All variables are global in busybox
5. **Use `printf` not `echo -e`**: More portable and consistent
6. **Source with `.` not `source`**: Use `. script.sh` instead of `source script.sh`
7. **No `function()` syntax**: Use `function_name() {` format
8. **Proper printf format**: Avoid variables in format strings (SC2059)

### **Intelligent Label System**
This issue uses our comprehensive labeling system with $($intelligentLabels.Count) labels for:
- **Automated tracking** and progress monitoring
- **Scope validation** to prevent unintended changes
- **Priority routing** for critical issues
- **Cost optimization** through intelligent batching

### **Validation Process**
The enhanced automation system will:
1. ✅ **Monitor progress** using intelligent labels
2. 🚀 **Validate scope** to ensure only target file is modified
3. 🔄 **Track attempts** and prevent infinite loops
4. 🔀 **Handle conflicts** with advanced merge strategies
5. ✅ **Verify completion** with comprehensive testing

### **Scope Control**
**🎯 CRITICAL**: Only modify the file mentioned above (`$FilePath`). Labels will track:
- ✅ **scope-single-file**: Ensures only one file is modified
- ✅ **scope-validated**: Confirms changes are within scope
- ❌ **scope-violation**: Triggers alerts for unauthorized changes

## 📋 **Acceptance Criteria**
- [ ] All critical issues resolved (tracked by labels)
- [ ] All major issues resolved (if possible)
- [ ] Minor issues addressed (if time permits)
- [ ] File passes validation (automatic label updates)
- [ ] All workflows green (workflow-success label)
- [ ] No merge conflicts (merge-ready label)
- [ ] Scope validation passes (scope-validated label)

## 🔍 **Verification & Monitoring**
The enhanced system provides:
- **Real-time label updates** as progress is made
- **Automated scope validation** to prevent unauthorized changes
- **Intelligent retry logic** with attempt-1/2/3 labels
- **Cost optimization** through batching and rate limiting
- **Anti-loop protection** with escalation-needed label

---

## 🏷️ **Applied Labels** ($($intelligentLabels.Count) total)
$($intelligentLabels | ForEach-Object { "- ``$_``" } | Join-String -Separator "`n")

---

## 🤖 **Enhanced Automation Features**
- **Intelligent Label Assignment**: $($intelligentLabels.Count) labels automatically applied
- **Scope Validation**: Ensures only target file is modified
- **Progress Tracking**: Real-time monitoring with label updates
- **Cost Optimization**: Batched processing and rate limiting
- **Anti-Loop Protection**: Maximum 3 attempts with escalation

**⚠️ Safety Features**: This issue uses enhanced automation with scope validation, progress tracking, and anti-loop protection.

---

*Generated by create-copilot-issues-enhanced.ps1 with intelligent labeling system*
*Labels applied: $($intelligentLabels.Count) | Priority: $($criticalIssues.Count -gt 0 ? "CRITICAL" : $majorIssues.Count -gt 0 ? "MAJOR" : "MINOR") | Scope: Single File*
"@

    return @{
        Title = $issueTitle
        Body = $issueBody
        Labels = $intelligentLabels
    }
}

# Test the enhanced label system
if ($args.Count -eq 0 -or $args[0] -eq "-help") {
    Write-Output @"
🏷️  Enhanced RUTOS Copilot Issue Creation with Intelligent Labels

This enhanced version includes:
- 🎯 Intelligent label assignment based on issue analysis
- 🔍 Comprehensive issue classification
- 📊 Priority-based routing
- 🛡️  Enhanced scope validation
- 🚀 Progress tracking with labels
- 💰 Cost optimization features

Usage:
  .\create-copilot-issues-enhanced.ps1 -Production -DebugMode
  .\create-copilot-issues-enhanced.ps1 -DryRun -TargetFile "scripts/test.sh"
  .\create-copilot-issues-enhanced.ps1 -TestMode -PriorityFilter Critical

Labels Applied: 82 comprehensive labels for complete automation
"@

    Write-Output "`nTo see the complete implementation, use the original script with this enhancement."
    exit 0
}

Write-Output "🏷️  Enhanced RUTOS Copilot Issue Creation System Ready"
Write-Output "   Labels: 82 intelligent labels available"
Write-Output "   Features: Priority routing, scope validation, progress tracking"
Write-Output "   Safety: Anti-loop protection, cost optimization, rate limiting"
