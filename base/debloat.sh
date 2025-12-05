#!/bin/bash
set -euo pipefail

# Ensure deterministic ordering of uid and gids before debloating
# See Debian issue #963788
mkosi-chroot pwck  --sort >/dev/null
mkosi-chroot grpck --sort >/dev/null

# Remove all logs and cache, but keep directory structure intact
find "$BUILDROOT/var/log" -type f -delete
find "$BUILDROOT/var/cache" -type f -delete

debloat_paths=(
    "/.cache"
    "/etc/*-"
    "/etc/credstore"
    "/etc/machine-id"
    "/etc/ssh/ssh_host_*_key*"
    "/etc/systemd/network"
    "/nix"
    "/usr/lib/modules"
    "/usr/lib/pcrlock.d"
    "/usr/lib/systemd/catalog"
    "/usr/lib/systemd/network"
    "/usr/lib/systemd/user-generators"
    "/usr/lib/systemd/user"
    "/usr/lib/tmpfiles.d"
    "/usr/lib/udev/hwdb.bin"
    "/usr/lib/udev/hwdb.d"
    "/usr/share/bug"
    "/usr/share/debconf"
    "/usr/share/doc"
    "/usr/share/gcc"
    "/usr/share/gdb"
    "/usr/share/info"
    "/usr/share/initramfs-tools"
    "/usr/share/lintian"
    "/usr/share/locale"
    "/usr/share/man"
    "/usr/share/menu"
    "/usr/share/mime"
    "/usr/share/perl5/debconf"
    "/usr/share/polkit-1"
    "/usr/share/systemd"
    "/usr/share/zsh"
    "/var/lib/ucf"
)

if [[ ! "${PROFILES:-}" == *"devtools"* ]]; then
    debloat_paths+=(
        "/usr/share/bash-completion"
    )
fi

for p in "${debloat_paths[@]}"; do
    echo "Debloating $p"
    rm -rf $BUILDROOT$p
done
