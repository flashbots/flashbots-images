#!/bin/bash
set -euo pipefail

[[ "$OSTYPE" == "linux-gnu"* ]] || exit 0
[[ "${FORCE_LIMA:-}" == "1" ]] && exit 0

LIMA_MSG="Alternatively, you can install Lima from lima-vm.io and run make with FORCE_LIMA=1"

err() { echo -e "\033[0;31mError: $1\033[0m" >&2; exit 1; }
warn() { echo -e "\033[1;33m$1\033[0m"; }
success() { echo -e "\033[0;32m$1\033[0m"; }
cmd_exists() { command -v "$1" &>/dev/null; }
is_interactive() { [ -t 0 ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; }

missing=()

# Check for missing dependencies

cmd_exists curl || missing+=("curl")
cmd_exists qemu-img || missing+=("qemu-utils")

ls /usr/share/keyrings/debian-archive* &>/dev/null 2>&1 || missing+=("debian-archive-keyring")

if cmd_exists systemctl; then
    version=$(systemctl --version | head -1 | awk '{print $2}')
    [ "$version" -ge 250 ] || err "systemd 250+ required (current: $version). $LIMA_MSG"
fi

if ! cmd_exists nix; then
    missing+=("nix" "nix-features")
elif ! nix config show experimental-features 2>/dev/null | grep -q "flakes.*nix-command"; then
    missing+=("nix-features")
fi

# Exit silently if no dependencies are missing
[ ${#missing[@]} -eq 0 ] && exit 0

# Warn about missing dependencies
if is_interactive; then
    warn "Missing: ${missing[*]}"
    read -p "Install? [y/N] " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] || err "Setup cancelled. $LIMA_MSG"
fi

# Install missing dependencies

if ! cmd_exists apt-get; then
    err "Missing dependencies: ${missing[*]}. Automatic installation requires apt. Please install manually."
fi

apt_pkgs=()
for dep in "${missing[@]}"; do
    [[ "$dep" == "curl" || "$dep" == "debian-archive-keyring" || "$dep" == "qemu-utils" ]] && apt_pkgs+=("$dep")
done

if [ ${#apt_pkgs[@]} -gt 0 ]; then
    (cmd_exists sudo && sudo apt-get update || apt-get update)
    (cmd_exists sudo && sudo apt-get install -y "${apt_pkgs[@]}" || apt-get install -y "${apt_pkgs[@]}")
fi

if [[ " ${missing[@]} " =~ " nix-features " ]]; then
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
fi

if [[ " ${missing[@]} " =~ " nix " ]]; then
    sh <(curl -L https://nixos.org/nix/install) --no-daemon
    . ~/.nix-profile/etc/profile.d/nix.sh
fi

success "Dependencies installed successfully!"
