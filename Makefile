# Makefile for flashbots-images
# Build VM images using mkosi
#
# NOTE: Current implementation uses venv with pip for dependency management.
# TODO: Revisit tooling choice (pip vs uv vs nix) in future PR.

.DEFAULT_GOAL := help

VERSION := $(shell git describe --tags --always --dirty="-dev" 2>/dev/null || echo "dev")
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# mkosi version
MKOSI_COMMIT := a425313c5811d2ed840630dbfc45c6bc296bfd48

# Virtual environment paths
VENV := .venv
VENV_BIN := $(VENV)/bin
VENV_MARKER := $(VENV)/.installed-$(MKOSI_COMMIT)
MKOSI := $(VENV_BIN)/mkosi

# Build logs
LOGS_DIR := logs
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

##@ Help

# Awk script from https://github.com/paradigmxyz/reth/blob/main/Makefile
.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: v
v: ## Show the version
	@echo "Version: $(VERSION)"

##@ Build

.PHONY: build
build: $(VENV_MARKER) ## Build VM image
	@mkdir -p $(LOGS_DIR)
	$(MKOSI) --force -I buildernet.conf 2>&1 | tee $(LOGS_DIR)/build-$(TIMESTAMP).log

.PHONY: build-playground
build-playground: $(VENV_MARKER) ## Build VM image for playground
	@mkdir -p $(LOGS_DIR)
	$(MKOSI) --force -I buildernet.conf --profile="devtools,playground" 2>&1 | tee $(LOGS_DIR)/build-playground-$(TIMESTAMP).log

##@ Setup

# Create venv only if it doesn't exist
$(VENV_BIN)/activate:
	@echo "Creating Python virtual environment at $(VENV)..."
	python3 -m venv $(VENV)

# Install/update dependencies when mkosi version changed
$(VENV_MARKER): $(VENV_BIN)/activate
	@echo "Installing mkosi (commit: $(MKOSI_COMMIT))..."
	@rm -f $(VENV)/.installed-*
	$(VENV_BIN)/pip install -q --upgrade pip
	$(VENV_BIN)/pip install -q git+https://github.com/systemd/mkosi.git@$(MKOSI_COMMIT)
	@touch $@
	@echo "Installed: $$($(MKOSI) --version)"

.PHONY: setup
setup: $(VENV_MARKER) ## Setup build environment (venv + mkosi)
	@echo "Environment ready. mkosi: $$($(MKOSI) --version)"

##@ Utilities

.PHONY: clean
clean: ## Remove build artifacts (keeps venv)
	git clean -fdX mkosi.output mkosi.builddir
	rm -rf $(LOGS_DIR)

.PHONY: clean-all
clean-all: clean ## Remove all artifacts including venv
	rm -rf $(VENV)
