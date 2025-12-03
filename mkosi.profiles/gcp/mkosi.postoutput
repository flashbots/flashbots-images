#!/bin/bash
set -euxo pipefail

EFI="${OUTPUTDIR}/${IMAGE_ID}_${IMAGE_VERSION}.efi"
TAR="${OUTPUTDIR}/${IMAGE_ID}_${IMAGE_VERSION}.tar.gz"
TMP="${OUTPUTDIR}/gcp-tmp"

[ ! -f "$EFI" ] && echo "Error: $EFI not found" && exit 1

mkdir -p "$TMP"

# Fixed GUIDs and IDs
DISK_GUID="12345678-1234-5678-1234-567812345678"
PARTITION_GUID="87654321-4321-8765-4321-876543218765"
FAT_SERIAL="12345678"

# Create 500MB ESP
dd if=/dev/zero of="$TMP/esp.img" bs=1M count=500

# Format with fixed volume serial number and label
mformat -i "$TMP/esp.img" -F -v "ESP" -N "$FAT_SERIAL" ::

# Create directory structure
mmd -i "$TMP/esp.img" ::EFI ::EFI/BOOT

# Copy files with deterministic timestamps
# -D o sets file times to 1980-01-01 (DOS epoch)
mcopy -D o -i "$TMP/esp.img" "$EFI" ::EFI/BOOT/BOOTX64.EFI

# Create 1GB disk with GPT
dd if=/dev/zero of="$TMP/disk.raw" bs=1M count=1024
sgdisk --disk-guid="$DISK_GUID" "$TMP/disk.raw"

# Create ESP partition
# -n creates partition (number:start:end)
# -t sets type (1:ef00 for ESP)
# -u sets partition GUID
# -c sets partition name
sgdisk -n 1:2048:1026047 \
        -t 1:ef00 \
        -u 1:"$PARTITION_GUID" \
        -c 1:"ESP" \
        -A 1:set:0 \
        "$TMP/disk.raw"

# Write ESP image to partition area
dd if="$TMP/esp.img" of="$TMP/disk.raw" bs=512 seek=2048 conv=notrunc
touch -d "2024-01-01 00:00:00 UTC" "$TMP/disk.raw" 2>/dev/null || true

# Create GCP tar.gz
tar --format=oldgnu -Sczf "$TAR" -C "$TMP" disk.raw

rm -rf "$TMP"
