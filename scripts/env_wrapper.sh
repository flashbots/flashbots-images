#!/usr/bin/env bash
set -euo pipefail

# Check for dangling old-style tee-builder VM
if command -v limactl &>/dev/null && limactl list 2>/dev/null | grep -q '^tee-builder '; then
    echo "WARNING: FOUND 'tee-builder' VM FROM BEFORE COMMIT 2b44885."
    echo "THIS VM IS NO LONGER USED. TO CLEAN IT UP, RUN:"
    echo "  limactl stop tee-builder && limactl delete tee-builder"
    echo ""
fi

# Generate a unique VM name based on the absolute path of this repo
# This prevents conflicts when the same repo is cloned to multiple locations
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_HASH="$(echo -n "$REPO_DIR" | sha256sum | cut -c1-8)"
LIMA_VM="${LIMA_VM:-tee-builder-$REPO_HASH}"

# Check if Lima should be used
should_use_lima() {
    # Use Lima by default for now
    true ||
    # Use Lima on macOS or if FORCE_LIMA is set
    [[ "$OSTYPE" == "darwin"* ]] || [ -n "${FORCE_LIMA:-}" ] || 
    # Use Lima if it's available but Nix is not
    (command -v limactl &>/dev/null && ! command -v nix &>/dev/null)
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
    if ! limactl list "$LIMA_VM" > /dev/null 2>&1; then
        declare -a args=()
        if [ -n "${LIMA_CPUS:-}" ]; then
            args+=("--cpus" "$LIMA_CPUS")
        fi
        if [ -n "${LIMA_MEMORY:-}" ]; then
            args+=("--memory" "$LIMA_MEMORY")
        fi
        if [ -n "${LIMA_DISK:-}" ]; then
            args+=("--disk" "$LIMA_DISK")
        fi

        echo -e "Creating Lima VM '$LIMA_VM' for $REPO_DIR..."
        # Portable way to expand array on bash 3 & 4
        limactl create -y --name "$LIMA_VM" ${args[@]+"${args[@]}"} "$REPO_DIR/lima.yaml"
    fi

    # Start VM if not running
    status=$(limactl list "$LIMA_VM" --format "{{.Status}}")
    if [ "$status" != "Running" ]; then
        echo -e "Starting Lima VM '$LIMA_VM'..."
        limactl start -y "$LIMA_VM"

        rm -f NvVars # Remove stray file created by QEMU
    fi
}

# Execute command in Lima VM
lima_exec() {
    # Allocate TTY (-t) for pretty output in nix commands
    # Add -o LogLevel=QUIET to suppress SSH "Shared connection closed" messages
    ssh -F "$HOME/.lima/$LIMA_VM/ssh.config" "lima-$LIMA_VM" \
        -t -o LogLevel=QUIET \
        -- "$@"
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

is_mkosi_cmd() {
    [[ "${cmd[0]}" == "mkosi" ]] || [[ "${cmd[0]}" == *"/mkosi" ]]
}

if is_mkosi_cmd && [ -n "${MKOSI_EXTRA_ARGS:-}" ]; then
    # TODO: these args will be overriden by default cache/out dir in Lima
    # Not a big deal, but might worth fixing
    cmd+=($MKOSI_EXTRA_ARGS)
fi

if should_use_lima; then
    setup_lima

    mkosi_cache=/home/debian/mkosi-cache
    mkosi_output=/home/debian/mkosi-output

    if is_mkosi_cmd; then
        lima_exec mkdir -p "$mkosi_cache" "$mkosi_output"

        cmd+=(
            # We can't use default cache dir from mnt/, because it is mounted
            # from host, and mkosi will try to preserve root/other permissions
            # without success.
            "--cache-directory=$mkosi_cache"
            # For the same reason, we need to use separate output dir.
            # mkosi tries to preserve ownership of output files, which fails,
            # as it is running from root in a user namespace.
            "--output-dir=$mkosi_output"
        )
    fi

    lima_exec "cd ~/mnt && /home/debian/.nix-profile/bin/nix develop -c ${cmd[*]@Q}"

    if is_mkosi_cmd; then
        files=$(lima_exec "ls -1 $mkosi_output 2>/dev/null" | tr -d '\r')
        lima_exec "mkdir -p ~/mnt/build; mv '$mkosi_output'/* ~/mnt/build/" || true

        for f in $files; do
            ext=${f#*.*.}
            [[ "$ext" != "$f" ]] && ln -sf "$f" "build/latest.$ext"
        done

        echo "Check ./build/ directory for output files"
        echo
    fi

    echo "Note: Lima VM '$LIMA_VM' is still running. To stop it, run: limactl stop $LIMA_VM"
else
    if in_nix_env; then
        exec "${cmd[@]}"
    else
        exec nix develop -c "${cmd[@]}"
    fi
fi
