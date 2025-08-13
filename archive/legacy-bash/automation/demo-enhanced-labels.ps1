#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Demonstration of Enhanced Label System with Documentation and Enhancement Labels
    
.DESCRIPTION
    This script demonstrates how the enhanced label system intelligently assigns
    labels for documentation, enhancement, and content-related issues in addition
    to the existing RUTOS compatibility labels.
    
.PARAMETER TestScenario
    Which scenario to test: All, Documentation, Enhancement, Content, Technical
    
.EXAMPLE
    .\demo-enhanced-labels.ps1 -TestScenario All
    Test all enhanced labeling scenarios
    
.EXAMPLE
    .\demo-enhanced-labels.ps1 -TestScenario Documentation
    Test documentation-specific labeling
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "Documentation", "Enhancement", "Content", "Technical")]
    [string]$TestScenario = "All"
)

# Import the label management module
$modulePath = Join-Path $PSScriptRoot "GitHub-Label-Management.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    Write-Host "✅ Loaded GitHub Label Management Module" -ForegroundColor Green
} else {
    Write-Host "❌ Could not find GitHub-Label-Management.psm1" -ForegroundColor Red
    exit 1
}

# Test scenarios
$testScenarios = @{
    "Documentation" = @{
        Title = "Fix typos in README.md"
        Body = "Found several spelling errors in the README file that need to be corrected."
        FilePath = "README.md"
        Context = "documentation"
        Issues = @()
    }
    
    "Enhancement" = @{
        Title = "Feature request: Add support for custom notification sounds"
        Body = "As a user, I would like to customize notification sounds for different alert types. This would be a nice enhancement to the current system."
        FilePath = "scripts/notifications.sh"
        Context = "enhancement"
        Issues = @()
    }
    
    "Content" = @{
        Title = "Update outdated installation guide"
        Body = "The installation guide contains outdated information about system requirements. Need to update for accuracy."
        FilePath = "docs/INSTALLATION.md"
        Context = "content"
        Issues = @()
    }
    
    "Technical" = @{
        Title = "RUTOS Compatibility: Fix busybox issues in monitor script"
        Body = "Found critical POSIX violations and local keyword usage that will cause failures."
        FilePath = "scripts/starlink-monitor.sh"
        Context = "issue"
        Issues = @(
            @{ Type = "Critical"; Line = "local debug_mode=1"; LineNumber = 45; Issue = "Local keyword not supported in busybox" }
            @{ Type = "Major"; Line = "echo -e 'test'"; LineNumber = 67; Issue = "Echo -e not portable" }
            @{ Type = "Minor"; Line = "function test() {"; LineNumber = 89; Issue = "Function syntax not POSIX" }
        )
    }
    
    "Markdown" = @{
        Title = "Fix markdown formatting in troubleshooting guide"
        Body = "The markdown structure in the troubleshooting guide is inconsistent and needs formatting improvements."
        FilePath = "docs/TROUBLESHOOTING.md"
        Context = "documentation"
        Issues = @()
    }
    
    "Suggestion" = @{
        Title = "Suggestion: Improve error messages for better debugging"
        Body = "I suggest we improve the error messages to make debugging easier. This would help users troubleshoot issues more effectively."
        FilePath = "scripts/error-handler.sh"
        Context = "enhancement"
        Issues = @()
    }
    
    "Research" = @{
        Title = "Research: Investigate alternative notification methods"
        Body = "We should research and analyze different notification methods to determine the best approach for our use case."
        FilePath = ""
        Context = "enhancement"
        Issues = @()
    }
}

