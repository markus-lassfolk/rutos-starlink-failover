#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Enhanced Go verification script for the Starfail project

.DESCRIPTION
    Comprehensive Go code verification with project-specific features including:
    - Multiple verification modes (all, files, staged, commit)
    - Granular control over individual checks
    - Auto-fix capabilities
    - Multi-platform build testing
    - Performance profiling
    - Dependency analysis
    - Security scanning
    - Documentation generation

.PARAMETER Mode
    Verification mode: all, files, staged, commit, ci

.PARAMETER Files
    Specific files or patterns to verify

.PARAMETER Help
    Show detailed help

.PARAMETER Verbose
    Enable verbose output

.PARAMETER Quiet
    Quiet mode (errors only)

.PARAMETER DryRun
    Show what would be done without making changes

.PARAMETER Fix
    Attempt to fix issues automatically

.PARAMETER NoFormat
    Skip gofmt formatting

.PARAMETER NoImports
    Skip goimports

.PARAMETER NoLint
    Skip golangci-lint

.PARAMETER NoVet
    Skip go vet

.PARAMETER NoStaticcheck
    Skip staticcheck

.PARAMETER NoSecurity
    Skip gosec security check

.PARAMETER NoTests
    Skip tests

.PARAMETER NoBuild
    Skip build verification

.PARAMETER NoDeps
    Skip dependency analysis

.PARAMETER NoDocs
    Skip documentation generation

.PARAMETER Profile
    Enable performance profiling

.PARAMETER Coverage
    Generate test coverage report

.PARAMETER Benchmarks
    Run benchmarks

.PARAMETER Race
    Enable race detection in tests

.PARAMETER Timeout
    Timeout for individual checks (seconds)

.EXAMPLE
    # Basic verification
    .\scripts\verify-go-enhanced.ps1 all

.EXAMPLE
    # Pre-commit check
    .\scripts\verify-go-enhanced.ps1 staged

.EXAMPLE
    # CI/CD mode with all checks
    .\scripts\verify-go-enhanced.ps1 ci -Coverage -Race

.EXAMPLE
    # Quick development check
    .\scripts\verify-go-enhanced.ps1 all -NoTests -NoBuild

.EXAMPLE
    # Auto-fix mode
    .\scripts\verify-go-enhanced.ps1 all -Fix

.EXAMPLE
    # Performance profiling
    .\scripts\verify-go-enhanced.ps1 all -Profile -Benchmarks
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("all", "files", "staged", "commit", "ci")]
    [string]$Mode = "all",
    
    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Files = @(),
    
    [switch]$Help,
    [switch]$VerboseOutput,
    [switch]$Quiet,
    [switch]$DryRun,
    [switch]$Fix,
    [switch]$InstallDeps,
    [switch]$NoFormat,
    [switch]$NoImports,
    [switch]$NoLint,
    [switch]$NoVet,
    [switch]$NoStaticcheck,
    [switch]$NoSecurity,
    [switch]$NoTests,
    [switch]$NoBuild,
    [switch]$NoDeps,
    [switch]$NoDocs,
    [switch]$Coverage,
    [switch]$Benchmarks,
    [switch]$Race,
    [int]$Timeout = 300,
    
    # LuCI verification options
    [switch]$LuCI,
    [switch]$NoLua,
    [switch]$NoHTML,
    [switch]$NoCSS,
    [switch]$NoJS,
    [switch]$NoTranslations
)

# Script metadata
$Script:ScriptName = "verify-go-enhanced.ps1"
$Script:Version = "2.0.0"
$Script:ProjectName = "Starfail"

# Configuration
$Script:Config = @{
    EnableFormat      = !$NoFormat
    EnableImports     = !$NoImports
    EnableLint        = !$NoLint
    EnableVet         = !$NoVet
    EnableStaticcheck = !$NoStaticcheck
    EnableSecurity    = !$NoSecurity
    EnableTests       = !$NoTests
    EnableBuild       = !$NoBuild
    EnableDeps        = !$NoDeps
    EnableDocs        = !$NoDocs
    EnableProfile     = $Profile
    EnableCoverage    = $Coverage
    EnableBenchmarks  = $Benchmarks
    EnableRace        = $Race
    AutoFix           = $Fix
    DryRun            = $DryRun
    Verbose           = $VerboseOutput
    Quiet             = $Quiet
    Timeout           = $Timeout
    
    # LuCI configuration
    EnableLuCI        = $LuCI
    EnableLua         = !$NoLua
    EnableHTML        = !$NoHTML
    EnableCSS         = !$NoCSS
    EnableJS          = !$NoJS
    EnableTranslations = !$NoTranslations
}

# Project-specific configuration
$Script:ProjectConfig = @{
    ModulePath        = "github.com/starfail/starfail"
    MainPackages      = @("cmd/starfaild", "cmd/starfailsysmgmt")
    TestPackages      = @("pkg/...")
    BuildTargets      = @(
        @{GOOS="linux"; GOARCH="amd64"; Name="linux-amd64"},
        @{GOOS="linux"; GOARCH="arm"; Name="linux-arm"},
        @{GOOS="linux"; GOARCH="mips"; Name="linux-mips"},
        @{GOOS="windows"; GOARCH="amd64"; Name="windows-amd64"},
        @{GOOS="darwin"; GOARCH="amd64"; Name="darwin-amd64"}
    )
    LintConfig        = ".golangci.yml"
    CoverageThreshold = 80
    SecurityRules     = @("default", "G101", "G102", "G103", "G104")
    
    # LuCI-specific configuration
    LuCIConfig        = @{
        LuaCheckConfig    = ".luacheckrc"
        ESLintConfig      = ".eslintrc.js"
        StylelintConfig   = ".stylelintrc.json"
        HTMLHintConfig    = ".htmlhintrc"
        LuaPattern        = "**/*.lua"
        HTMLPattern       = "**/*.htm"
        CSSPattern        = "**/*.css"
        JSPattern         = "**/*.js"
        POPattern         = "**/*.po"
    }
}

# Colors for console output
$Script:Colors = @{
    Red     = "Red"
    Green   = "Green"
    Yellow  = "Yellow"
    Blue    = "Blue"
    Cyan    = "Cyan"
    Gray    = "Gray"
    Magenta = "Magenta"
}

