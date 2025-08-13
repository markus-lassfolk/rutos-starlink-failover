#!/bin/sh
set -e

# Go Verification Script for RUTOS Starlink Failover
# Supports: all files, specific files, and pre-commit verification

SCRIPT_NAME="go-verify.sh"
VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENABLE_FORMAT=1
ENABLE_IMPORTS=1
ENABLE_LINT=1
ENABLE_VET=1
ENABLE_STATICCHECK=1
ENABLE_SECURITY=1
ENABLE_TESTS=1
ENABLE_BUILD=1

# Flags
DRY_RUN=0
VERBOSE=0
QUIET=0
PRE_COMMIT=0

# Tool detection
TOOLS_MISSING=""

print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [MODE] [FILES...]

MODES:
    all                 - Check all Go files in project (default)
    files FILE1 FILE2   - Check specific files or patterns
    staged              - Check staged files for pre-commit
    commit              - Check files in git diff --cached

OPTIONS:
    -h, --help         - Show this help
    -v, --verbose      - Verbose output
    -q, --quiet        - Quiet mode (errors only)
    -n, --dry-run      - Show what would be done
    --no-format        - Skip gofmt formatting
    --no-imports       - Skip goimports
    --no-lint          - Skip golangci-lint
    --no-vet           - Skip go vet
    --no-staticcheck   - Skip staticcheck
    --no-security      - Skip gosec security check
    --no-tests         - Skip tests
    --no-build         - Skip build verification
    --fix              - Attempt to fix issues automatically

