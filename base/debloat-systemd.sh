#!/bin/bash
set -euo pipefail

# Core systemd units to keep
systemd_svc_whitelist=(
    "minimal.target"
    "basic.target"
    "sysinit.target"
    "sockets.target" 
    "local-fs.target"
    "local-fs-pre.target"
    "network-online.target"
    "slices.target"
    "systemd-journald.service"
    "systemd-journald.socket"
    "systemd-journald-dev-log.socket"
    "systemd-remount-fs.service"
    "systemd-sysctl.service"
    "chrony.service"
)

# Keep only essential systemd binaries
systemd_bin_whitelist=(
    "systemctl"
    "journalctl"
    "systemd"
    "systemd-tty-ask-password-agent"
)

mkosi-chroot dpkg-query -L systemd | grep -E '^/usr/bin/' | while read -r bin_path; do
    bin_name=$(basename "$bin_path")
    if ! printf '%s\n' "${systemd_bin_whitelist[@]}" | grep -qx "$bin_name"; then
        rm -f "$BUILDROOT$bin_path"
    fi
done

# Get all systemd units and mask those not in service whitelist
SYSTEMD_DIR="$BUILDROOT/etc/systemd/system"
mkosi-chroot dpkg-query -L systemd | grep -E '\.service$|\.socket$|\.timer$|\.target$|\.mount$' | sed 's|.*/||' | while read -r unit; do
    if ! printf '%s\n' "${systemd_svc_whitelist[@]}" | grep -qx "$unit"; then
        ln -sf /dev/null "$SYSTEMD_DIR/$unit"
    fi
done

# Enable chrony service
mkosi-chroot systemctl add-wants minimal.target chrony.service