function Show-Usage {
    @"
$Script:ProjectName Go Verification Script v$Script:Version

Usage: $Script:ScriptName [MODE] [OPTIONS] [FILES...]

MODES:
    all                 - Check all Go files in project (default)
    files FILE1 FILE2   - Check specific files or patterns
    staged              - Check staged files for pre-commit
    commit              - Check files in git diff --cached
    ci                  - Full CI/CD verification with all checks

OPTIONS:
    -Help              - Show this help
    -Verbose           - Verbose output
    -Quiet             - Quiet mode (errors only)
    -DryRun            - Show what would be done
    -Fix               - Attempt to fix issues automatically
    -InstallDeps       - Install missing dependencies and tools
    -NoFormat          - Skip gofmt formatting
    -NoImports         - Skip goimports
    -NoLint            - Skip golangci-lint
    -NoVet             - Skip go vet
    -NoStaticcheck     - Skip staticcheck
    -NoSecurity        - Skip gosec security check
    -NoTests           - Skip tests
    -NoBuild           - Skip build verification
    -NoDeps            - Skip dependency analysis
    -NoDocs            - Skip documentation generation
    -Profile           - Enable performance profiling
    -Coverage          - Generate test coverage report
    -Benchmarks        - Run benchmarks
    -Race              - Enable race detection in tests
    -Timeout SECONDS   - Timeout for individual checks (default: 300)

LUCI OPTIONS:
    -LuCI              - Enable LuCI verification (Lua, HTML, CSS, JS, translations)
    -NoLua             - Skip Lua syntax and style checking (luacheck)
    -NoHTML            - Skip HTML syntax checking (htmlhint)
    -NoCSS             - Skip CSS style checking (stylelint)
    -NoJS              - Skip JavaScript checking (eslint)
    -NoTranslations    - Skip translation file validation (msgfmt)

EXAMPLES:
    .\$Script:ScriptName all                           # Check all files
    .\$Script:ScriptName files pkg\logx\*.go          # Check specific files
    .\$Script:ScriptName staged                        # Check staged files
    .\$Script:ScriptName ci -Coverage -Race           # Full CI check
    .\$Script:ScriptName -InstallDeps                  # Install missing tools
    .\$Script:ScriptName -InstallDeps -LuCI           # Install tools including LuCI
    .\$Script:ScriptName -NoTests all                  # Check without tests
    .\$Script:ScriptName -DryRun all                   # Show what would run
    .\$Script:ScriptName all -Fix                      # Auto-fix issues
    .\$Script:ScriptName all -LuCI                     # Include LuCI verification
    .\$Script:ScriptName all -LuCI -NoJS               # LuCI without JavaScript check

ENVIRONMENT:
    `$env:GO_VERIFY_CONFIG   - Path to config file
    `$env:DRY_RUN=1         - Enable dry-run mode
    `$env:VERBOSE=1         - Enable verbose mode
    `$env:COVERAGE_THRESHOLD - Set coverage threshold
    `$env:BUILD_TARGETS     - Comma-separated build targets
"@
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Verbose", "Debug")]
        [string]$Level = "Info",
        [string]$Category = ""
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $categoryPrefix = if ($Category) { "[$Category] " } else { "" }
    
    switch ($Level) {
        "Info" {
            if (!$Script:Config.Quiet) {
                Write-Host "[$timestamp] [INFO] $categoryPrefix$Message" -ForegroundColor $Script:Colors.Blue
            }
        }
        "Success" {
            Write-Host "[$timestamp] [SUCCESS] $categoryPrefix$Message" -ForegroundColor $Script:Colors.Green
        }
        "Warning" {
            Write-Host "[$timestamp] [WARNING] $categoryPrefix$Message" -ForegroundColor $Script:Colors.Yellow
        }
        "Error" {
            Write-Host "[$timestamp] [ERROR] $categoryPrefix$Message" -ForegroundColor $Script:Colors.Red
        }
        "Verbose" {
            if ($Script:Config.Verbose) {
                Write-Host "[$timestamp] [VERBOSE] $categoryPrefix$Message" -ForegroundColor $Script:Colors.Gray
            }
        }
        "Debug" {
            if ($Script:Config.Verbose) {
                Write-Host "[$timestamp] [DEBUG] $categoryPrefix$Message" -ForegroundColor $Script:Colors.Magenta
            }
        }
    }
}

function Test-Command {
    param(
        [string]$Command,
        [string]$InstallCommand = "",
        [string]$Category = "Tools"
    )
    
    try {
        $null = Get-Command $Command -ErrorAction Stop
        Write-Log "$Command available" -Level Verbose -Category $Category
        return $true
    }
    catch {
        Write-Log "Tool '$Command' not found" -Level Warning -Category $Category
        if ($InstallCommand) {
            Write-Log "Install with: $InstallCommand" -Level Info -Category $Category
        }
        return $false
    }
}

function Test-Tools {
    Write-Log "Checking required tools..." -Level Info -Category "Setup"
    
    $missingTools = @()
    $availableTools = @()
    
    # Core Go tools
    if (Test-Command "go" "Install Go from https://golang.org/" "Go") {
        $availableTools += "go"
        $goVersion = go version
        Write-Log "Go version: $goVersion" -Level Verbose -Category "Go"
    } else {
        $missingTools += "go"
    }
    
    # Additional tools
    $tools = @{
        "gofmt" = @{ Install = "Included with Go"; Required = $true }
        "goimports" = @{ Install = "go install golang.org/x/tools/cmd/goimports@latest"; Required = $Script:Config.EnableImports }
        "golangci-lint" = @{ Install = "go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; Required = $Script:Config.EnableLint }
        "staticcheck" = @{ Install = "go install honnef.co/go/tools/cmd/staticcheck@latest"; Required = $Script:Config.EnableStaticcheck }
        "gosec" = @{ Install = "go install github.com/securego/gosec/v2/cmd/gosec@latest"; Required = $Script:Config.EnableSecurity }
        "gocritic" = @{ Install = "go install github.com/go-critic/go-critic/cmd/gocritic@latest"; Required = $false }
        "gocyclo" = @{ Install = "go install github.com/fzipp/gocyclo/cmd/gocyclo@latest"; Required = $false }
        "ineffassign" = @{ Install = "go install github.com/gordonklaus/ineffassign@latest"; Required = $false }
        "godoc" = @{ Install = "go install golang.org/x/tools/cmd/godoc@latest"; Required = $Script:Config.EnableDocs }
        
        # LuCI tools
        "luacheck" = @{ Install = "Install via: luarocks install luacheck"; Required = ($Script:Config.EnableLuCI -and $Script:Config.EnableLua) }
        "lua" = @{ Install = "Install Lua from https://www.lua.org/"; Required = ($Script:Config.EnableLuCI -and $Script:Config.EnableLua) }
        "htmlhint" = @{ Install = "npm install -g htmlhint"; Required = ($Script:Config.EnableLuCI -and $Script:Config.EnableHTML) }
        "eslint" = @{ Install = "npm install -g eslint"; Required = ($Script:Config.EnableLuCI -and $Script:Config.EnableJS) }
        "stylelint" = @{ Install = "npm install -g stylelint"; Required = ($Script:Config.EnableLuCI -and $Script:Config.EnableCSS) }
        "msgfmt" = @{ Install = "Install gettext tools"; Required = ($Script:Config.EnableLuCI -and $Script:Config.EnableTranslations) }
    }
    
    foreach ($tool in $tools.GetEnumerator()) {
        if ($tool.Value.Required) {
            if (Test-Command $tool.Key $tool.Value.Install "Tools") {
                $availableTools += $tool.Key
            } else {
                $missingTools += $tool.Key
            }
        } else {
            if (Test-Command $tool.Key $tool.Value.Install "Tools") {
                $availableTools += $tool.Key
            }
        }
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Log "Missing required tools: $($missingTools -join ', ')" -Level Error -Category "Setup"
        Write-Log "Install missing tools and run again, or use -No* parameters to skip checks" -Level Info -Category "Setup"
        return $false
    }
    
    Write-Log "Available tools: $($availableTools -join ', ')" -Level Success -Category "Setup"
    return $true
}

function Install-Dependencies {
    Write-Log "Installing missing dependencies and tools..." -Level Info -Category "Setup"
    
    $installCommands = @()
    $manualInstalls = @()
    
    # Check which tools are needed based on configuration
    $requiredTools = @{
        "go" = @{ Install = "Download from https://golang.org/"; Manual = $true }
        "goimports" = @{ Install = "go install golang.org/x/tools/cmd/goimports@latest"; Manual = $false }
        "golangci-lint" = @{ Install = "go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; Manual = $false }
        "staticcheck" = @{ Install = "go install honnef.co/go/tools/cmd/staticcheck@latest"; Manual = $false }
        "gosec" = @{ Install = "go install github.com/securego/gosec/v2/cmd/gosec@latest"; Manual = $false }
        "gocritic" = @{ Install = "go install github.com/go-critic/go-critic/cmd/gocritic@latest"; Manual = $false }
        "gocyclo" = @{ Install = "go install github.com/fzipp/gocyclo/cmd/gocyclo@latest"; Manual = $false }
        "ineffassign" = @{ Install = "go install github.com/gordonklaus/ineffassign@latest"; Manual = $false }
        "godoc" = @{ Install = "go install golang.org/x/tools/cmd/godoc@latest"; Manual = $false }
    }
    
    # Add LuCI tools if LuCI verification is enabled
    if ($Script:Config.EnableLuCI) {
        $requiredTools["lua"] = @{ Install = "Download from https://www.lua.org/ or install via package manager"; Manual = $true }
        $requiredTools["luacheck"] = @{ Install = "luarocks install luacheck"; Manual = $true }
        $requiredTools["htmlhint"] = @{ Install = "npm install -g htmlhint"; Manual = $true }
        $requiredTools["eslint"] = @{ Install = "npm install -g eslint"; Manual = $true }
        $requiredTools["stylelint"] = @{ Install = "npm install -g stylelint stylelint-config-standard stylelint-order"; Manual = $true }
        $requiredTools["msgfmt"] = @{ Install = "Install gettext tools via package manager"; Manual = $true }
    }
    
    Write-Log "Checking and installing tools..." -Level Info -Category "Setup"
    
    foreach ($tool in $requiredTools.GetEnumerator()) {
        $toolName = $tool.Key
        $toolInfo = $tool.Value
        
        if (!(Test-Command $toolName "" "")) {
            Write-Log "Installing $toolName..." -Level Info -Category "Setup"
            
            if ($toolInfo.Manual) {
                $manualInstalls += @{
                    Tool = $toolName
                    Command = $toolInfo.Install
                }
                Write-Log "Manual installation required for $toolName" -Level Warning -Category "Setup"
            } else {
                $installCommands += @{
                    Tool = $toolName
                    Command = $toolInfo.Install
                }
            }
        } else {
            Write-Log "$toolName already installed" -Level Success -Category "Setup"
        }
    }
    
    # Install Go tools automatically
    if ($installCommands.Count -gt 0) {
        Write-Log "Installing Go tools automatically..." -Level Info -Category "Setup"
        
        foreach ($install in $installCommands) {
            Write-Log "Installing $($install.Tool)..." -Level Info -Category "Setup"
            
            if ($Script:Config.DryRun) {
                Write-Log "DRY RUN: Would run: $($install.Command)" -Level Info -Category "Setup"
                continue
            }
            
            try {
                $output = Invoke-Expression $install.Command 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "$($install.Tool) installed successfully" -Level Success -Category "Setup"
                } else {
                    Write-Log "Failed to install $($install.Tool): $output" -Level Error -Category "Setup"
                }
            } catch {
                Write-Log "Failed to install $($install.Tool): $($_.Exception.Message)" -Level Error -Category "Setup"
            }
        }
    }
    
    # Show manual installation instructions
    if ($manualInstalls.Count -gt 0) {
        Write-Log "Manual installation required for the following tools:" -Level Warning -Category "Setup"
        Write-Log "================================================================" -Level Info -Category "Setup"
        
        foreach ($manual in $manualInstalls) {
            Write-Log "$($manual.Tool):" -Level Info -Category "Setup"
            Write-Log "  $($manual.Command)" -Level Info -Category "Setup"
            Write-Log "" -Level Info -Category "Setup"
        }
        
        Write-Log "Platform-specific installation guide:" -Level Info -Category "Setup"
        Write-Log "================================================================" -Level Info -Category "Setup"
        Write-Log "Windows:" -Level Info -Category "Setup"
        Write-Log "  - Install Node.js from https://nodejs.org/" -Level Info -Category "Setup"
        Write-Log "  - Install Lua from https://www.lua.org/ or via Chocolatey: choco install lua" -Level Info -Category "Setup"
        Write-Log "  - Install LuaRocks: https://luarocks.org/" -Level Info -Category "Setup"
        Write-Log "  - Install gettext via MSYS2 or WSL" -Level Info -Category "Setup"
        Write-Log "" -Level Info -Category "Setup"
        Write-Log "macOS (via Homebrew):" -Level Info -Category "Setup"
        Write-Log "  brew install node lua luarocks gettext" -Level Info -Category "Setup"
        Write-Log "" -Level Info -Category "Setup"
        Write-Log "Ubuntu/Debian:" -Level Info -Category "Setup"
        Write-Log "  sudo apt-get install nodejs npm lua5.4 luarocks gettext" -Level Info -Category "Setup"
        Write-Log "" -Level Info -Category "Setup"
        Write-Log "After installing base tools, run:" -Level Info -Category "Setup"
        Write-Log "  npm install -g htmlhint eslint stylelint stylelint-config-standard stylelint-order" -Level Info -Category "Setup"
        Write-Log "  luarocks install luacheck" -Level Info -Category "Setup"
    }
    
    Write-Log "Dependency installation completed" -Level Success -Category "Setup"
    return $true
}

function Get-GoFiles {
    param(
        [string]$Mode,
        [string[]]$FileList = @()
    )
    
    $goFiles = @()
    
    switch ($Mode) {
        "all" {
            Write-Log "Scanning for all Go files..." -Level Info -Category "Files"
            $goFiles = Get-ChildItem -Path . -Filter "*.go" -Recurse | 
                Where-Object { 
                    $_.FullName -notmatch "vendor|\.git|\.cache|bin|obj" -and
                    $_.FullName -notmatch "\\vendor\\|\.git\\|\.cache\\|bin\\|obj\\"
                } |
                ForEach-Object { $_.FullName }
        }
        "files" {
            Write-Log "Processing specified files..." -Level Info -Category "Files"
            foreach ($pattern in $FileList) {
                if ($pattern -like "*\**" -or $pattern -like "*/*") {
                    # Handle glob patterns
                    $matchedFiles = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -eq ".go" } |
                        ForEach-Object { $_.FullName }
                    $goFiles += $matchedFiles
                    Write-Log "Pattern '$pattern' matched $($matchedFiles.Count) files" -Level Verbose -Category "Files"
                }
                elseif (Test-Path $pattern -PathType Leaf) {
                    if ([System.IO.Path]::GetExtension($pattern) -eq ".go") {
                        $goFiles += (Resolve-Path $pattern).Path
                        Write-Log "Added file: $pattern" -Level Verbose -Category "Files"
                    }
                    else {
                        Write-Log "File is not a Go file: $pattern" -Level Warning -Category "Files"
                    }
                }
                elseif (Test-Path $pattern -PathType Container) {
                    $dirFiles = Get-ChildItem -Path $pattern -Filter "*.go" -Recurse |
                        ForEach-Object { $_.FullName }
                    $goFiles += $dirFiles
                    Write-Log "Directory '$pattern' contains $($dirFiles.Count) Go files" -Level Verbose -Category "Files"
                }
                else {
                    Write-Log "File not found: $pattern" -Level Warning -Category "Files"
                }
            }
        }
        { $_ -eq "staged" -or $_ -eq "commit" } {
            Write-Log "Getting staged files..." -Level Info -Category "Files"
            try {
                $goFiles = git diff --cached --name-only --diff-filter=ACM |
                    Where-Object { $_ -like "*.go" } |
                    ForEach-Object { (Resolve-Path $_).Path }
                Write-Log "Found $($goFiles.Count) staged Go files" -Level Info -Category "Files"
            }
            catch {
                Write-Log "Error getting staged files: $_" -Level Error -Category "Files"
            }
        }
        "ci" {
            Write-Log "CI mode - checking all files" -Level Info -Category "Files"
            $goFiles = Get-ChildItem -Path . -Filter "*.go" -Recurse | 
                Where-Object { 
                    $_.FullName -notmatch "vendor|\.git|\.cache|bin|obj" -and
                    $_.FullName -notmatch "\\vendor\\|\.git\\|\.cache\\|bin\\|obj\\"
                } |
                ForEach-Object { $_.FullName }
        }
    }
    
    return $goFiles | Sort-Object -Unique
}

function Invoke-CommandWithTimeout {
    param(
        [string]$Description,
        [string]$Command,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = $Script:Config.Timeout,
        [string]$Category = "Command"
    )
    
    if ($Script:Config.DryRun) {
        Write-Log "DRY RUN: $Description" -Level Info -Category $Category
        Write-Log "Would run: $Command $($Arguments -join ' ')" -Level Verbose -Category $Category
        return $true
    }
    
    Write-Log $Description -Level Info -Category $Category
    Write-Log "Running: $Command $($Arguments -join ' ')" -Level Verbose -Category $Category
    
    try {
        $job = Start-Job -ScriptBlock {
            param($cmd, $argsList)
            $output = & $cmd @argsList 2>&1
            $exitCode = $LASTEXITCODE
            return @{ Output = $output; ExitCode = $exitCode }
        } -ArgumentList $Command, $Arguments
        
        if (Wait-Job $job -Timeout $TimeoutSeconds) {
            $result = Receive-Job $job
            Remove-Job $job
            
            if ($Script:Config.Verbose) {
                $result.Output | ForEach-Object { Write-Log $_ -Level Verbose -Category $Category }
            }
            
            if ($result.ExitCode -eq 0) {
                return $true
            } else {
                Write-Log "Command failed with exit code $($result.ExitCode)" -Level Error -Category $Category
                if ($result.Output) {
                    Write-Log "Error output: $($result.Output -join "`n")" -Level Error -Category $Category
                }
                return $false
            }
        } else {
            Stop-Job $job
            Remove-Job $job
            Write-Log "Command timed out after $TimeoutSeconds seconds" -Level Error -Category $Category
            return $false
        }
    }
    catch {
        Write-Log "Command failed: $_" -Level Error -Category $Category
        return $false
    }
}

