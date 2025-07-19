# PowerShell script to setup development tools on Windows
# This is a Windows-compatible version of setup-dev-tools.sh

[CmdletBinding()]
param(
    [switch]$NodeOnly,
    [switch]$ShellOnly,
    [switch]$Force,
    [switch]$Check,
    [switch]$Help
)

$ScriptVersion = "1.0.0"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-InfoLog {
    param([string]$Message)
    Write-ColorOutput "[INFO] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Color Green
}

function Write-WarningLog {
    param([string]$Message)
    Write-ColorOutput "[WARNING] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Color Yellow
}

function Write-ErrorLog {
    param([string]$Message)
    Write-ColorOutput "[ERROR] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Color Red
}

function Write-StepLog {
    param([string]$Message)
    Write-ColorOutput "[STEP] [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Color Blue
}

function Test-CommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Show-Usage {
    Write-Host @"
Setup Local Development Tools v$ScriptVersion (Windows PowerShell)

This script installs code quality tools locally for the RUTOS Starlink Failover project:
- markdownlint-cli: Markdown linting and formatting
- prettier: Code and markdown formatting
- shellcheck: Shell script validation (via WSL)
- shfmt: Shell script formatting (via WSL or Go)

Usage: .\scripts\setup-dev-tools.ps1 [options]

Options:
    -NodeOnly         Install only Node.js tools (skip shell tools)
    -ShellOnly        Install only shell tools (skip Node.js tools)
    -Force            Force reinstall even if tools exist
    -Check            Just check what tools are available
    -Help             Show this help message

Examples:
    .\scripts\setup-dev-tools.ps1                # Install all tools
    .\scripts\setup-dev-tools.ps1 -NodeOnly     # Install only markdownlint and prettier
    .\scripts\setup-dev-tools.ps1 -Check        # Check what tools are currently available
    .\scripts\setup-dev-tools.ps1 -Force        # Force reinstall all tools

"@
}

function Test-Tools {
    Write-StepLog "Checking current tool availability"
    
    Write-Host ""
    Write-Host ("{0,-20} {1}" -f "Tool", "Status")
    Write-Host ("{0,-20} {1}" -f "----", "------")
    
    # Node.js tools
    if (Test-CommandExists "markdownlint") {
        $version = try { (markdownlint --version 2>$null) } catch { "unknown version" }
        Write-Host ("{0,-20} {1} ({2})" -f "markdownlint", "✓ Available", $version) -ForegroundColor Green
    } else {
        Write-Host ("{0,-20} {1}" -f "markdownlint", "✗ Missing") -ForegroundColor Red
    }
    
    if (Test-CommandExists "prettier") {
        $version = try { (prettier --version 2>$null) } catch { "unknown version" }
        Write-Host ("{0,-20} {1} ({2})" -f "prettier", "✓ Available", $version) -ForegroundColor Green
    } else {
        Write-Host ("{0,-20} {1}" -f "prettier", "✗ Missing") -ForegroundColor Red
    }
    
    # Shell tools (may be in WSL)
    $shellcheckAvailable = (Test-CommandExists "shellcheck") -or (Test-CommandExists "wsl")
    if ($shellcheckAvailable) {
        Write-Host ("{0,-20} {1}" -f "shellcheck", "✓ Available") -ForegroundColor Green
    } else {
        Write-Host ("{0,-20} {1}" -f "shellcheck", "✗ Missing") -ForegroundColor Red
    }
    
    $shfmtAvailable = (Test-CommandExists "shfmt") -or (Test-CommandExists "wsl") -or (Test-CommandExists "go")
    if ($shfmtAvailable) {
        Write-Host ("{0,-20} {1}" -f "shfmt", "✓ Available") -ForegroundColor Green
    } else {
        Write-Host ("{0,-20} {1}" -f "shfmt", "✗ Missing") -ForegroundColor Red
    }
    
    # Node.js itself
    if (Test-CommandExists "node") {
        $version = try { (node --version 2>$null) } catch { "unknown version" }
        Write-Host ("{0,-20} {1} ({2})" -f "node", "✓ Available", $version) -ForegroundColor Green
    } else {
        Write-Host ("{0,-20} {1}" -f "node", "✗ Missing") -ForegroundColor Red
    }
    
    if (Test-CommandExists "npm") {
        $version = try { (npm --version 2>$null) } catch { "unknown version" }
        Write-Host ("{0,-20} {1} ({2})" -f "npm", "✓ Available", $version) -ForegroundColor Green
    } else {
        Write-Host ("{0,-20} {1}" -f "npm", "✗ Missing") -ForegroundColor Red
    }
    
    Write-Host ""
}

