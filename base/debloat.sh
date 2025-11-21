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
    "/etc/machine-id"
    "/etc/*-"
    "/etc/ssh/ssh_host_*_key*"
    "/usr/share/doc"
    "/usr/share/man"
    "/usr/share/info"
    "/usr/share/locale"
    "/usr/share/gcc"
    "/usr/share/gdb"
    "/usr/share/lintian"
    "/usr/share/perl5/debconf"
    "/usr/share/debconf"
    "/usr/share/initramfs-tools"
    "/usr/share/polkit-1"
    "/usr/share/bug"
    "/usr/share/menu"
    "/usr/share/systemd"
    "/usr/share/zsh"
    "/usr/share/mime"
    "/usr/lib/modules"
    "/usr/lib/udev/hwdb.d"
    "/usr/lib/udev/hwdb.bin"
    "/usr/lib/systemd/catalog"
    "/usr/lib/systemd/user"
    "/usr/lib/systemd/user-generators"
    "/usr/lib/systemd/network"
    "/usr/lib/pcrlock.d"
    "/usr/lib/tmpfiles.d"
    "/var/lib/ucf"
    "/etc/systemd/network"
    "/etc/credstore"
    "/nix"
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