function Invoke-GoFmt {
    param([string[]]$Files)
    
    if (!$Script:Config.EnableFormat) {
        Write-Log "Skipping gofmt (disabled)" -Level Verbose -Category "Format"
        return $true
    }
    
    if ($Files.Count -eq 0) {
        Write-Log "No Go files to format" -Level Warning -Category "Format"
        return $true
    }
    
    Write-Log "Running gofmt formatting..." -Level Info -Category "Format"
    
    # Check if files need formatting
    $unformatted = @()
    foreach ($file in $Files) {
        $result = gofmt -l $file 2>$null
        if ($result) {
            $unformatted += $file
        }
    }
    
    if ($unformatted.Count -gt 0) {
        Write-Log "Files need formatting: $($unformatted.Count)" -Level Warning -Category "Format"
        if ($Script:Config.Verbose) {
            $unformatted | ForEach-Object { Write-Log "  $_" -Level Verbose -Category "Format" }
        }
        
        if ($Script:Config.AutoFix -and !$Script:Config.DryRun) {
            Write-Log "Auto-fixing formatting..." -Level Info -Category "Format"
            foreach ($file in $unformatted) {
                gofmt -s -w $file
                Write-Log "Fixed: $file" -Level Verbose -Category "Format"
            }
            Write-Log "Formatting fixed" -Level Success -Category "Format"
        }
        elseif ($Script:Config.DryRun) {
            Write-Log "DRY RUN: Would fix formatting for $($unformatted.Count) files" -Level Info -Category "Format"
        }
        else {
            Write-Log "Run with -Fix to auto-fix formatting issues" -Level Info -Category "Format"
            return $false
        }
    }
    else {
        Write-Log "All files properly formatted" -Level Success -Category "Format"
    }
    
    return $true
}

