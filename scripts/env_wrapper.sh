#!/usr/bin/env bash
set -euo pipefail

# script that runs on `make build`.
#
# on macOS (or other non-linux hosts) the command is shipped into a per-repo
# Lima VM. the VM is created on first use from lima.yaml, the repo is mounted
# at ~/mnt inside it, and mkosi is installed there pinned to .mkosi_version.
# build artifacts are copied back to mkosi.output/ in the repo when done.
#
# if already on Linux, you can create a `.bypass-lima` file in the repo root and this
# script gets out of the way (install mkosi per the README).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# use sha256sum or shasum (linux=>sha256sum, macOS=>shasum)
sha256() {
    if command -v sha256sum &>/dev/null; then sha256sum; else shasum -a 256; fi
}

# VM is named after a hash of the repo path (tee-builder-<hash>)
REPO_HASH="$(echo -n "$REPO_DIR" | sha256 | cut -c1-8)"
LIMA_VM="${LIMA_VM:-tee-builder-$REPO_HASH}"

should_use_lima() {
    [ ! -f "$REPO_DIR/.bypass-lima" ]
}

setup_lima() {
    if ! command -v limactl &>/dev/null; then
        echo "Lima is not installed. Please install Lima to use this script."
        echo "Visit: https://lima-vm.io/docs/installation/"
        exit 1
    fi

    if ! limactl list "$LIMA_VM" > /dev/null 2>&1; then
        declare -a args=()
        [ -n "${LIMA_CPUS:-}" ] && args+=("--cpus" "$LIMA_CPUS")
        [ -n "${LIMA_MEMORY:-}" ] && args+=("--memory" "$LIMA_MEMORY")
        [ -n "${LIMA_DISK:-}" ] && args+=("--disk" "$LIMA_DISK")

        echo "Creating Lima VM '$LIMA_VM' for $REPO_DIR..."
        limactl create -y \
            --set '.mounts = [{"location": "'"$REPO_DIR"'", "mountPoint": "/home/debian/mnt", "writable": true}]' \
            --name "$LIMA_VM" ${args[@]+"${args[@]}"} "$REPO_DIR/lima.yaml"
    fi

    status=$(limactl list "$LIMA_VM" --format "{{.Status}}")
    if [ "$status" != "Running" ]; then
        echo "Starting Lima VM '$LIMA_VM'..."
        limactl start -y "$LIMA_VM"
    fi
}

# make cmds travel into the VM over Lima's generated ssh config
lima_exec() {
    # -t: give interactive commands a TTY (qemu console, mkosi progress bars)
    # LogLevel=QUIET: hide SSH's "Shared connection closed" noise
    ssh -F "$HOME/.lima/$LIMA_VM/ssh.config" "lima-$LIMA_VM" \
        -t -o LogLevel=QUIET \
        -- "$@"
}

# exit here if being sourced
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

if [ $# -eq 0 ]; then
    echo "Error: No command specified"
    exit 1
fi

# quote cmds
cmd_q="$(printf '%q ' "$@")"

# What actually runs inside the VM, every time:
#
#  1. Make sure the right mkosi exists: a venv keyed by the git sha in
#     .mkosi_version. bump the pin and the new version installs itself.
#  2. rsync the repo to real Linux disk first. mkosi cannot build directly on
#     the macOS<->VM shared mount (virtiofs). caches/outputs are excluded from
#     sync so they persist in the VM between runs.
#  3. run cmd from the synced copy. umask 022 for reproducibility
#  4. ship build artifacts back to the repo's mkosi.output/ on host.
remote_script="
set -euo pipefail
MKOSI_REF=\$(cat ~/mnt/.mkosi_version)
VENV=~/.cache/mkosi-venvs/\$MKOSI_REF
if [ ! -x \$VENV/bin/mkosi ]; then
    echo \"Installing mkosi @\$MKOSI_REF into \$VENV...\"
    command -v git >/dev/null || sudo apt-get install -y -qq git
    python3 -m venv \$VENV
    \$VENV/bin/pip install --quiet --upgrade pip
    \$VENV/bin/pip install --quiet \"git+https://github.com/systemd/mkosi.git@\$MKOSI_REF\"
fi
command -v rsync >/dev/null || sudo apt-get install -y -qq rsync

SRC=~/.cache/tee-builder/src
mkdir -p \$SRC
rsync -a --delete \
    --exclude .git \
    --exclude .DS_Store \
    --exclude 'mkosi.output/' \
    --exclude 'mkosi.builddir/' \
    --exclude 'mkosi.cache/' \
    --exclude 'mkosi.tools*' \
    ~/mnt/ \$SRC/
mkdir -p \$SRC/mkosi.output \$SRC/mkosi.builddir \$SRC/mkosi.cache

cd \$SRC
umask 022
export PATH=\$VENV/bin:\$PATH
set -- $cmd_q
\"\$@\"

mkdir -p ~/mnt/mkosi.output
find \$SRC/mkosi.output \$SRC/tests/*/mkosi.output -maxdepth 1 -type f -exec cp -f {} ~/mnt/mkosi.output/ \; 2>/dev/null || true
"

if should_use_lima; then
    setup_lima

    # mounted repo is owned by host user, not the VM user; tells git
    # inside the VM it is safe to touch.
    lima_exec "git config --global --get-all safe.directory 2>/dev/null | grep -Fxq ~/mnt || git config --global --add safe.directory ~/mnt"

    lima_exec "$remote_script"

    echo "Note: Lima VM '$LIMA_VM' is still running. To stop it, run: limactl stop $LIMA_VM"
else
    cd "$REPO_DIR"
    umask 022
    "$@"
fi
