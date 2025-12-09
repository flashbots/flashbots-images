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

.PHONY: all build build-dev setup measure clean check-module

# Default target
all: build

# Setup dependencies (Linux only)
setup: ## Install dependencies (Linux only)
	@scripts/setup_deps.sh

preflight:
	@$(WRAPPER) echo "Ready to build"

# Build module
build: setup ## Build the specified module
	time $(WRAPPER) mkosi --force -I $(IMAGE).conf

# Build module with devtools profile
build-dev: setup ## Build module with development tools
	time $(WRAPPER) mkosi --force --profile=devtools -I $(IMAGE).conf

##@ Utilities

check-repro: ## Build same module twice and compare resulting images
	@rm -rf build.1
	@rm -rf build.2

	@rm -rf build/* mkosi.builddir/* mkosi.cache/* mkosi.packages/*
#	hack:  there's some race condition under lima that causes apt to fail while trying to
#	       create a temp dir under apt cache
	@sleep 15

	@echo "Building image #1..."
	time $(WRAPPER) mkosi --force -I $(IMAGE).conf
	@mkdir -p build/cache
	@mv mkosi.builddir/* build/cache/
	@mv build build.1

	@rm -rf build/* mkosi.builddir/* mkosi.cache/* mkosi.packages/*
#	hack:  there's some race condition under lima that causes apt to fail while trying to
#	       create a temp dir under apt cache
	@sleep 15

	@echo "Building image #2..."
	time $(WRAPPER) mkosi --force -I $(IMAGE).conf
	@mkdir -p build/cache
	@mv mkosi.builddir/* build/cache/
	@mv build build.2

	@echo "Comparing..."
	@for file in $$( find build.1 -type f ); do \
		sha256sum $$file; \
		sha256sum $${file/build1/build.2}; \
		echo ""; \
	done

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
	@$(WRAPPER) dstack-mr -uki build/tdx-debian.efi

# Clean build artifacts
clean: ## Remove cache and build artifacts
	rm -rf build/ mkosi.builddir/ mkosi.cache/ lima-nix/
	@if command -v limactl >/dev/null 2>&1 && limactl list | grep -q '^tee-builder'; then \
		echo "Stopping and deleting lima VM 'tee-builder'..."; \
		limactl stop tee-builder || true; \
		limactl delete tee-builder || true; \
	fi