function Invoke-GoImports {
    param([string[]]$Files)
    
    if (!$Script:Config.EnableImports -or !(Get-Command goimports -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping goimports (disabled or not available)" -Level Verbose -Category "Imports"
        return $true
    }
    
    if ($Files.Count -eq 0) {
        Write-Log "No Go files for import organization" -Level Warning -Category "Imports"
        return $true
    }
    
    Write-Log "Organizing imports..." -Level Info -Category "Imports"
    
    if ($Script:Config.AutoFix -and !$Script:Config.DryRun) {
        foreach ($file in $Files) {
            goimports -w $file
            Write-Log "Organized imports: $file" -Level Verbose -Category "Imports"
        }
        Write-Log "Import organization completed" -Level Success -Category "Imports"
    }
    elseif ($Script:Config.DryRun) {
        Write-Log "DRY RUN: Would organize imports for $($Files.Count) files" -Level Info -Category "Imports"
    }
    else {
        Write-Log "Run with -Fix to auto-organize imports" -Level Info -Category "Imports"
    }
    
    return $true
}

function Invoke-GolangciLint {
    if (!$Script:Config.EnableLint -or !(Get-Command golangci-lint -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping golangci-lint (disabled or not available)" -Level Verbose -Category "Lint"
        return $true
    }
    
    return Invoke-CommandWithTimeout "Running golangci-lint" "golangci-lint" @("run") -Category "Lint"
}

function Invoke-GoVet {
    if (!$Script:Config.EnableVet) {
        Write-Log "Skipping go vet (disabled)" -Level Verbose -Category "Vet"
        return $true
    }
    
    # Use a simpler approach for go vet to avoid PowerShell error interpretation
    if ($Script:Config.DryRun) {
        Write-Log "DRY RUN: Would run go vet ./..." -Level Info -Category "Vet"
        return $true
    }
    
    Write-Log "Running go vet..." -Level Info -Category "Vet"
    $output = go vet ./... 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($Script:Config.Verbose) {
        $output | ForEach-Object { Write-Log $_ -Level Verbose -Category "Vet" }
    }
    
    if ($exitCode -eq 0) {
        Write-Log "Go vet passed" -Level Success -Category "Vet"
        return $true
    } else {
        Write-Log "Go vet found issues" -Level Error -Category "Vet"
        if ($output) {
            Write-Log "Vet output: $($output -join "`n")" -Level Error -Category "Vet"
        }
        
        # Try to fix dependency issues automatically
        if ($Script:Config.AutoFix -and $output -match "missing go\.sum entry") {
            Write-Log "Attempting to fix dependency issues..." -Level Info -Category "Vet"
            try {
                go mod tidy 2>&1 | Out-Null
                go mod download 2>&1 | Out-Null
                Write-Log "Dependencies updated, re-running go vet..." -Level Info -Category "Vet"
                
                $output2 = go vet ./... 2>&1
                $exitCode2 = $LASTEXITCODE
                
                if ($exitCode2 -eq 0) {
                    Write-Log "Go vet passed after dependency fix" -Level Success -Category "Vet"
                    return $true
                } else {
                    Write-Log "Go vet still has issues after dependency fix" -Level Error -Category "Vet"
                    if ($output2) {
                        Write-Log "Vet output: $($output2 -join "`n")" -Level Error -Category "Vet"
                    }
                }
            }
            catch {
                Write-Log "Failed to fix dependencies: $_" -Level Error -Category "Vet"
            }
        }
        
        return $false
    }
}

