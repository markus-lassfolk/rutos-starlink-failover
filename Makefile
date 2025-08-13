# Makefile for Starfail project
.PHONY: help verify verify-all verify-files verify-staged verify-quick verify-luci verify-comprehensive build test clean install-tools install-luci-tools

# Default target
help:
	@echo "Available targets:"
	@echo "  verify              - Run verification on staged files (pre-commit)"
	@echo "  verify-all          - Run verification on all Go files"
	@echo "  verify-files        - Run verification on specific files (use FILES=file1,file2)"
	@echo "  verify-quick        - Run verification without tests"
	@echo "  verify-ci           - Run full CI verification with coverage and race detection"
	@echo "  verify-fix          - Run verification with auto-fix enabled"
	@echo "  verify-dry          - Run dry-run verification (show what would be done)"
	@echo "  verify-luci         - Run LuCI verification only"
	@echo "  verify-comprehensive- Run comprehensive verification (Go + LuCI)"
	@echo "  build               - Build all binaries"
	@echo "  test                - Run tests"
	@echo "  clean               - Clean build artifacts"
	@echo "  install-tools       - Install required Go tools"
	@echo "  install-luci-tools  - Install required LuCI tools"
	@echo ""
	@echo "Examples:"
	@echo "  make verify"
	@echo "  make verify-all"
	@echo "  make verify-files FILES=cmd/starfaild/main.go,pkg/logx/logger.go"
	@echo "  make verify-quick"
	@echo "  make verify-ci"
	@echo "  make verify-fix"
	@echo "  make verify-luci"
	@echo "  make verify-comprehensive"

# Detect OS and use appropriate script
ifeq ($(OS),Windows_NT)
    VERIFY_SCRIPT = scripts/verify-go-enhanced.ps1
    VERIFY_CMD = powershell -ExecutionPolicy Bypass -File
    COMPREHENSIVE_SCRIPT = scripts/verify-comprehensive.ps1
else
    VERIFY_SCRIPT = scripts/verify-go.sh
    VERIFY_CMD = bash
    COMPREHENSIVE_SCRIPT = scripts/verify-comprehensive.sh
endif

# Verification targets
verify:
	@echo "Running verification on staged files..."
	$(VERIFY_CMD) $(VERIFY_SCRIPT) staged

verify-all:
	@echo "Running verification on all files..."
	$(VERIFY_CMD) $(VERIFY_SCRIPT) all

verify-files:
	@echo "Running verification on specific files: $(FILES)"
	$(VERIFY_CMD) $(VERIFY_SCRIPT) files $(FILES)

verify-quick:
	@echo "Running quick verification (no tests)..."
	$(VERIFY_CMD) $(VERIFY_SCRIPT) all -NoTests

verify-ci:
	@echo "Running full CI verification..."
	$(VERIFY_CMD) $(VERIFY_SCRIPT) ci -Coverage -Race

verify-fix:
	@echo "Running verification with auto-fix..."
	$(VERIFY_CMD) $(VERIFY_SCRIPT) all -Fix

verify-dry:
	@echo "Running dry-run verification..."
	$(VERIFY_CMD) $(VERIFY_SCRIPT) all -DryRun

verify-luci:
	@echo "Running LuCI verification..."
	$(VERIFY_CMD) $(COMPREHENSIVE_SCRIPT) luci

verify-comprehensive:
	@echo "Running comprehensive verification (Go + LuCI)..."
	$(VERIFY_CMD) $(COMPREHENSIVE_SCRIPT) all

# Build targets
build:
	@echo "Building all binaries..."
	go build -o bin/starfaild ./cmd/starfaild
	go build -o bin/starfailsysmgmt ./cmd/starfailsysmgmt

# Test targets
test:
	@echo "Running tests..."
	go test -race -v ./...

# Clean targets
clean:
	@echo "Cleaning build artifacts..."
	rm -rf bin/
	go clean -cache -testcache

# Tool installation
install-tools:
	@echo "Installing required Go tools..."
	go install golang.org/x/tools/cmd/goimports@latest
	go install honnef.co/go/tools/cmd/staticcheck@latest
	go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	@echo "Go tools installed successfully!"

install-luci-tools:
	@echo "Installing required LuCI tools..."
	@echo "Installing Node.js tools..."
	npm install -g htmlhint eslint stylelint
	@echo "Installing Lua tools..."
	luarocks install luacheck
	@echo "Note: Install Lua and gettext manually if not available"
	@echo "LuCI tools installed successfully!"

# Development helpers
fmt:
	@echo "Formatting code..."
	gofmt -s -w .
	goimports -w .

lint:
	@echo "Running linter..."
	golangci-lint run

vet:
	@echo "Running go vet..."
	go vet ./...

mod-tidy:
	@echo "Tidying modules..."
	go mod tidy
	go mod verify

# Pre-commit hook (can be used in .git/hooks/pre-commit)
pre-commit: verify

# CI/CD helpers
ci: verify-all test build

# Docker helpers (if needed)
docker-build:
	@echo "Building Docker image..."
	docker build -t starfail .

docker-run:
	@echo "Running Docker container..."
	docker run -it --rm starfail