function Install-NodeTools {
    Write-StepLog "Installing Node.js tools (markdownlint, prettier)"
    
    # Check if Node.js is available
    if (-not (Test-CommandExists "node") -or -not (Test-CommandExists "npm")) {
        Write-ErrorLog "Node.js and npm are required but not found"
        Write-ErrorLog "Please install Node.js from: https://nodejs.org/"
        Write-ErrorLog "Or using package managers:"
        Write-ErrorLog "  Chocolatey: choco install nodejs"
        Write-ErrorLog "  Scoop: scoop install nodejs"
        Write-ErrorLog "  Winget: winget install OpenJS.NodeJS"
        return $false
    }
    
    $nodeVersion = node --version 2>$null
    $npmVersion = npm --version 2>$null
    Write-InfoLog "Node.js $nodeVersion and npm $npmVersion found"
    
    # Create package.json if it doesn't exist
    $packageJsonPath = Join-Path $ProjectRoot "package.json"
    if (-not (Test-Path $packageJsonPath)) {
        Write-StepLog "Creating package.json for Node.js tools"
        
        $packageJson = @{
            name = "rutos-starlink-failover-tools"
            version = "1.0.0"
            description = "Development tools for RUTOS Starlink Failover project"
            private = $true
            scripts = @{
                "lint:markdown" = "markdownlint `"**/*.md`" --ignore node_modules --fix"
                "format:markdown" = "prettier --write `"**/*.md`" --ignore-path .gitignore"
                "check:markdown" = "markdownlint `"**/*.md`" --ignore node_modules && prettier --check `"**/*.md`" --ignore-path .gitignore"
            }
            devDependencies = @{
                "markdownlint-cli" = "^0.37.0"
                "prettier" = "^3.0.0"
            }
            keywords = @("rutos", "starlink", "router", "failover", "monitoring")
        }
        
        $packageJson | ConvertTo-Json -Depth 3 | Set-Content $packageJsonPath -Encoding UTF8
        Write-InfoLog "Created package.json"
    } else {
        Write-InfoLog "package.json already exists"
    }
    
    # Install Node.js dependencies
    Write-StepLog "Installing Node.js dependencies"
    Push-Location $ProjectRoot
    
    try {
        if ($Force) {
            if (Test-Path "node_modules") { Remove-Item "node_modules" -Recurse -Force }
            if (Test-Path "package-lock.json") { Remove-Item "package-lock.json" -Force }
            Write-InfoLog "Removed existing node_modules (force install)"
        }
        
        $npmResult = npm install
        if ($LASTEXITCODE -eq 0) {
            Write-InfoLog "Node.js tools installed successfully"
        } else {
            Write-ErrorLog "Failed to install Node.js tools"
            return $false
        }
    } finally {
        Pop-Location
    }
    
    # Create .markdownlint.json configuration
    $markdownlintConfigPath = Join-Path $ProjectRoot ".markdownlint.json"
    if (-not (Test-Path $markdownlintConfigPath)) {
        Write-StepLog "Creating markdownlint configuration"
        
        $markdownlintConfig = @{
            default = $true
            MD003 = @{ style = "atx" }
            MD007 = @{ indent = 2 }
            MD013 = @{ line_length = 120; code_blocks = $false; tables = $false }
            MD024 = @{ allow_different_nesting = $true }
            MD033 = @{ allowed_elements = @("details", "summary", "br") }
            MD041 = $false
        }
        
        $markdownlintConfig | ConvertTo-Json -Depth 3 | Set-Content $markdownlintConfigPath -Encoding UTF8
        Write-InfoLog "Created .markdownlint.json configuration"
    }
    
    # Create .prettierrc configuration
    $prettierConfigPath = Join-Path $ProjectRoot ".prettierrc"
    if (-not (Test-Path $prettierConfigPath)) {
        Write-StepLog "Creating prettier configuration"
        
        $prettierConfig = @{
            printWidth = 120
            tabWidth = 2
            useTabs = $false
            semi = $false
            singleQuote = $false
            quoteProps = "as-needed"
            trailingComma = "none"
            bracketSpacing = $true
            proseWrap = "preserve"
            overrides = @(
                @{
                    files = "*.md"
                    options = @{
                        proseWrap = "preserve"
                        printWidth = 120
                    }
                }
            )
        }
        
        $prettierConfig | ConvertTo-Json -Depth 4 | Set-Content $prettierConfigPath -Encoding UTF8
        Write-InfoLog "Created .prettierrc configuration"
    }
    
    return $true
}