EXAMPLES:
    $SCRIPT_NAME all                           # Check all files
    $SCRIPT_NAME files pkg/logx/*.go          # Check specific files
    $SCRIPT_NAME staged                        # Check staged files
    $SCRIPT_NAME --no-tests pkg/collector/    # Check without tests
    $SCRIPT_NAME --dry-run all                # Show what would run

ENVIRONMENT:
    GO_VERIFY_CONFIG   - Path to config file
    DRY_RUN=1         - Enable dry-run mode
    VERBOSE=1         - Enable verbose mode
EOF
}

log_info() {
    if [ "$QUIET" = "0" ]; then
        printf "${BLUE}[INFO]${NC} %s\n" "$*"
    fi
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$*"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

log_verbose() {
    if [ "$VERBOSE" = "1" ]; then
        printf "${YELLOW}[VERBOSE]${NC} %s\n" "$*"
    fi
}

run_command() {
    local description="$1"
    shift
    local command="$*"
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "DRY RUN: $description"
        log_verbose "Would run: $command"
        return 0
    fi
    
    log_info "$description"
    log_verbose "Running: $command"
    
    if [ "$VERBOSE" = "1" ]; then
        eval "$command"
    else
        eval "$command" >/dev/null 2>&1
    fi
}

check_tool() {
    local tool="$1"
    local install_cmd="$2"
    
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_warning "Tool '$tool' not found"
        if [ -n "$install_cmd" ]; then
            log_info "Install with: $install_cmd"
        fi
        TOOLS_MISSING="$TOOLS_MISSING $tool"
        return 1
    fi
    return 0
}

check_tools() {
    log_info "Checking required tools..."
    
    # Core Go tools (should be available)
    check_tool "go" "Install Go from https://golang.org/"
    check_tool "gofmt" "Part of Go installation"
    
    # Additional tools
    if [ "$ENABLE_IMPORTS" = "1" ]; then
        check_tool "goimports" "go install golang.org/x/tools/cmd/goimports@latest"
    fi
    
    if [ "$ENABLE_LINT" = "1" ]; then
        check_tool "golangci-lint" "go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
    fi
    
    if [ "$ENABLE_STATICCHECK" = "1" ]; then
        check_tool "staticcheck" "go install honnef.co/go/tools/cmd/staticcheck@latest"
    fi
    
    if [ "$ENABLE_SECURITY" = "1" ]; then
        check_tool "gosec" "go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest"
    fi
    
    if [ -n "$TOOLS_MISSING" ]; then
        log_error "Missing tools:$TOOLS_MISSING"
        log_info "Install missing tools and run again, or use --no-* flags to skip checks"
        return 1
    fi
    
    log_success "All required tools available"
}

get_go_files() {
    local mode="$1"
    shift
    
    case "$mode" in
        "all")
            find . -name "*.go" -not -path "./vendor/*" -not -path "./.git/*"
            ;;
        "files")
            # Expand patterns and validate files exist
            for pattern in "$@"; do
                if echo "$pattern" | grep -q '\*'; then
                    # Handle glob patterns
                    find . -path "./$pattern" -name "*.go" 2>/dev/null || true
                elif [ -f "$pattern" ] && echo "$pattern" | grep -q '\.go$'; then
                    echo "$pattern"
                elif [ -d "$pattern" ]; then
                    find "$pattern" -name "*.go" 2>/dev/null || true
                else
                    log_warning "File not found or not a Go file: $pattern"
                fi
            done
            ;;
        "staged"|"commit")
            git diff --cached --name-only --diff-filter=ACM | grep '\.go$' || true
            ;;
        *)
            log_error "Unknown mode: $mode"
            return 1
            ;;
    esac
}

run_gofmt() {
    local files="$1"
    
    if [ "$ENABLE_FORMAT" = "0" ]; then
        log_verbose "Skipping gofmt (disabled)"
        return 0
    fi
    
    if [ -z "$files" ]; then
        log_warning "No Go files to format"
        return 0
    fi
    
    log_info "Running gofmt formatting..."
    
    # Check if files need formatting
    local unformatted
    unformatted=$(echo "$files" | xargs gofmt -l 2>/dev/null || true)
    
    if [ -n "$unformatted" ]; then
        log_warning "Files need formatting:"
        echo "$unformatted" | sed 's/^/  /'
        
        if [ "$DRY_RUN" = "0" ]; then
            echo "$files" | xargs gofmt -s -w
            log_success "Files formatted"
        else
            log_info "DRY RUN: Would format files"
        fi
    else
        log_success "All files properly formatted"
    fi
}

run_goimports() {
    local files="$1"
    
    if [ "$ENABLE_IMPORTS" = "0" ] || ! command -v goimports >/dev/null 2>&1; then
        log_verbose "Skipping goimports (disabled or not available)"
        return 0
    fi
    
    if [ -z "$files" ]; then
        log_warning "No Go files for import organization"
        return 0
    fi
    
    run_command "Organizing imports with goimports" "echo '$files' | xargs goimports -w"
}

run_golangci_lint() {
    if [ "$ENABLE_LINT" = "0" ] || ! command -v golangci-lint >/dev/null 2>&1; then
        log_verbose "Skipping golangci-lint (disabled or not available)"
        return 0
    fi
    
    run_command "Running golangci-lint" "golangci-lint run"
}

run_go_vet() {
    if [ "$ENABLE_VET" = "0" ]; then
        log_verbose "Skipping go vet (disabled)"
        return 0
    fi
    
    run_command "Running go vet" "go vet ./..."
}

run_staticcheck() {
    if [ "$ENABLE_STATICCHECK" = "0" ] || ! command -v staticcheck >/dev/null 2>&1; then
        log_verbose "Skipping staticcheck (disabled or not available)"
        return 0
    fi
    
    run_command "Running staticcheck" "staticcheck ./..."
}

run_gosec() {
    if [ "$ENABLE_SECURITY" = "0" ] || ! command -v gosec >/dev/null 2>&1; then
        log_verbose "Skipping gosec (disabled or not available)"
        return 0
    fi
    
    run_command "Checking security with gosec" "gosec ./..."
}

run_tests() {
    if [ "$ENABLE_TESTS" = "0" ]; then
        log_verbose "Skipping tests (disabled)"
        return 0
    fi
    
    run_command "Running tests with race detection" "go test -race ./..."
}

run_build_check() {
    if [ "$ENABLE_BUILD" = "0" ]; then
        log_verbose "Skipping build check (disabled)"
        return 0
    fi
    
    log_info "Verifying build..."
    
    # Check if project builds for target architectures
    local targets="linux/amd64 linux/arm linux/mips"
    
    for target in $targets; do
        local goos=$(echo "$target" | cut -d'/' -f1)
        local goarch=$(echo "$target" | cut -d'/' -f2)
        
        log_verbose "Building for $goos/$goarch"
        
        if [ "$DRY_RUN" = "0" ]; then
            if GOOS="$goos" GOARCH="$goarch" go build -o /dev/null ./cmd/starfaild >/dev/null 2>&1; then
                log_verbose "Build successful for $target"
            else
                log_error "Build failed for $target"
                return 1
            fi
        else
            log_verbose "DRY RUN: Would build for $target"
        fi
    done
    
    log_success "All builds successful"
}

main() {
    # Parse command line arguments
    local mode="all"
    local files=""
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=1
                ;;
            -q|--quiet)
                QUIET=1
                ;;
            -n|--dry-run)
                DRY_RUN=1
                ;;
            --no-format)
                ENABLE_FORMAT=0
                ;;
            --no-imports)
                ENABLE_IMPORTS=0
                ;;
            --no-lint)
                ENABLE_LINT=0
                ;;
            --no-vet)
                ENABLE_VET=0
                ;;
            --no-staticcheck)
                ENABLE_STATICCHECK=0
                ;;
            --no-security)
                ENABLE_SECURITY=0
                ;;
            --no-tests)
                ENABLE_TESTS=0
                ;;
            --no-build)
                ENABLE_BUILD=0
                ;;
            all|files|staged|commit)
                mode="$1"
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                if [ "$mode" = "files" ]; then
                    files="$files $1"
                else
                    log_error "Unexpected argument: $1"
                    print_usage
                    exit 1
                fi
                ;;
        esac
        shift
    done
    
    # Set environment variables
    if [ "${DRY_RUN:-0}" = "1" ]; then
        DRY_RUN=1
    fi
    if [ "${VERBOSE:-0}" = "1" ]; then
        VERBOSE=1
    fi
    
    log_info "Go Verification Script v$VERSION"
    log_info "Mode: $mode"
    
    if [ "$DRY_RUN" = "1" ]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    # Check tools availability
    if ! check_tools; then
        exit 1
    fi
    
    # Get list of files to check
    local go_files
    if [ "$mode" = "files" ]; then
        go_files=$(get_go_files "$mode" $files)
    else
        go_files=$(get_go_files "$mode")
    fi
    
    if [ -z "$go_files" ]; then
        log_warning "No Go files found to check"
        exit 0
    fi
    
    local file_count=$(echo "$go_files" | wc -l)
    log_info "Found $file_count Go files to verify"
    
    if [ "$VERBOSE" = "1" ]; then
        log_verbose "Files to check:"
        echo "$go_files" | sed 's/^/  /'
    fi
    
    # Run verification steps
    local start_time=$(date +%s)
    local errors=0
    
    # Format check
    if ! run_gofmt "$go_files"; then
        errors=$((errors + 1))
    fi
    
    # Import organization
    if ! run_goimports "$go_files"; then
        errors=$((errors + 1))
    fi
    
    # Linting
    if ! run_golangci_lint; then
        errors=$((errors + 1))
    fi
    
    # Vet
    if ! run_go_vet; then
        errors=$((errors + 1))
    fi
    
    # Static analysis
    if ! run_staticcheck; then
        errors=$((errors + 1))
    fi
    
    # Security check
    if ! run_gosec; then
        errors=$((errors + 1))
    fi
    
    # Tests
    if ! run_tests; then
        errors=$((errors + 1))
    fi
    
    # Build verification
    if ! run_build_check; then
        errors=$((errors + 1))
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "Verification completed in ${duration}s"
    
    if [ "$errors" -eq 0 ]; then
        log_success "All checks passed! ✅"
        exit 0
    else
        log_error "$errors check(s) failed ❌"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
