#!/bin/bash
#
# Build script for starfail daemon
# Supports cross-compilation for RutOS and OpenWrt
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build configuration
APP_NAME="starfaild"
VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo 'dev')}"
BUILD_TIME="$(date -u '+%Y-%m-%d_%H:%M:%S')"
GO_VERSION="$(go version | awk '{print $3}')"

# Build flags
LDFLAGS="-s -w"
LDFLAGS="$LDFLAGS -X main.version=$VERSION"
LDFLAGS="$LDFLAGS -X main.buildTime=$BUILD_TIME"
LDFLAGS="$LDFLAGS -X main.goVersion=$GO_VERSION"

# Create dist directory
mkdir -p dist

# Build targets
declare -A TARGETS=(
    ["rutos-armv7"]="linux arm 7"
    ["openwrt-mips"]="linux mips"
    ["openwrt-mipsel"]="linux mipsle"
    ["linux-amd64"]="linux amd64"
    ["linux-arm64"]="linux arm64"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Check Go installation
check_go() {
    if ! command -v go >/dev/null 2>&1; then
        log_error "Go is not installed or not in PATH"
        exit 1
    fi
    
    local go_version
    go_version=$(go version | awk '{print $3}' | sed 's/go//')
    log_info "Using Go version: $go_version"
    
    # Check minimum version (1.22)
    if ! go version | grep -q "go1\.2[2-9]\|go1\.[3-9]"; then
        log_warn "Go 1.22+ recommended for optimal performance"
    fi
}

# Build for specific target
build_target() {
    local name="$1"
    local goos="$2"
    local goarch="$3"
    local goarm="$4"
    local gomips="$5"
    
    log_info "Building $name ($goos/$goarch${goarm:+/v$goarm}${gomips:+/$gomips})"
    
    local output="dist/${APP_NAME}-${name}"
    
    env CGO_ENABLED=0 \
        GOOS="$goos" \
        GOARCH="$goarch" \
        ${goarm:+GOARM="$goarm"} \
        ${gomips:+GOMIPS="$gomips"} \
        go build -ldflags "$LDFLAGS" -o "$output" ./cmd/starfaild
    
    if [ -f "$output" ]; then
        local size
        size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null || echo "unknown")
        local size_mb=$((size / 1024 / 1024))
        
        log_success "Built $output (${size_mb}MB)"
        
        # Check size limit (12MB from PROJECT_INSTRUCTION.md)
        if [ "$size" != "unknown" ] && [ "$size" -gt 12582912 ]; then
            log_warn "Binary size (${size_mb}MB) exceeds 12MB target"
        fi
    else
        log_error "Failed to build $name"
        return 1
    fi
}

# Main build function
main() {
    local target_filter="$1"
    
    log_info "Building starfail daemon"
    log_info "Version: $VERSION"
    log_info "Build time: $BUILD_TIME"
    
    check_go
    
    # Clean and prepare
    if [ "$target_filter" = "clean" ]; then
        log_info "Cleaning build artifacts"
        rm -rf dist/
        return 0
    fi
    
    # Format and test first
    log_info "Formatting code"
    go fmt ./...
    
    log_info "Running go mod tidy"
    go mod tidy
    
    log_info "Vetting code"
    if ! go vet ./...; then
        log_error "Go vet failed"
        exit 1
    fi
    
    log_info "Running tests"
    if ! go test ./...; then
        log_error "Tests failed"
        exit 1
    fi
    
    # Build targets
    local built_count=0
    for target in "${!TARGETS[@]}"; do
        if [ -n "$target_filter" ] && [[ "$target" != *"$target_filter"* ]]; then
            continue
        fi
        
        IFS=' ' read -r goos goarch goarm_or_gomips <<< "${TARGETS[$target]}"
        
        # Handle ARM vs MIPS variants
        if [ "$goarch" = "arm" ]; then
            build_target "$target" "$goos" "$goarch" "$goarm_or_gomips" ""
        elif [[ "$goarch" =~ mips ]]; then
            build_target "$target" "$goos" "$goarch" "" "$goarm_or_gomips"
        else
            build_target "$target" "$goos" "$goarch" "" ""
        fi
        
        ((built_count++))
    done
    
    if [ "$built_count" -eq 0 ]; then
        log_warn "No targets matched filter: $target_filter"
        log_info "Available targets: ${!TARGETS[*]}"
    else
        log_success "Built $built_count target(s)"
        log_info "Binaries available in dist/"
    fi
}

# Usage information
usage() {
    echo "Usage: $0 [target|clean]"
    echo ""
    echo "Targets:"
    for target in "${!TARGETS[@]}"; do
        echo "  $target"
    done
    echo ""
    echo "Examples:"
    echo "  $0                # Build all targets"
    echo "  $0 rutos          # Build RutOS target only"
    echo "  $0 clean          # Clean build artifacts"
}

# Handle help
if [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
    exit 0
fi

# Run main function
main "$@"
