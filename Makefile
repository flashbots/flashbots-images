.DEFAULT_GOAL := help

SHELL := /usr/bin/env bash
WRAPPER := scripts/env_wrapper.sh
UKI_FILE ?= mkosi.output/buildernet-gcp_latest.efi
MEASUREMENTS_FILE ?= mkosi.output/portable_measurements.json

# Lima build VM name, mirroring scripts/env_wrapper.sh: tee-builder-<sha256(repo path)[:8]>.
ifndef LIMA_VM
LIMA_VM := tee-builder-$(shell printf '%s' "$(CURDIR)" | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | cut -c1-8)
endif

# our kernel config is amd64-only, but on Apple Silicon the Lima VM is arm64
# and mkosi defaults to the host arch
ARCH := --architecture=x86-64

##@ Help

# Awk script from https://github.com/paradigmxyz/reth/blob/main/Makefile
.PHONY: help
help: ## display their help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

.PHONY: build build-dev build-local smoke measure-portable boot clean clean-vm stop-vm

build: ## build all BuilderNet images (azure, gcp, qemu)
	$(WRAPPER) mkosi $(ARCH) --force -I buildernet.conf build

build-dev: ## build with devtools profile (apt, tcpdump, strace, ...)
	$(WRAPPER) mkosi $(ARCH) --force --profile=devtools -I buildernet.conf build

build-local: ## build with local+devtools profiles (root autologin console, for `make boot`)
	$(WRAPPER) mkosi $(ARCH) --force --profile=local --profile=devtools -I buildernet.conf build

smoke: ## tiny quick image build to validate the toolchain 
	$(WRAPPER) mkosi -C tests/smoke --force build
	@echo "Smoke build OK"

measure-portable: ## export portable measurements for the GCP UKI (override UKI_FILE=...)
	@mkdir -p "$(dir $(MEASUREMENTS_FILE))"
	@command -v attest >/dev/null || { echo "attest not found; install Easy-TEE/attest from main" >&2; exit 1; }
	@attest measure portable --no-azure "$(UKI_FILE)" > "$(MEASUREMENTS_FILE)"
	@echo "Portable measurements exported to $(MEASUREMENTS_FILE)"

##@ Run

boot: ## boot the built qemu UKI (no disk/TPM). root shell: `make console` in another terminal
	$(WRAPPER) bash -c 'qemu-system-x86_64 -m 6G -smp 4 -nographic -cpu max \
	  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
	  -kernel $$(ls -t mkosi.output/buildernet-qemu_*.efi | head -1) \
	  -nic user,model=virtio-net-pci \
	  -chardev socket,id=hvc0,path=/tmp/hvc0.sock,server=on,wait=off \
	  -device virtio-serial-pci \
	  -device virtconsole,chardev=hvc0'

console: ## attach to the root shell of a VM started with `make boot` (detach: Enter ~ .)
	$(WRAPPER) socat -,raw,echo=0 UNIX-CONNECT:/tmp/hvc0.sock

##@ Utils

clean: ## remove build artifacts, host-side and in the Lima build VM (keeps the VM)
	rm -rf mkosi.output/* mkosi.builddir/* mkosi.cache/* tests/smoke/mkosi.output tests/smoke/mkosi.tools
	@if command -v limactl >/dev/null 2>&1 && limactl list 2>/dev/null | grep -q "^$(LIMA_VM)"; then \
		echo "Cleaning build artifacts inside Lima VM '$(LIMA_VM)'..."; \
		$(WRAPPER) rm -rf mkosi.output mkosi.builddir mkosi.cache tests/smoke/mkosi.output tests/smoke/mkosi.tools; \
	fi

stop-vm: ## stop this repo's Lima build VM (override with LIMA_VM=; keeps its disk)
	@if ! command -v limactl >/dev/null 2>&1; then echo "limactl not found."; exit 0; fi; \
	if [ "$$(limactl list "$(LIMA_VM)" --format '{{.Status}}' 2>/dev/null)" = "Running" ]; then \
		echo "Stopping '$(LIMA_VM)'..."; limactl stop "$(LIMA_VM)"; \
	else \
		echo "No running Lima VM '$(LIMA_VM)'."; \
	fi

clean-vm: ## stop and delete this repo's Lima build VM (override with LIMA_VM=; destroys its contents)
	@if command -v limactl >/dev/null 2>&1 && limactl list 2>/dev/null | grep -q "^$(LIMA_VM)"; then \
		echo "Stopping and deleting Lima VM '$(LIMA_VM)'..."; \
		limactl stop "$(LIMA_VM)" || true; \
		limactl delete "$(LIMA_VM)" || true; \
	else \
		echo "No Lima VM '$(LIMA_VM)' found."; \
	fi