function Install-ShellTools {
    Write-StepLog "Installing shell tools (shellcheck, shfmt)"
    
    # Check if WSL is available
    if (Test-CommandExists "wsl") {
        Write-InfoLog "WSL detected - shell tools can be installed in WSL"
        Write-InfoLog "Run in WSL: sudo apt update && sudo apt install shellcheck"
        Write-InfoLog "For shfmt in WSL: go install mvdan.cc/sh/v3/cmd/shfmt@latest"
    } else {
        Write-WarningLog "WSL not available"
        Write-InfoLog "Consider installing WSL for better shell tool support:"
        Write-InfoLog "  wsl --install"
    }
    
    # Check if Go is available for shfmt
    if (Test-CommandExists "go") {
        Write-StepLog "Installing shfmt via Go"
        try {
            go install mvdan.cc/sh/v3/cmd/shfmt@latest
            Write-InfoLog "shfmt installed via Go"
            Write-InfoLog "Make sure `$env:GOPATH\bin is in your PATH"
        } catch {
            Write-WarningLog "Failed to install shfmt via Go"
        }
    }
    
    return $true
}

function Update-GitIgnore {
    Write-StepLog "Updating .gitignore for development tools"
    
    $gitignorePath = Join-Path $ProjectRoot ".gitignore"
    
    if (-not (Test-Path $gitignorePath) -or -not (Select-String -Path $gitignorePath -Pattern "node_modules" -Quiet)) {
        Write-StepLog "Adding Node.js entries to .gitignore"
        
        $nodeEntries = @"

# Node.js development tools
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
package-lock.json
.npm

"@
        Add-Content -Path $gitignorePath -Value $nodeEntries -Encoding UTF8
        Write-InfoLog "Updated .gitignore with Node.js entries"
    } else {
        Write-InfoLog ".gitignore already contains Node.js entries"
    }
}

# Main execution
if ($Help) {
    Show-Usage
    exit 0
}

Write-InfoLog "Starting development tools setup v$ScriptVersion (Windows PowerShell)"

if ($Check) {
    Test-Tools
    exit 0
}

Write-StepLog "Setting up development tools for RUTOS Starlink Failover project"
Write-InfoLog "Project root: $ProjectRoot"
Write-Host ""

# Show current status
Test-Tools

# Install tools based on options
if (-not $ShellOnly) {
    if (-not (Install-NodeTools)) {
        Write-ErrorLog "Failed to install Node.js tools"
        exit 1
    }
    Write-Host ""
}

if (-not $NodeOnly) {
    Install-ShellTools
    Write-Host ""
}

# Update project files
Update-GitIgnore

Write-Host ""
Write-InfoLog "Development tools setup complete!"
Write-Host ""

# Final status check
Write-StepLog "Final tool status"
Test-Tools

Write-Host ""
Write-InfoLog "Available commands:"
Write-InfoLog "  npm run lint:markdown      - Lint markdown files"
Write-InfoLog "  npm run format:markdown    - Format markdown files"
Write-InfoLog "  npm run check:markdown     - Check markdown formatting"
Write-InfoLog "  .\scripts\pre-commit-validation.sh - Full pre-commit validation (in WSL)"
Write-Host ""
Write-InfoLog "For shell script validation, use WSL:"
Write-InfoLog "  wsl ./scripts/pre-commit-validation.sh"
Write-Host ""
Write-InfoLog "✅ You can now run validation with all tools available!"