function Test-LabelScenario {
    param(
        [string]$ScenarioName,
        [hashtable]$Scenario
    )
    
    Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
    Write-Host "🧪 Testing Scenario: $ScenarioName" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    Write-Host "📋 Issue Details:" -ForegroundColor Blue
    Write-Host "   Title: $($Scenario.Title)" -ForegroundColor White
    Write-Host "   Body: $($Scenario.Body)" -ForegroundColor White
    Write-Host "   File: $($Scenario.FilePath)" -ForegroundColor White
    Write-Host "   Context: $($Scenario.Context)" -ForegroundColor White
    Write-Host "   Issues: $($Scenario.Issues.Count)" -ForegroundColor White
    
    # Get intelligent labels
    $labels = Get-IntelligentLabels -FilePath $Scenario.FilePath -Issues $Scenario.Issues -Context $Scenario.Context -IssueTitle $Scenario.Title -IssueBody $Scenario.Body
    
    Write-Host "`n🏷️  Intelligent Labels Applied ($($labels.Count) total):" -ForegroundColor Green
    
    # Group labels by category for better display
    $labelsByCategory = @{}
    foreach ($label in $labels) {
        $labelInfo = Get-LabelInfo -LabelName $label
        if ($labelInfo) {
            $category = $labelInfo.Category
            if (-not $labelsByCategory.ContainsKey($category)) {
                $labelsByCategory[$category] = @()
            }
            $labelsByCategory[$category] += @{
                Name = $label
                Description = $labelInfo.Description
                Color = $labelInfo.Color
            }
        } else {
            # Unknown label
            if (-not $labelsByCategory.ContainsKey("Unknown")) {
                $labelsByCategory["Unknown"] = @()
            }
            $labelsByCategory["Unknown"] += @{
                Name = $label
                Description = "Unknown label"
                Color = "#808080"
            }
        }
    }
    
    # Display labels by category
    foreach ($category in ($labelsByCategory.Keys | Sort-Object)) {
        Write-Host "   📂 $category`:" -ForegroundColor Yellow
        foreach ($labelInfo in $labelsByCategory[$category]) {
            Write-Host "      • $($labelInfo.Name)" -ForegroundColor Cyan -NoNewline
            Write-Host " - $($labelInfo.Description)" -ForegroundColor Gray
        }
    }
    
    # Show label statistics
    Write-Host "`n📊 Label Statistics:" -ForegroundColor Magenta
    Show-LabelStatistics -Labels $labels
    
    return $labels
}

# Run tests based on scenario
Write-Host "🏷️  Enhanced Label System Demonstration" -ForegroundColor Green
Write-Host "📊 Total available labels: 100" -ForegroundColor Cyan
Write-Host "🆕 New label categories: Documentation, Enhancement, Content" -ForegroundColor Yellow

$scenariosToTest = @()

switch ($TestScenario) {
    "All" { $scenariosToTest = $testScenarios.Keys }
    "Documentation" { $scenariosToTest = @("Documentation", "Markdown") }
    "Enhancement" { $scenariosToTest = @("Enhancement", "Suggestion", "Research") }
    "Content" { $scenariosToTest = @("Content") }
    "Technical" { $scenariosToTest = @("Technical") }
}

$allLabels = @()
foreach ($scenarioName in $scenariosToTest) {
    $labels = Test-LabelScenario -ScenarioName $scenarioName -Scenario $testScenarios[$scenarioName]
    $allLabels += $labels
}

# Summary
Write-Host "`n" + ("=" * 80) -ForegroundColor Green
Write-Host "🎉 Enhanced Label System Demonstration Complete!" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green

Write-Host "`n📊 Summary Statistics:" -ForegroundColor Cyan
Write-Host "   Scenarios tested: $($scenariosToTest.Count)" -ForegroundColor White
Write-Host "   Unique labels used: $(($allLabels | Sort-Object -Unique).Count)" -ForegroundColor White
Write-Host "   Total label applications: $($allLabels.Count)" -ForegroundColor White

Write-Host "`n🆕 New Label Categories Demonstrated:" -ForegroundColor Yellow
Write-Host "   📝 Documentation: markdown, readme, guide, api-docs, changelog, comments" -ForegroundColor White
Write-Host "   🚀 Enhancement: feature-request, suggestion, recommendation, user-story, epic, prototype, research" -ForegroundColor White
Write-Host "   📄 Content: content-typo, content-grammar, content-structure, content-accuracy, content-outdated" -ForegroundColor White

Write-Host "`n💡 Key Features:" -ForegroundColor Blue
Write-Host "   ✅ Intelligent detection based on title and body content" -ForegroundColor Green
Write-Host "   ✅ File extension-based labeling (e.g., .md files get 'markdown' label)" -ForegroundColor Green
Write-Host "   ✅ Context-aware labeling for different issue types" -ForegroundColor Green
Write-Host "   ✅ Comprehensive coverage of all project needs" -ForegroundColor Green
Write-Host "   ✅ Maintains compatibility with existing RUTOS labels" -ForegroundColor Green

Write-Host "`n🔧 Usage in Scripts:" -ForegroundColor Magenta
Write-Host "   • create-copilot-issues.ps1: Automatically applies intelligent labels to issues" -ForegroundColor Gray
Write-Host "   • Monitor-CopilotPRs-Advanced.ps1: Updates labels based on PR progress" -ForegroundColor Gray
Write-Host "   • GitHub-Label-Management.psm1: Provides all label management functions" -ForegroundColor Gray

Write-Host "`n✨ Ready for production use with 100 comprehensive labels!" -ForegroundColor Green
