#!/usr/bin/env bash
set -euo pipefail

# systemd-stub > 255 merges .osrel section into initrd at runtime
# This removes .osrel to make initrd contents deterministic
shopt -s nullglob
for uki in "$OUTPUTDIR"/*.efi; do
    objcopy --remove-section=.osrel "${OUTPUTDIR}/${IMAGE_ID}_${IMAGE_VERSION}.efi"
done
