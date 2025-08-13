# Build targets and cross-compilation for starfail

# Common build settings
export CGO_ENABLED=0
export GOOS=linux

# Build flags for size optimization
LDFLAGS := -s -w -X main.version=$(VERSION) -X main.buildTime=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)
BUILDFLAGS := -ldflags "$(LDFLAGS)" -trimpath

# Default version if not set
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

# Architecture targets for OpenWrt/RutOS devices
TARGETS = \
	linux/arm/v7 \
	linux/mips \
	linux/mipsle \
	linux/arm64 \
	linux/amd64

# Device-specific targets
RUTX50_TARGET = linux/arm/v7
RUTX11_TARGET = linux/arm/v7
RUTX12_TARGET = linux/arm/v7
RUT901_TARGET = linux/mips
GENERIC_ARM_TARGET = linux/arm/v7
GENERIC_MIPS_TARGET = linux/mips

.PHONY: all clean build test fmt vet deps check rutx50 rutx11 rutx12 rut901 package install

all: build

# Development tasks
fmt:
	go fmt ./...

vet:
	go vet ./...

test:
	go test -v ./...

deps:
	go mod download
	go mod tidy

check: fmt vet test

# Build tasks
build: build/starfaild build/starfail-sysmgmt

build/starfaild:
	@mkdir -p build
	go build $(BUILDFLAGS) -o build/starfaild ./cmd/starfaild

build/starfail-sysmgmt:
	@mkdir -p build
	go build $(BUILDFLAGS) -o build/starfail-sysmgmt ./cmd/starfail-sysmgmt

# Cross-compilation for specific devices
rutx50:
	@echo "Building for RUTX50 (ARMv7)..."
	@mkdir -p build/rutx50
	GOARCH=arm GOARM=7 go build $(BUILDFLAGS) -o build/rutx50/starfaild ./cmd/starfaild
	GOARCH=arm GOARM=7 go build $(BUILDFLAGS) -o build/rutx50/starfail-sysmgmt ./cmd/starfail-sysmgmt
	@ls -lh build/rutx50/starfail*

rutx11:
	@echo "Building for RUTX11 (ARMv7)..."
	@mkdir -p build/rutx11
	GOARCH=arm GOARM=7 go build $(BUILDFLAGS) -o build/rutx11/starfaild ./cmd/starfaild
	GOARCH=arm GOARM=7 go build $(BUILDFLAGS) -o build/rutx11/starfail-sysmgmt ./cmd/starfail-sysmgmt
	@ls -lh build/rutx11/starfail*

rutx12:
	@echo "Building for RUTX12 (ARMv7)..."
	@mkdir -p build/rutx12
	GOARCH=arm GOARM=7 go build $(BUILDFLAGS) -o build/rutx12/starfaild ./cmd/starfaild
	GOARCH=arm GOARM=7 go build $(BUILDFLAGS) -o build/rutx12/starfail-sysmgmt ./cmd/starfail-sysmgmt
	@ls -lh build/rutx12/starfail*

rut901:
	@echo "Building for RUT901 (MIPS)..."
	@mkdir -p build/rut901
	GOARCH=mips go build $(BUILDFLAGS) -o build/rut901/starfaild ./cmd/starfaild
	GOARCH=mips go build $(BUILDFLAGS) -o build/rut901/starfail-sysmgmt ./cmd/starfail-sysmgmt
	@ls -lh build/rut901/starfail*

# Build all targets
build-all: $(addprefix build-, $(subst /,-,$(TARGETS)))

build-%: 
	$(eval PARTS := $(subst -, ,$*))
	$(eval ARCH := $(word 2,$(PARTS)))
	$(eval VARIANT := $(word 3,$(PARTS)))
	@echo "Building for $(ARCH)$(if $(VARIANT),/$(VARIANT))..."
	@mkdir -p build/$(ARCH)$(if $(VARIANT),-$(VARIANT))
	GOARCH=$(ARCH) $(if $(VARIANT),GOARM=$(VARIANT)) go build $(BUILDFLAGS) \
		-o build/$(ARCH)$(if $(VARIANT),-$(VARIANT))/starfaild ./cmd/starfaild
	@ls -lh build/$(ARCH)$(if $(VARIANT),-$(VARIANT))/starfaild

# Strip binaries (if strip is available)
strip: build
	@for binary in build/*/starfaild build/starfaild; do \
		if [ -f "$$binary" ]; then \
			echo "Stripping $$binary..."; \
			strip "$$binary" 2>/dev/null || echo "strip not available"; \
		fi; \
	done

# Package creation
package: package-openwrt

package-openwrt: build
	@echo "Creating OpenWrt package structure..."
	@mkdir -p package/starfail/files/usr/sbin
	@mkdir -p package/starfail/files/etc/init.d
	@mkdir -p package/starfail/files/etc/hotplug.d/iface
	@mkdir -p package/starfail/files/etc/config
	
	# Copy binaries
	cp build/starfaild package/starfail/files/usr/sbin/
	cp scripts/starfailctl.sh package/starfail/files/usr/sbin/starfailctl
	chmod +x package/starfail/files/usr/sbin/*
	
	# Copy system files
	cp scripts/starfail.init package/starfail/files/etc/init.d/starfail
	cp scripts/99-starfail.hotplug package/starfail/files/etc/hotplug.d/iface/
	chmod +x package/starfail/files/etc/init.d/starfail
	chmod +x package/starfail/files/etc/hotplug.d/iface/99-starfail.hotplug
	
	@echo "Package structure created in package/starfail/"

# Install to local system (for testing)
install: build
	@echo "Installing starfail to local system..."
	sudo install -m 755 build/starfaild /usr/sbin/
	sudo install -m 755 scripts/starfailctl.sh /usr/sbin/starfailctl
	sudo install -m 755 scripts/starfail.init /etc/init.d/starfail
	sudo install -m 755 scripts/99-starfail.hotplug /etc/hotplug.d/iface/
	@echo "Installation complete. Start with: sudo /etc/init.d/starfail start"

# Development helpers
dev-build: check build

dev-test: build
	@echo "Running basic functionality test..."
	./build/starfaild -version
	./build/starfaild -config /dev/null -help || true

# Clean build artifacts
clean:
	rm -rf build/
	rm -rf package/
	go clean

# Help
help:
	@echo "Starfail Build System"
	@echo ""
	@echo "Common targets:"
	@echo "  build      - Build for current platform"
	@echo "  rutx50     - Build for RUTX50 (ARMv7)"
	@echo "  rutx11     - Build for RUTX11 (ARMv7)"
	@echo "  rutx12     - Build for RUTX12 (ARMv7)"
	@echo "  rut901     - Build for RUT901 (MIPS)"
	@echo "  build-all  - Build for all targets"
	@echo "  package    - Create OpenWrt package"
	@echo "  install    - Install to local system"
	@echo "  test       - Run tests"
	@echo "  clean      - Clean build artifacts"
	@echo ""
	@echo "Development:"
	@echo "  dev-build  - Build with checks"
	@echo "  dev-test   - Quick functionality test"
	@echo "  fmt        - Format code"
	@echo "  vet        - Run go vet"
	@echo "  check      - Run all checks"
