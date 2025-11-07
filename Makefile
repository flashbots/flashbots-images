.DEFAULT_GOAL := help

VERSION := $(shell git describe --tags --always --dirty="-dev")
SHELL := /bin/bash
WRAPPER := scripts/env_wrapper.sh

##@ Help

# Awk script from https://github.com/paradigmxyz/reth/blob/main/Makefile
.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: v
v: ## Show the version
	@echo "Version: ${VERSION}"

##@ Build

build build-dev: check-module

check-module:
ifndef IMAGE
	$(error IMAGE is not set. Please specify IMAGE=<image> when running make build or make build-dev)
endif

.PHONY: all build build-dev setup measure clean check-perms check-module

# Default target
all: build

# Ensure repo was cloned with correct permissions
check-perms: ## Check repository permissions
	@scripts/check_perms.sh

# Setup dependencies (Linux only)
setup: ## Install dependencies (Linux only)
	@scripts/setup_deps.sh

# Build module
build: check-perms setup ## Build the specified module
	$(WRAPPER) mkosi --force -I $(IMAGE).conf

# Build module with devtools profile
build-dev: check-perms setup ## Build module with development tools
	$(WRAPPER) mkosi --force --profile=devtools -I $(IMAGE).conf

##@ Utilities

measure: ## Export TDX measurements for the built EFI file
	@if [ ! -f build/tdx-debian.efi ]; then \
		echo "Error: build/tdx-debian.efi not found. Run 'make build' first."; \
		exit 1; \
	fi
	@$(WRAPPER) measured-boot build/tdx-debian.efi build/measurements.json --direct-uki
	echo "Measurements exported to build/measurements.json"

measure-gcp: ## Export TDX measurements for GCP
	@if [ ! -f build/tdx-debian.efi ]; then \
		echo "Error: build/tdx-debian.efi not found. Run 'make build' first."; \
		exit 1; \
	fi
	@$(WRAPPER) bash -c "dstack-mr -uki build/tdx-debian.efi -json > build/gcp_measurements.json"
	echo "GCP Measurements exported to build/gcp_measurements.json"

# Clean build artifacts
clean: ## Remove cache and build artifacts
	rm -rf build/ mkosi.builddir/ mkosi.cache/ lima-nix/
	@if command -v limactl >/dev/null 2>&1 && limactl list | grep -q '^tee-builder'; then \
		echo "Stopping and deleting lima VM 'tee-builder'..."; \
		limactl stop tee-builder || true; \
		limactl delete tee-builder || true; \
	fi
