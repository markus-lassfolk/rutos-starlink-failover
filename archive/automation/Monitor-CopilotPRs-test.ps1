param(
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
    Write-StatusMessage "Fetching open Copilot PRs..." -Color $BLUE
    
    try {
        $prs = gh pr list --state open --json number,title,headRefName,author --limit 50
        
        if ($LASTEXITCODE -ne 0) {
            Write-StatusMessage "Failed to fetch PR list" -Color $RED
            return @()
        }
        
        $prData = $prs | ConvertFrom-Json
        
        # Filter for Copilot PRs (multiple possible author formats)
        $copilotPRs = $prData | Where-Object { 
            $_.author.login -match "copilot" -or 
            $_.author.login -eq "app/github-copilot" -or 
            $_.author.login -eq "app/copilot-swe-agent" -or
            $_.title -match "copilot" -or
            $_.headRefName -match "copilot"
        } | ForEach-Object {
            @{
                Number = $_.number
                Title = $_.title
                HeadRef = $_.headRefName
                Author = $_.author.login
            }
        }
        
        if ($copilotPRs.Count -eq 0) {
            Write-StatusMessage "No open Copilot PRs found" -Color $CYAN
            Write-StatusMessage "Debug: Found $($prData.Count) total PRs, checking authors..." -Color $CYAN
            foreach ($pr in $prData) {
                Write-StatusMessage "   PR #$($pr.number): Author = $($pr.author.login), Title = $($pr.title)" -Color $CYAN
            }
            return @()
        }
        
        Write-StatusMessage "Found $($copilotPRs.Count) Copilot PR(s)" -Color $GREEN
        foreach ($pr in $copilotPRs) {
            Write-StatusMessage "   PR #$($pr.Number): $($pr.Title) (by $($pr.Author))" -Color $BLUE
        }
        
        return $copilotPRs
        
    } catch {
        Write-StatusMessage "Error fetching Copilot PRs: $($_.Exception.Message)" -Color $RED
        return @()
    }
}

# Main processing function
function Start-CopilotPRs {
    Write-StatusMessage "Starting Copilot PR monitoring..." -Color $GREEN
    
    # Get open PRs from Copilot
    $openPRs = Get-CopilotPRs
    
    if ($openPRs.Count -eq 0) {
        Write-StatusMessage "No open Copilot PRs found to process" -Color $CYAN
        return
    }
    
    Write-StatusMessage "Found $($openPRs.Count) open Copilot PR(s)" -Color $BLUE
    
    foreach ($pr in $openPRs) {
        Write-StatusMessage "Processing PR #$($pr.Number): $($pr.Title)" -Color $PURPLE
        Write-StatusMessage "  Author: $($pr.Author)" -Color $CYAN
        Write-StatusMessage "  Branch: $($pr.HeadRef)" -Color $CYAN
        
        # In TestMode, just show what we found
        if ($TestMode) {
            Write-StatusMessage "  [TEST MODE] Would validate this PR" -Color $YELLOW
        } else {
            Write-StatusMessage "  [PRODUCTION MODE] Ready to validate" -Color $GREEN
        }
    }
    
    Write-StatusMessage "Copilot PR monitoring completed!" -Color $GREEN
}

# Main execution
try {
    # Validate we're in the correct directory
    if (-not (Test-Path ".git")) {
        Write-StatusMessage "This script must be run from the repository root" -Color $RED
        exit 1
    }
    
    # Check GitHub CLI is available
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-StatusMessage "GitHub CLI (gh) is not installed or not in PATH" -Color $RED
        exit 1
    }
    
    # Check authentication
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "GitHub CLI is not authenticated. Run 'gh auth login' first." -Color $RED
        exit 1
    }
    
    # Run the main processing
    Start-CopilotPRs
    
} catch {
    Write-StatusMessage "Script execution failed: $($_.Exception.Message)" -Color $RED
    exit 1
}
