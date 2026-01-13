#!/bin/bash
set -euo pipefail

# Additional systemd units to enable for proper reboot support in bob-common
# These build on top of base/debloat-systemd.sh
bob_systemd_additions=(
    "final.target"
    "shutdown.target"
    "umount.target"
    "systemd-reboot.service"
    "reboot.target"
)

SYSTEMD_DIR="$BUILDROOT/etc/systemd/system"

# Unmask the additional units needed for proper reboot
for unit in "${bob_systemd_additions[@]}"; do
    if [[ -L "$SYSTEMD_DIR/$unit" ]] && [[ "$(readlink "$SYSTEMD_DIR/$unit")" == "/dev/null" ]]; then
        echo "Unmasking $unit for bob-common"
        rm -f "$SYSTEMD_DIR/$unit"
    fi
done
