# Go Verification Script for RUTOS Starlink Failover (PowerShell)
# Supports: all files, specific files, and pre-commit verification

param(
    [Parameter(Position=0)]
    [ValidateSet("all", "files", "staged", "commit")]
    [string]$Mode = "all",
    
    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Files = @(),
    
    [switch]$Help,
    [switch]$VerboseOutputOutput,
    [switch]$Quiet,
    [switch]$DryRun,
    [switch]$NoFormat,
    [switch]$NoImports,
    [switch]$NoLint,
    [switch]$NoVet,
    [switch]$NoStaticcheck,
    [switch]$NoSecurity,
    [switch]$NoTests,
    [switch]$NoBuild,
    [switch]$Fix
)

$Script:ScriptName = "go-verify.ps1"
$Script:Version = "1.0.0"

# Configuration
$Script:Config = @{
    EnableFormat     = !$NoFormat
    EnableImports    = !$NoImports
    EnableLint       = !$NoLint
    EnableVet        = !$NoVet
    EnableStaticcheck = !$NoStaticcheck
    EnableSecurity   = !$NoSecurity
    EnableTests      = !$NoTests
    EnableBuild      = !$NoBuild
}

# Colors for console output
$Script:Colors = @{
    Red     = "Red"
    Green   = "Green"
    Yellow  = "Yellow"
    Blue    = "Blue"
    Cyan    = "Cyan"
    Gray    = "Gray"
}

