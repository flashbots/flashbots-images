#!/usr/bin/env bash
set -euo pipefail
export SOURCE_DATE_EPOCH=0

# systemd-stub > 255 merges .osrel section into initrd at runtime
# This removes .osrel to make initrd contents deterministic
objcopy --remove-section=.osrel "${OUTPUTDIR}/${IMAGE_ID}_${IMAGE_VERSION}.efi"

# For dm-verity the UKI is embedded in the ESP
for raw in "$OUTPUTDIR"/*.raw; do
    uki="${raw%.raw}.efi"
    [ -f "$uki" ] || continue
    start=$(sgdisk -p "$raw" | awk '$6 == "EF00" { print $2; exit }')
    [ -n "$start" ] || continue
    mcopy -o -i "$raw@@$((start * 512))" "$uki" ::EFI/BOOT/BOOTX64.EFI
done
