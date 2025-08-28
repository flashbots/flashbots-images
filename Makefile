SHELL := /bin/bash
WRAPPER := scripts/env_wrapper.sh

build build-dev: check-module

check-module:
ifndef IMAGE
	$(error IMAGE is not set. Please specify IMAGE=<image> when running make build or make build-dev)
endif

.PHONY: all build build-dev setup measure clean help

# Default target
all: build

# Setup dependencies (Linux only)
setup:
	@scripts/setup_deps.sh

# Build module
build: setup
	@$(WRAPPER) mkosi --force -I $(IMAGE).conf

# Build module with devtools profile
build-dev: setup
	@$(WRAPPER) mkosi --force --profile=devtools -I $(IMAGE).conf

# Run measured-boot on the EFI file
measure:
	@if [ ! -f build/tdx-debian.efi ]; then \
		echo "Error: build/tdx-debian.efi not found. Run 'make build' first."; \
		exit 1; \
	fi
	@$(WRAPPER) measured-boot build/tdx-debian build/measurements.json

# Clean build artifacts
clean:
	rm -rf build/ mkosi.builddir/ mkosi.cache/ lima-nix/
	@if command -v limactl >/dev/null 2>&1 && limactl list | grep -q '^tee-builder'; then \
		echo "Stopping and deleting lima VM 'tee-builder'..."; \
		limactl stop tee-builder || true; \
		limactl delete tee-builder || true; \
	fi

# Help target
help:
	@echo "Mkosi TEE Build System"
	@echo ""
	@echo "Usage: make [target] [IMAGE=<image>]"
	@echo ""
	@echo "Targets:"
	@echo "  build       - Build the specified module"
	@echo "  build-dev   - Build with dev tools"
	@echo "  measure     - Export TDX measurements for the built image to build/"
	@echo "  setup       - Install dependencies (Linux only)"
	@echo "  clean       - Remove cache and build artifacts"
	@echo "  help        - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build IMAGE=bob"
	@echo "  make build-dev IMAGE=l2-builder"
	@echo "  make measure"