function Show-Usage {
    @"
Go Verification Script v$Script:Version

Usage: $Script:ScriptName [MODE] [OPTIONS] [FILES...]

MODES:
    all                 - Check all Go files in project (default)
    files FILE1 FILE2   - Check specific files or patterns
    staged              - Check staged files for pre-commit
    commit              - Check files in git diff --cached

OPTIONS:
    -Help              - Show this help
    -Verbose           - Verbose output
    -Quiet             - Quiet mode (errors only)
    -DryRun            - Show what would be done
    -NoFormat          - Skip gofmt formatting
    -NoImports         - Skip goimports
    -NoLint            - Skip golangci-lint
    -NoVet             - Skip go vet
    -NoStaticcheck     - Skip staticcheck
    -NoSecurity        - Skip gosec security check
    -NoTests           - Skip tests
    -NoBuild           - Skip build verification
    -Fix               - Attempt to fix issues automatically

EXAMPLES:
    .\$Script:ScriptName all                           # Check all files
    .\$Script:ScriptName files pkg\logx\*.go          # Check specific files
    .\$Script:ScriptName staged                        # Check staged files
    .\$Script:ScriptName -NoTests all                  # Check without tests
    .\$Script:ScriptName -DryRun all                   # Show what would run

ENVIRONMENT:
    `$env:GO_VERIFY_CONFIG   - Path to config file
    `$env:DRY_RUN=1         - Enable dry-run mode
    `$env:VERBOSE=1         - Enable verbose mode
"@
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Verbose")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    switch ($Level) {
        "Info" {
            if (!$Quiet) {
                Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor $Script:Colors.Blue
            }
        }
        "Success" {
            Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor $Script:Colors.Green
        }
        "Warning" {
            Write-Host "[$timestamp] [WARNING] $Message" -ForegroundColor $Script:Colors.Yellow
        }
        "Error" {
            Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor $Script:Colors.Red
        }
        "Verbose" {
            if ($VerboseOutput) {
                Write-Host "[$timestamp] [VERBOSE] $Message" -ForegroundColor $Script:Colors.Gray
            }
        }
    }
}

function Test-Command {
    param(
        [string]$Command,
        [string]$InstallCommand = ""
    )
    
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log "Tool '$Command' not found" -Level Warning
        if ($InstallCommand) {
            Write-Log "Install with: $InstallCommand" -Level Info
        }
        return $false
    }
}

function Test-Tools {
    Write-Log "Checking required tools..." -Level Info
    
    $missingTools = @()
    
    # Core Go tools
    if (!(Test-Command "go" "Install Go from https://golang.org/")) {
        $missingTools += "go"
    }
    
    # Additional tools
    if ($Script:Config.EnableImports -and !(Test-Command "goimports" "go install golang.org/x/tools/cmd/goimports@latest")) {
        $missingTools += "goimports"
    }
    
    if ($Script:Config.EnableLint -and !(Test-Command "golangci-lint" "go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest")) {
        $missingTools += "golangci-lint"
    }
    
    if ($Script:Config.EnableStaticcheck -and !(Test-Command "staticcheck" "go install honnef.co/go/tools/cmd/staticcheck@latest")) {
        $missingTools += "staticcheck"
    }
    
    if ($Script:Config.EnableSecurity -and !(Test-Command "gosec" "go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest")) {
        $missingTools += "gosec"
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Log "Missing tools: $($missingTools -join ', ')" -Level Error
        Write-Log "Install missing tools and run again, or use -No* parameters to skip checks" -Level Info
        return $false
    }
    
    Write-Log "All required tools available" -Level Success
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
            $goFiles = Get-ChildItem -Path . -Filter "*.go" -Recurse | 
                Where-Object { $_.FullName -notmatch "vendor|\.git" } |
                ForEach-Object { $_.FullName }
        }
        "files" {
            foreach ($pattern in $FileList) {
                if ($pattern -like "*\**" -or $pattern -like "*/*") {
                    # Handle glob patterns
                    $goFiles += Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -eq ".go" } |
                        ForEach-Object { $_.FullName }
                }
                elseif (Test-Path $pattern -PathType Leaf) {
                    if ([System.IO.Path]::GetExtension($pattern) -eq ".go") {
                        $goFiles += (Resolve-Path $pattern).Path
                    }
                    else {
                        Write-Log "File is not a Go file: $pattern" -Level Warning
                    }
                }
                elseif (Test-Path $pattern -PathType Container) {
                    $goFiles += Get-ChildItem -Path $pattern -Filter "*.go" -Recurse |
                        ForEach-Object { $_.FullName }
                }
                else {
                    Write-Log "File not found: $pattern" -Level Warning
                }
            }
        }
        { $_ -eq "staged" -or $_ -eq "commit" } {
            try {
                $goFiles = git diff --cached --name-only --diff-filter=ACM |
                    Where-Object { $_ -like "*.go" } |
                    ForEach-Object { (Resolve-Path $_).Path }
            }
            catch {
                Write-Log "Error getting staged files: $_" -Level Error
            }
        }
    }
    
    return $goFiles | Sort-Object -Unique
}

function Invoke-Command {
    param(
        [string]$Description,
        [string]$Command,
        [string[]]$Arguments = @()
    )
    
    if ($DryRun) {
        Write-Log "DRY RUN: $Description" -Level Info
        Write-Log "Would run: $Command $($Arguments -join ' ')" -Level Verbose
        return $true
    }
    
    Write-Log $Description -Level Info
    Write-Log "Running: $Command $($Arguments -join ' ')" -Level Verbose
    
    try {
        if ($VerboseOutput) {
            & $Command @Arguments
        }
        else {
            & $Command @Arguments 2>$null | Out-Null
        }
        return $LASTEXITCODE -eq 0
    }
    catch {
        Write-Log "Command failed: $_" -Level Error
        return $false
    }
}

function Invoke-GoFmt {
    param([string[]]$Files)
    
    if (!$Script:Config.EnableFormat) {
        Write-Log "Skipping gofmt (disabled)" -Level Verbose
        return $true
    }
    
    if ($Files.Count -eq 0) {
        Write-Log "No Go files to format" -Level Warning
        return $true
    }
    
    Write-Log "Running gofmt formatting..." -Level Info
    
    # Check if files need formatting
    $unformatted = @()
    foreach ($file in $Files) {
        $result = gofmt -l $file 2>$null
        if ($result) {
            $unformatted += $file
        }
    }
    
    if ($unformatted.Count -gt 0) {
        Write-Log "Files need formatting:" -Level Warning
        $unformatted | ForEach-Object { Write-Log "  $_" -Level Info }
        
        if (!$DryRun) {
            foreach ($file in $unformatted) {
                gofmt -s -w $file
            }
            Write-Log "Files formatted" -Level Success
        }
        else {
            Write-Log "DRY RUN: Would format files" -Level Info
        }
    }
    else {
        Write-Log "All files properly formatted" -Level Success
    }
    
    return $true
}

function Invoke-GoImports {
    param([string[]]$Files)
    
    if (!$Script:Config.EnableImports -or !(Get-Command goimports -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping goimports (disabled or not available)" -Level Verbose
        return $true
    }
    
    if ($Files.Count -eq 0) {
        Write-Log "No Go files for import organization" -Level Warning
        return $true
    }
    
    foreach ($file in $Files) {
        if (!$DryRun) {
            goimports -w $file
        }
    }
    
    Write-Log "Import organization completed" -Level Success
    return $true
}

function Invoke-GolangciLint {
    if (!$Script:Config.EnableLint -or !(Get-Command golangci-lint -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping golangci-lint (disabled or not available)" -Level Verbose
        return $true
    }
    
    return Invoke-Command "Running golangci-lint" "golangci-lint" @("run")
}

function Invoke-GoVet {
    if (!$Script:Config.EnableVet) {
        Write-Log "Skipping go vet (disabled)" -Level Verbose
        return $true
    }
    
    return Invoke-Command "Running go vet" "go" @("vet", "./...")
}

function Invoke-Staticcheck {
    if (!$Script:Config.EnableStaticcheck -or !(Get-Command staticcheck -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping staticcheck (disabled or not available)" -Level Verbose
        return $true
    }
    
    return Invoke-Command "Running staticcheck" "staticcheck" @("./...")
}

function Invoke-Gosec {
    if (!$Script:Config.EnableSecurity -or !(Get-Command gosec -ErrorAction SilentlyContinue)) {
        Write-Log "Skipping gosec (disabled or not available)" -Level Verbose
        return $true
    }
    
    return Invoke-Command "Checking security with gosec" "gosec" @("./...")
}

function Invoke-Tests {
    if (!$Script:Config.EnableTests) {
        Write-Log "Skipping tests (disabled)" -Level Verbose
        return $true
    }
    
    return Invoke-Command "Running tests with race detection" "go" @("test", "-race", "./...")
}

function Invoke-BuildCheck {
    if (!$Script:Config.EnableBuild) {
        Write-Log "Skipping build check (disabled)" -Level Verbose
        return $true
    }
    
    Write-Log "Verifying build..." -Level Info
    
    $targets = @(
        @{GOOS="linux"; GOARCH="amd64"},
        @{GOOS="linux"; GOARCH="arm"},
        @{GOOS="linux"; GOARCH="mips"}
    )
    
    foreach ($target in $targets) {
        $targetName = "$($target.GOOS)/$($target.GOARCH)"
        Write-Log "Building for $targetName" -Level Verbose
        
        if (!$DryRun) {
            $env:GOOS = $target.GOOS
            $env:GOARCH = $target.GOARCH
            
            try {
                $output = go build -o $null -ldflags="-s -w" ./cmd/starfail-sysmgmt 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Build successful for starfail-sysmgmt $targetName" -Level Verbose
                }
                else {
                    Write-Log "Build failed for starfail-sysmgmt $targetName" -Level Error
                    Write-Log $output -Level Error
                    return $false
                }
                
                $output = go build -o $null -ldflags="-s -w" ./cmd/starfaild 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Build successful for starfaild $targetName" -Level Verbose
                }
                else {
                    Write-Log "Build failed for starfaild $targetName" -Level Error
                    Write-Log $output -Level Error
                    return $false
                }
            }
            finally {
                Remove-Item Env:GOOS -ErrorAction SilentlyContinue
                Remove-Item Env:GOARCH -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Log "DRY RUN: Would build for $targetName" -Level Verbose
        }
    }
    
    Write-Log "All builds successful" -Level Success
    return $true
}

# Main execution
function Main {
    if ($Help) {
        Show-Usage
        exit 0
    }
    
    # Environment variable overrides
    if ($env:DRY_RUN -eq "1") { $Script:DryRun = $true }
    if ($env:VERBOSE -eq "1") { $Script:Verbose = $true }
    
    Write-Log "Go Verification Script v$Script:Version" -Level Info
    Write-Log "Mode: $Mode" -Level Info
    
    if ($DryRun) {
        Write-Log "DRY RUN MODE - No changes will be made" -Level Warning
    }
    
    # Check tools
    if (!(Test-Tools)) {
        exit 1
    }
    
    # Get files
    $goFiles = Get-GoFiles -Mode $Mode -FileList $Files
    
    if ($goFiles.Count -eq 0) {
        Write-Log "No Go files found to check" -Level Warning
        exit 0
    }
    
    Write-Log "Found $($goFiles.Count) Go files to verify" -Level Info
    
    if ($VerboseOutput) {
        Write-Log "Files to check:" -Level Verbose
        $goFiles | ForEach-Object { Write-Log "  $_" -Level Verbose }
    }
    
    # Run verification steps
    $startTime = Get-Date
    $errors = 0
    
    # Format check
    if (!(Invoke-GoFmt -Files $goFiles)) { $errors++ }
    
    # Import organization  
    if (!(Invoke-GoImports -Files $goFiles)) { $errors++ }
    
    # Linting
    if (!(Invoke-GolangciLint)) { $errors++ }
    
    # Vet
    if (!(Invoke-GoVet)) { $errors++ }
    
    # Static analysis
    if (!(Invoke-Staticcheck)) { $errors++ }
    
    # Security check
    if (!(Invoke-Gosec)) { $errors++ }
    
    # Tests
    if (!(Invoke-Tests)) { $errors++ }
    
    # Build verification
    if (!(Invoke-BuildCheck)) { $errors++ }
    
    $duration = (Get-Date) - $startTime
    Write-Log "Verification completed in $([math]::Round($duration.TotalSeconds, 1))s" -Level Info
    
    if ($errors -eq 0) {
        Write-Log "All checks passed! ✅" -Level Success
        exit 0
    }
    else {
        Write-Log "$errors check(s) failed ❌" -Level Error
        exit 1
    }
}

# Execute main function
Main
