# Makefile for Starfail project
.PHONY: help verify verify-all verify-files verify-staged verify-quick build test clean install-tools

# Default target
help:
	@echo "Available targets:"
	@echo "  verify        - Run verification on staged files (pre-commit)"
	@echo "  verify-all    - Run verification on all Go files"
	@echo "  verify-files  - Run verification on specific files (use FILES=file1,file2)"
	@echo "  verify-quick  - Run verification without tests"
	@echo "  verify-ci     - Run full CI verification with coverage and race detection"
	@echo "  verify-fix    - Run verification with auto-fix enabled"
	@echo "  verify-dry    - Run dry-run verification (show what would be done)"
	@echo "  build         - Build all binaries"
	@echo "  test          - Run tests"
	@echo "  clean         - Clean build artifacts"
	@echo "  install-tools - Install required Go tools"
	@echo ""
	@echo "Examples:"
	@echo "  make verify"
	@echo "  make verify-all"
	@echo "  make verify-files FILES=cmd/starfaild/main.go,pkg/logx/logger.go"
	@echo "  make verify-quick"
	@echo "  make verify-ci"
	@echo "  make verify-fix"

# Detect OS and use appropriate script
ifeq ($(OS),Windows_NT)
    VERIFY_SCRIPT = scripts/verify-go-enhanced.ps1
    VERIFY_CMD = powershell -ExecutionPolicy Bypass -File
else
    VERIFY_SCRIPT = scripts/verify-go.sh
    VERIFY_CMD = bash
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
	@echo "Tools installed successfully!"

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
