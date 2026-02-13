.DEFAULT_GOAL := help

VERSION := $(shell git describe --tags --always --dirty="-dev")
SHELL := /usr/bin/env bash
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

.PHONY: all build build-dev build-bob-l1 setup measure clean check-module

# Build module directly (no Lima/nix wrapper, requires mkosi in PATH)
build-bob-l1: ## Build bob-l1 directly with mkosi (no wrapper)
	time nix develop -c mkosi --force --image-id bob-l1 --include=bob-l1.conf

# Default target
all: build

# Setup dependencies (Linux only)
setup: ## Install dependencies (Linux only)
	@scripts/setup_deps.sh

# Build module
build: setup ## Build the specified module
	$(WRAPPER) mkosi --force --image-id $(IMAGE) --include=$(IMAGE).conf

# Build module with devtools profile
build-dev: setup ## Build module with development tools
	$(WRAPPER) mkosi --force --image-id $(IMAGE)-dev --profile=devtools --include=$(IMAGE).conf

##@ Utilities

measure: ## Export TDX measurements for the built EFI file
	@$(WRAPPER) measured-boot $(FILE) build/measurements.json --direct-uki
	echo "Measurements exported to build/measurements.json"

measure-gcp: ## Export TDX measurements for GCP
	@$(WRAPPER) dstack-mr -uki $(FILE) -json > build/gcp_measurements.json
	echo "GCP Measurements exported to build/gcp_measurements.json"

# Clean build artifacts
clean: ## Remove cache and build artifacts
	rm -rf build/ mkosi.builddir/ mkosi.cache/ lima-nix/
	@REPO_DIR="$$(pwd)"; \
	REPO_HASH="$$(echo -n "$$REPO_DIR" | sha256sum | cut -c1-8)"; \
	LIMA_VM="tee-builder-$$REPO_HASH"; \
	if command -v limactl >/dev/null 2>&1 && limactl list | grep -q "^$$LIMA_VM"; then \
		echo "Stopping and deleting Lima VM '$$LIMA_VM'..."; \
		limactl stop "$$LIMA_VM" || true; \
		limactl delete "$$LIMA_VM" || true; \
	fi