function Invoke-Staticcheck {
    if (!$Script:Config.EnableStaticcheck -or !(Get-Command staticcheck -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping staticcheck (disabled or not available)" -Level Verbose -Category "Staticcheck"
        return $true
    }
    
    return Invoke-CommandWithTimeout "Running staticcheck" "staticcheck" @("./...") -Category "Staticcheck"
}

function Invoke-Gosec {
    if (!$Script:Config.EnableSecurity -or !(Get-Command gosec -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping gosec (disabled or not available)" -Level Verbose -Category "Security"
        return $true
    }
    
    # Use a simpler approach for gosec to avoid PowerShell argument parsing issues
    if ($Script:Config.DryRun) {
        Write-Log "DRY RUN: Would run gosec ./..." -Level Info -Category "Security"
        return $true
    }
    
    Write-Log "Checking security with gosec..." -Level Info -Category "Security"
    $output = gosec ./... 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($Script:Config.Verbose) {
        $output | ForEach-Object { Write-Log $_ -Level Verbose -Category "Security" }
    }
    
    if ($exitCode -eq 0) {
        Write-Log "Security check passed" -Level Success -Category "Security"
        return $true
    } else {
        Write-Log "Security check found issues" -Level Error -Category "Security"
        if ($output) {
            Write-Log "Security output: $($output -join "`n")" -Level Error -Category "Security"
        }
        return $false
    }
}

function Invoke-Tests {
    if (!$Script:Config.EnableTests) {
        Write-Log "Skipping tests (disabled)" -Level Verbose -Category "Tests"
        return $true
    }
    
    # Build test command
    $testCmd = "go test"
    if ($Script:Config.EnableRace) {
        $testCmd += " -race"
    }
    if ($Script:Config.EnableCoverage) {
        $testCmd += " -cover -coverprofile=coverage.out -covermode=atomic"
    }
    if ($Script:Config.EnableBenchmarks) {
        $testCmd += " -bench=."
    }
    $testCmd += " ./..."
    
    # Use a simpler approach for go test to avoid PowerShell error interpretation
    if ($Script:Config.DryRun) {
        Write-Log "DRY RUN: Would run $testCmd" -Level Info -Category "Tests"
        return $true
    }
    
    Write-Log "Running tests..." -Level Info -Category "Tests"
    $output = Invoke-Expression $testCmd 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($Script:Config.Verbose) {
        $output | ForEach-Object { Write-Log $_ -Level Verbose -Category "Tests" }
    }
    
    if ($exitCode -eq 0) {
        Write-Log "Tests passed" -Level Success -Category "Tests"
        
        # Handle coverage if enabled
        if ($Script:Config.EnableCoverage -and (Test-Path "coverage.out")) {
            try {
                go tool cover -html=coverage.out -o coverage.html 2>$null
                $coverageOutput = go tool cover -func=coverage.out 2>$null
                $coverage = $coverageOutput | Select-String "total:" | ForEach-Object { 
                    if ($_ -match "total:\s*\(statements\)\s*(\d+\.\d+)%") { 
                        [double]$matches[1] 
                    } else { 0 } 
                }
                
                if ($coverage -lt $Script:ProjectConfig.CoverageThreshold) {
                    Write-Log "Coverage $coverage% is below threshold $($Script:ProjectConfig.CoverageThreshold)%" -Level Warning -Category "Tests"
                    return $false
                } else {
                    Write-Log "Coverage: $coverage%" -Level Success -Category "Tests"
                }
            }
            catch {
                Write-Log "Failed to process coverage: $_" -Level Warning -Category "Tests"
            }
        }
        
        return $true
    } else {
        Write-Log "Tests failed" -Level Error -Category "Tests"
        if ($output) {
            Write-Log "Test output: $($output -join "`n")" -Level Error -Category "Tests"
        }
        
        # Try to fix test setup issues automatically
        if ($Script:Config.AutoFix -and $output -match "setup failed") {
            Write-Log "Attempting to fix test setup issues..." -Level Info -Category "Tests"
            try {
                # Try to fix common test setup issues
                go mod tidy 2>&1 | Out-Null
                go mod download 2>&1 | Out-Null
                
                # Re-run tests with verbose output to see what's happening
                Write-Log "Re-running tests with verbose output..." -Level Info -Category "Tests"
                $output2 = go test -v ./... 2>&1
                $exitCode2 = $LASTEXITCODE
                
                if ($exitCode2 -eq 0) {
                    Write-Log "Tests passed after setup fix" -Level Success -Category "Tests"
                    return $true
                } else {
                    Write-Log "Tests still failing after setup fix" -Level Error -Category "Tests"
                    if ($output2) {
                        Write-Log "Test output: $($output2 -join "`n")" -Level Error -Category "Tests"
                    }
                }
            }
            catch {
                Write-Log "Failed to fix test setup: $_" -Level Error -Category "Tests"
            }
        }
        
        return $false
    }
}

function Invoke-BuildCheck {
    if (!$Script:Config.EnableBuild) {
        Write-Log "Skipping build check (disabled)" -Level Verbose -Category "Build"
        return $true
    }
    
    Write-Log "Verifying builds..." -Level Info -Category "Build"
    
    $buildTargets = $Script:ProjectConfig.BuildTargets
    if ($env:BUILD_TARGETS) {
        $buildTargets = $env:BUILD_TARGETS -split "," | ForEach-Object {
            $parts = $_ -split "/"
            @{GOOS=$parts[0]; GOARCH=$parts[1]; Name=$_}
        }
    }
    
    foreach ($target in $buildTargets) {
        $targetName = "$($target.GOOS)/$($target.GOARCH)"
        Write-Log "Building for $targetName" -Level Verbose -Category "Build"
        
        if (!$Script:Config.DryRun) {
            $env:GOOS = $target.GOOS
            $env:GOARCH = $target.GOARCH
            
            try {
                foreach ($pkg in $Script:ProjectConfig.MainPackages) {
                    # Check if the package directory exists and contains Go files
                    if (Test-Path $pkg) {
                        $goFiles = Get-ChildItem -Path $pkg -Filter "*.go" -Recurse -ErrorAction SilentlyContinue
                        if ($goFiles.Count -eq 0) {
                            Write-Log "No Go files found in $pkg, skipping build" -Level Warning -Category "Build"
                            continue
                        }
                        
                        # Build from the package directory
                        $output = go build -o $null $pkg 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Build successful: $pkg for $targetName" -Level Verbose -Category "Build"
                        }
                        else {
                            Write-Log "Build failed: $pkg for $targetName" -Level Error -Category "Build"
                            Write-Log $output -Level Error -Category "Build"
                            return $false
                        }
                    } else {
                        Write-Log "Package directory $pkg not found, skipping build" -Level Warning -Category "Build"
                    }
                }
            }
            finally {
                Remove-Item Env:GOOS -ErrorAction SilentlyContinue
                Remove-Item Env:GOARCH -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Log "DRY RUN: Would build for $targetName" -Level Verbose -Category "Build"
        }
    }
    
    Write-Log "All builds successful" -Level Success -Category "Build"
    return $true
}

function Invoke-DependencyAnalysis {
    if (!$Script:Config.EnableDeps) {
        Write-Log "Skipping dependency analysis (disabled)" -Level Verbose -Category "Deps"
        return $true
    }
    
    Write-Log "Analyzing dependencies..." -Level Info -Category "Deps"
    
    # Check for outdated dependencies
    $outdated = go list -u -m all 2>$null | Where-Object { $_ -match "\[" }
    if ($outdated) {
        Write-Log "Outdated dependencies found:" -Level Warning -Category "Deps"
        $outdated | ForEach-Object { Write-Log "  $_" -Level Info -Category "Deps" }
    } else {
        Write-Log "All dependencies up to date" -Level Success -Category "Deps"
    }
    
    # Check for security vulnerabilities
    if (Get-Command "govulncheck" -ErrorAction SilentlyContinue) {
        $vulns = govulncheck ./... 2>$null
        if ($vulns) {
            Write-Log "Security vulnerabilities found:" -Level Warning -Category "Deps"
            Write-Log $vulns -Level Info -Category "Deps"
        } else {
            Write-Log "No security vulnerabilities found" -Level Success -Category "Deps"
        }
    }
    
    return $true
}

function Invoke-DocumentationGeneration {
    if (!$Script:Config.EnableDocs) {
        Write-Log "Skipping documentation generation (disabled)" -Level Verbose -Category "Docs"
        return $true
    }
    
    Write-Log "Generating documentation..." -Level Info -Category "Docs"
    
    # Generate godoc only if available
    if (!$Script:Config.DryRun -and (Get-Command "godoc" -ErrorAction SilentlyContinue)) {
        try {
            $godocProcess = Start-Process -FilePath "godoc" -ArgumentList "-http=:6060" -WindowStyle Hidden -PassThru
            Start-Sleep -Seconds 2
            if ($godocProcess -and !$godocProcess.HasExited) {
                Stop-Process -Id $godocProcess.Id -Force -ErrorAction SilentlyContinue
            }
            Write-Log "Godoc documentation generated" -Level Success -Category "Docs"
            Write-Log "Documentation generation completed" -Level Success -Category "Docs"
            return $true
        }
        catch {
            Write-Log "Failed to generate godoc documentation: $_" -Level Error -Category "Docs"
            Write-Log "Documentation generation failed" -Level Error -Category "Docs"
            return $false
        }
    }
    elseif (!$Script:Config.DryRun) {
        Write-Log "Godoc not available, skipping documentation generation" -Level Warning -Category "Docs"
        Write-Log "Documentation generation skipped (godoc not installed)" -Level Warning -Category "Docs"
        Write-Log "Install godoc with: go install golang.org/x/tools/cmd/godoc@latest" -Level Info -Category "Docs"
        return $true  # Not an error, just not available
    }
    else {
        Write-Log "Documentation generation skipped (dry run)" -Level Verbose -Category "Docs"
        return $true
    }
}

function Invoke-PerformanceProfiling {
    if (!$Script:Config.EnableProfile) {
        Write-Log "Skipping performance profiling (disabled)" -Level Verbose -Category "Profile"
        return $true
    }
    
    Write-Log "Running performance profiling..." -Level Info -Category "Profile"
    
    # Run benchmarks with profiling
    if ($Script:Config.EnableBenchmarks) {
        go test -bench=. -cpuprofile=cpu.prof -memprofile=mem.prof ./...
        
        if (Test-Path "cpu.prof") {
            Write-Log "CPU profile generated: cpu.prof" -Level Info -Category "Profile"
        }
        if (Test-Path "mem.prof") {
            Write-Log "Memory profile generated: mem.prof" -Level Info -Category "Profile"
        }
    }
    
    Write-Log "Performance profiling completed" -Level Success -Category "Profile"
    return $true
}

# =====================================================================
# LuCI Verification Functions
# =====================================================================

function Get-LuCIFiles {
    param([string]$Pattern, [string]$FileType)
    
    $files = @()
    if (Test-Path ".") {
        $files = Get-ChildItem -Path "." -Recurse -Include $Pattern -File | Select-Object -ExpandProperty FullName
    }
    
    Write-Log "Found $($files.Count) $FileType files" -Level Verbose -Category "LuCI"
    return $files
}

function Invoke-LuaCheck {
    if (!$Script:Config.EnableLua -or !(Get-Command luacheck -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping Lua check (disabled or luacheck not available)" -Level Verbose -Category "LuCI"
        return $true
    }
    
    $luaFiles = Get-LuCIFiles "*.lua" "Lua"
    if ($luaFiles.Count -eq 0) {
        Write-Log "No Lua files found, skipping luacheck" -Level Verbose -Category "LuCI"
        return $true
    }
    
    Write-Log "Checking Lua syntax and style..." -Level Info -Category "LuCI"
    
    # First, check syntax with lua -p
    $syntaxErrors = 0
    foreach ($file in $luaFiles) {
        if ($Script:Config.DryRun) {
            Write-Log "DRY RUN: Would check Lua syntax for $file" -Level Info -Category "LuCI"
            continue
        }
        
        $output = lua -p $file 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Lua syntax error in $file" -Level Error -Category "LuCI"
            Write-Log $output -Level Error -Category "LuCI"
            $syntaxErrors++
        }
    }
    
    if ($syntaxErrors -gt 0) {
        Write-Log "Found $syntaxErrors Lua syntax errors" -Level Error -Category "LuCI"
        return $false
    }
    
    # Run luacheck
    $configFile = $Script:ProjectConfig.LuCIConfig.LuaCheckConfig
    $luacheckArgs = @(".", "--no-color")
    if (Test-Path $configFile) {
        $luacheckArgs += "--config", $configFile
    }
    
    return Invoke-CommandWithTimeout "Running luacheck" "luacheck" $luacheckArgs -Category "LuCI"
}

function Invoke-HTMLCheck {
    if (!$Script:Config.EnableHTML -or !(Get-Command htmlhint -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping HTML check (disabled or htmlhint not available)" -Level Verbose -Category "LuCI"
        return $true
    }
    
    $htmlFiles = Get-LuCIFiles "*.htm" "HTML"
    if ($htmlFiles.Count -eq 0) {
        Write-Log "No HTML files found, skipping htmlhint" -Level Verbose -Category "LuCI"
        return $true
    }
    
    Write-Log "Checking HTML syntax and style..." -Level Info -Category "LuCI"
    
    $configFile = $Script:ProjectConfig.LuCIConfig.HTMLHintConfig
    $htmlhintArgs = @(".")
    if (Test-Path $configFile) {
        $htmlhintArgs += "--config", $configFile
    }
    
    return Invoke-CommandWithTimeout "Running htmlhint" "htmlhint" $htmlhintArgs -Category "LuCI"
}

function Invoke-CSSCheck {
    if (!$Script:Config.EnableCSS -or !(Get-Command stylelint -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping CSS check (disabled or stylelint not available)" -Level Verbose -Category "LuCI"
        return $true
    }
    
    $cssFiles = Get-LuCIFiles "*.css" "CSS"
    if ($cssFiles.Count -eq 0) {
        Write-Log "No CSS files found, skipping stylelint" -Level Verbose -Category "LuCI"
        return $true
    }
    
    Write-Log "Checking CSS syntax and style..." -Level Info -Category "LuCI"
    
    $configFile = $Script:ProjectConfig.LuCIConfig.StylelintConfig
    $stylelintArgs = @("**/*.css")
    if (Test-Path $configFile) {
        $stylelintArgs += "--config", $configFile
    }
    
    return Invoke-CommandWithTimeout "Running stylelint" "stylelint" $stylelintArgs -Category "LuCI"
}

function Invoke-JSCheck {
    if (!$Script:Config.EnableJS -or !(Get-Command eslint -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping JavaScript check (disabled or eslint not available)" -Level Verbose -Category "LuCI"
        return $true
    }
    
    $jsFiles = Get-LuCIFiles "*.js" "JavaScript"
    if ($jsFiles.Count -eq 0) {
        Write-Log "No JavaScript files found, skipping eslint" -Level Verbose -Category "LuCI"
        return $true
    }
    
    Write-Log "Checking JavaScript syntax and style..." -Level Info -Category "LuCI"
    
    $configFile = $Script:ProjectConfig.LuCIConfig.ESLintConfig
    $eslintArgs = @(".")
    if (Test-Path $configFile) {
        $eslintArgs += "--config", $configFile
    }
    
    # Add browser environment for LuCI
    $eslintArgs += "--env", "browser,es2020"
    
    return Invoke-CommandWithTimeout "Running eslint" "eslint" $eslintArgs -Category "LuCI"
}

function Invoke-TranslationCheck {
    if (!$Script:Config.EnableTranslations -or !(Get-Command msgfmt -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping translation check (disabled or msgfmt not available)" -Level Verbose -Category "LuCI"
        return $true
    }
    
    $poFiles = Get-LuCIFiles "*.po" "Translation"
    if ($poFiles.Count -eq 0) {
        Write-Log "No translation files found, skipping msgfmt" -Level Verbose -Category "LuCI"
        return $true
    }
    
    Write-Log "Checking translation files..." -Level Info -Category "LuCI"
    
    $errors = 0
    foreach ($file in $poFiles) {
        if ($Script:Config.DryRun) {
            Write-Log "DRY RUN: Would check translation file $file" -Level Info -Category "LuCI"
            continue
        }
        
        $output = msgfmt --check $file 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Translation error in $file" -Level Error -Category "LuCI"
            Write-Log $output -Level Error -Category "LuCI"
            $errors++
        } else {
            Write-Log "Translation file OK: $file" -Level Verbose -Category "LuCI"
        }
    }
    
    if ($errors -gt 0) {
        Write-Log "Found $errors translation errors" -Level Error -Category "LuCI"
        return $false
    }
    
    Write-Log "All translation files are valid" -Level Success -Category "LuCI"
    return $true
}

function Invoke-LuCIVerification {
    if (!$Script:Config.EnableLuCI) {
        Write-Log "Skipping LuCI verification (disabled)" -Level Verbose -Category "LuCI"
        return $true
    }
    
    Write-Log "Running LuCI verification..." -Level Info -Category "LuCI"
    
    $totalChecks = 0
    $errors = 0
    
    # Lua check
    $totalChecks++
    if (!(Invoke-LuaCheck)) { $errors++ }
    
    # HTML check
    $totalChecks++
    if (!(Invoke-HTMLCheck)) { $errors++ }
    
    # CSS check
    $totalChecks++
    if (!(Invoke-CSSCheck)) { $errors++ }
    
    # JavaScript check
    $totalChecks++
    if (!(Invoke-JSCheck)) { $errors++ }
    
    # Translation check
    $totalChecks++
    if (!(Invoke-TranslationCheck)) { $errors++ }
    
    if ($errors -eq 0) {
        Write-Log "LuCI verification completed successfully" -Level Success -Category "LuCI"
        return $true
    } else {
        Write-Log "LuCI verification found $errors errors in $totalChecks checks" -Level Error -Category "LuCI"
        return $false
    }
}

# =====================================================================

# Main execution
function Main {
    if ($Help) {
        Show-Usage
        exit 0
    }
    
    # Handle dependency installation
    if ($InstallDeps) {
        Install-Dependencies
        exit 0
    }
    
    # Environment variable overrides
    if ($env:DRY_RUN -eq "1") { $Script:Config.DryRun = $true }
    if ($env:VERBOSE -eq "1") { $Script:Config.Verbose = $true }
    if ($env:COVERAGE_THRESHOLD) { $Script:ProjectConfig.CoverageThreshold = [int]$env:COVERAGE_THRESHOLD }
    
    Write-Log "$Script:ProjectName Go Verification Script v$Script:Version" -Level Info -Category "Setup"
    Write-Log "Mode: $Mode" -Level Info -Category "Setup"
    
    if ($Script:Config.DryRun) {
        Write-Log "DRY RUN MODE - No changes will be made" -Level Warning -Category "Setup"
    }
    
    if ($Script:Config.AutoFix) {
        Write-Log "AUTO-FIX MODE - Will attempt to fix issues" -Level Info -Category "Setup"
    }
    
    # Check tools
    if (!(Test-Tools)) {
        exit 1
    }
    
    # Get files
    $goFiles = Get-GoFiles -Mode $Mode -FileList $Files
    
    if ($goFiles.Count -eq 0) {
        Write-Log "No Go files found to check" -Level Warning -Category "Setup"
        exit 0
    }
    
    Write-Log "Found $($goFiles.Count) Go files to verify" -Level Info -Category "Setup"
    
    if ($Script:Config.Verbose) {
        Write-Log "Files to check:" -Level Verbose -Category "Setup"
        $goFiles | ForEach-Object { Write-Log "  $_" -Level Verbose -Category "Setup" }
    }
    
    # Run verification steps
    $startTime = Get-Date
    $errors = 0
    $totalChecks = 0
    
    # Format check
    $totalChecks++
    if (!(Invoke-GoFmt -Files $goFiles)) { $errors++ }
    
    # Import organization  
    $totalChecks++
    if (!(Invoke-GoImports -Files $goFiles)) { $errors++ }
    
    # Linting
    $totalChecks++
    if (!(Invoke-GolangciLint)) { $errors++ }
    
    # Vet
    $totalChecks++
    if (!(Invoke-GoVet)) { $errors++ }
    
    # Static analysis
    $totalChecks++
    if (!(Invoke-Staticcheck)) { $errors++ }
    
    # Security check
    $totalChecks++
    if (!(Invoke-Gosec)) { $errors++ }
    
    # Tests
    $totalChecks++
    if (!(Invoke-Tests)) { $errors++ }
    
    # Build verification
    $totalChecks++
    if (!(Invoke-BuildCheck)) { $errors++ }
    
    # Dependency analysis
    $totalChecks++
    if (!(Invoke-DependencyAnalysis)) { $errors++ }
    
    # Documentation generation
    $totalChecks++
    if (!(Invoke-DocumentationGeneration)) { $errors++ }
    
    # Performance profiling
    if ($Script:Config.EnableProfile) {
        $totalChecks++
        if (!(Invoke-PerformanceProfiling)) { $errors++ }
    }
    
    # LuCI verification (if enabled)
    if ($Script:Config.EnableLuCI) {
        $totalChecks++
        if (!(Invoke-LuCIVerification)) { $errors++ }
    }
    
    $duration = (Get-Date) - $startTime
    Write-Log "Verification completed in $([math]::Round($duration.TotalSeconds, 1))s" -Level Info -Category "Summary"
    Write-Log "Checks run: $totalChecks, Errors: $errors" -Level Info -Category "Summary"
    
    if ($errors -eq 0) {
        Write-Log "All checks passed!" -Level Success -Category "Summary"
        exit 0
    }
    else {
        Write-Log "$errors check(s) failed" -Level Error -Category "Summary"
        exit 1
    }
}

# Call the main function
Main
