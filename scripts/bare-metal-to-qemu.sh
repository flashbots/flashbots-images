#!/bin/bash
#
# Convert buildernet-bare-metal UKI to a raw disk image for QEMU testing

set -eu -o pipefail

OUTPUTDIR="${1:-mkosi.output}"
IMAGE_ID="buildernet-bare-metal"
IMAGE_VERSION="latest"

EFI_FILE="${OUTPUTDIR}/${IMAGE_ID}_${IMAGE_VERSION}.efi"
RAW_FILE="${OUTPUTDIR}/${IMAGE_ID}_${IMAGE_VERSION}.raw"

if [[ ! -f "${EFI_FILE}" ]]; then
    echo "Error: UKI not found at ${EFI_FILE}"
    echo "Run 'mkosi --force -I buildernet.conf --profile devtools,benchmark' first"
    exit 1
fi

echo "Converting ${EFI_FILE} to ${RAW_FILE}..."

export SOURCE_DATE_EPOCH=0 # not propagated from the main config, needed for mkfs.vfat
export SYSTEMD_REPART_MKFS_OPTIONS_VFAT="-i 12345678"

mkdir -p "${OUTPUTDIR}/esp/EFI/BOOT"
cp "${EFI_FILE}" "${OUTPUTDIR}/esp/EFI/BOOT/BOOTX64.EFI"
rm -f "${RAW_FILE}"

systemd-repart --empty=create \
  --size=auto \
  --definitions=mkosi.images/buildernet/repart.d \
  --copy-source="${OUTPUTDIR}" \
  --seed=630b5f72-a36a-4e83-b23d-6ef47c82fd9c \
  --dry-run=no \
  "${RAW_FILE}"

sgdisk --disk-guid "12345678-1234-5678-1234-567812345678" "${RAW_FILE}"

# Cleanup temp ESP
rm -rf "${OUTPUTDIR}/esp"

echo "Done: ${RAW_FILE}"
echo ""
echo "Run with QEMU:"
# TODO: update command
echo "  qemu-system-x86_64 -drive file=${RAW_FILE},format=raw,if=virtio ..."
