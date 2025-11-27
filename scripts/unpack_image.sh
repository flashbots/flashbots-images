#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 <image_path> [dest_directory]"
    echo "  image_path: Path to VHD or tar.gz image"
    echo "  dest_directory: Optional output directory (default: mktemp -d)"
    exit 1
}

# Check arguments
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
fi

IMAGE_PATH="$1"
DEST_DIR="${2:-$(mktemp -d)}"

# Verify image exists
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: Image file not found: $IMAGE_PATH"
    exit 1
fi

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

extract_efi_from_raw() {
    local RAW_FILE="$1"
    local EFI_FILE="$2"
    local DEST_DIR="$3"

    # Find the ESP partition offset (should be at sector 2048, 512 bytes per sector)
    local OFFSET=$((2048 * 512))

    local MOUNT_POINT="$DEST_DIR/mnt"
    mkdir -p "$MOUNT_POINT"

    echo "Mounting raw image, sudo may ask for password..."
    sudo mount -o loop,ro,offset=$OFFSET "$RAW_FILE" "$MOUNT_POINT"
    cp "$MOUNT_POINT/EFI/BOOT/BOOTX64.EFI" "$EFI_FILE"

    # cleanup
    sudo umount "$MOUNT_POINT"
    rmdir "$MOUNT_POINT"
    rm "$RAW_FILE"
}

EFI_FILE="$DEST_DIR/boot.efi"

# Detect image type and extract EFI file
if [[ "$IMAGE_PATH" == *.vhd ]]; then
    echo "Detected VHD image, extracting..."

    # Convert VHD to raw
    RAW_FILE="$DEST_DIR/disk.raw"
    qemu-img convert -O raw "$IMAGE_PATH" "$RAW_FILE"

    extract_efi_from_raw "$RAW_FILE" "$EFI_FILE" "$DEST_DIR"

elif [[ "$IMAGE_PATH" == *.tar.gz ]]; then
    echo "Detected tar.gz image, extracting..."

    tar -xzf "$IMAGE_PATH" -C "$DEST_DIR"

    RAW_FILE="$DEST_DIR/disk.raw"
    if [ ! -f "$RAW_FILE" ]; then
        echo "Error: disk.raw not found in tar.gz"
        exit 1
    fi

    extract_efi_from_raw "$RAW_FILE" "$EFI_FILE" "$DEST_DIR"

elif [[ "$IMAGE_PATH" == *.efi ]]; then
    echo "Detected efi file, copying..."

    cp "$IMAGE_PATH" "$EFI_FILE"

else
    echo "Error: Unsupported image format. Expected .vhd, .tar.gz or .efi"
    exit 1
fi

echo "Extracted EFI file to: $EFI_FILE"

# Extract linux and initrd sections from EFI file
LINUX_FILE="$DEST_DIR/vmlinuz"
INITRD_FILE="$DEST_DIR/initrd.img"

echo "Extracting kernel and initrd..."
objcopy --dump-section=.linux="$LINUX_FILE" "$EFI_FILE"
objcopy --dump-section=.initrd="$INITRD_FILE" "$EFI_FILE"


echo "Unpacking initrd..."

INITRD_DIR="$DEST_DIR/initrd"
mkdir -p "$INITRD_DIR"
cd "$INITRD_DIR"
zstdcat "$INITRD_FILE" | cpio -i -d --quiet 2>/dev/null || true
cd - > /dev/null

# Display os-release
OS_RELEASE="$INITRD_DIR/usr/lib/os-release"
if [ -f "$OS_RELEASE" ]; then
    echo ""
    echo "=== OS Release Information ==="
    cat "$OS_RELEASE"
    echo "=============================="
    echo ""
else
    echo "Warning: os-release file not found in initrd"
fi

echo "Unpacked image dir: $DEST_DIR"
echo " - EFI file: $EFI_FILE"
echo " - Kernel: $LINUX_FILE"
echo " - Initrd: $INITRD_FILE"
echo " - Initrd unpacked dir: $INITRD_DIR"
