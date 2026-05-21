#!/usr/bin/env bash
set -euo pipefail

# Unmask units needed for proper reboot support.
# Builds on top of shared/mkosi.postinst.d/90-debloat-systemd.sh which masks these.
cvm_systemd_additions=(
    "ctrl-alt-del.target"
    "final.target"
    "shutdown.target"
    "umount.target"
    "systemd-reboot.service"
    "reboot.target"
)

SYSTEMD_DIR="$BUILDROOT/etc/systemd/system"

for unit in "${cvm_systemd_additions[@]}"; do
    if [[ -L "$SYSTEMD_DIR/$unit" ]] && [[ "$(readlink "$SYSTEMD_DIR/$unit")" == "/dev/null" ]]; then
        echo "Unmasking $unit for cvm-base"
        rm -f "$SYSTEMD_DIR/$unit"
    fi
done
