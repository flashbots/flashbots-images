#!/bin/bash
set -euo pipefail

LIMA_VM="tee-builder"

# Check if Lima should be used
should_use_lima() {
    # Use Lima on macOS or if FORCE_LIMA is set
    [[ "$OSTYPE" == "darwin"* ]] || [ -n "${FORCE_LIMA:-}" ]
}

# Setup Lima if needed
setup_lima() {
    # Check if Lima is installed
    if ! command -v limactl &>/dev/null; then
        echo -e "Lima is not installed. Please install Lima to use this script."
        echo -e "Visit: https://lima-vm.io/docs/installation/"
        exit 1
    fi
    
    # Create VM if it doesn't exist
    if ! limactl list 2>/dev/null | grep -q "$LIMA_VM"; then
        echo -e "Creating $LIMA_VM VM..."
        limactl create -y --name "$LIMA_VM" lima.yaml
    fi
    
    # Start VM if not running
    if ! limactl list 2>/dev/null | grep "$LIMA_VM" | grep -q "Running"; then
        echo -e "Starting $LIMA_VM VM..."
        limactl start -y "$LIMA_VM"
        rm NvVars 2>/dev/null || true # Remove stray file created by QEMU
    fi
}

# Check if in nix environment
in_nix_env() {
    [ -n "${IN_NIX_SHELL:-}" ] || [ -n "${NIX_STORE:-}" ]
}

if [ $# -eq 0 ]; then
    echo "Error: No command specified"
    exit 1
fi

cmd=("$@")
if should_use_lima; then
    setup_lima
    cache_dir="/home/debian/mkosi-cache"
    cache_cmd="mkdir -p \"$cache_dir\" || true"
    if [[ "${cmd[0]}" == "mkosi" ]]; then
        cmd+=("--cache-directory=$cache_dir")
    fi
    limactl shell --workdir "/home/debian/mnt" "$LIMA_VM" bash -c "$cache_cmd; nix develop -c ${cmd[*]@Q}"
    echo "Note: Lima VM is still running. To stop it, run: limactl stop $LIMA_VM"
else
    if in_nix_env; then
        exec "${cmd[@]}"
    else
        exec nix develop -c "${cmd[@]}"
    fi
fi
