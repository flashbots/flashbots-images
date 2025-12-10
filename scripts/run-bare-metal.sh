#!/bin/bash
#
# Runs image built with 
#   mkosi -I buildernet.conf --profile="benchmark,devtools" 
# and then converted with
#   ./scripts/bare-metal-to-qemu.sh

set -eu -o pipefail

OUTPUTDIR="${1:-mkosi.output}"
IMAGE_ID="buildernet-bare-metal"
IMAGE_VERSION="latest"

RAW_FILE="${OUTPUTDIR}/${IMAGE_ID}_${IMAGE_VERSION}.raw"
#PERSISTENT_DISK="/data/fryd-home/bench-disk.qcow2"
PERSISTENT_DISK="/data/fryd-home/persistent.raw"

CPU=44
RAM=176G

if [[ ! -f "${RAW_FILE}" ]]; then
    echo "Error: Raw disk not found at ${RAW_FILE}"
    echo "Run './scripts/bare-metal-to-qemu.sh' first"
    exit 1
fi

qemu-system-x86_64 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_VARS_4M.fd \
  -drive format=raw,if=none,cache=none,id=osdisk,file="${RAW_FILE}" \
  -device nvme,drive=osdisk,serial=nvme-os,bootindex=0 \
  -enable-kvm -cpu host -m "${RAM}" -smp "${CPU}" -nographic \
  -device virtio-scsi-pci,id=scsi0 \
  -drive file="${PERSISTENT_DISK}",format=raw,if=none,id=datadisk \
  -device nvme,id=nvme0,serial=nvme-data \
  -device nvme-ns,drive=datadisk,bus=nvme0,nsid=12 \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2223-:40192

# qemu-system-x86_64 \
#   -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
#   -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_VARS_4M.fd \
#   -drive format=raw,if=none,cache=none,id=osdisk,file="${RAW_FILE}" \
#   -device nvme,drive=osdisk,serial=nvme-os,bootindex=0 \
#   -enable-kvm \
#   -cpu host \
#   -smp "${CPU}" \
#   -m "${RAM}" \
#   -nodefaults \
#   -no-user-config \
#   -display none \
#   -drive file="${PERSISTENT_DISK}",format=qcow2,if=virtio,cache=writeback,aio=io_uring \
#   -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2223-:40192 \
#   -chardev stdio,id=hvc0,signal=off \
#   -device virtio-serial-pci \
#   -device virtconsole,chardev=hvc0,name=org.qemu.console


#   -machine q35,kernel-irqchip=split,confidential-guest-support=tdx,hpet=off \
#   -object tdx-guest,id=tdx \
#   -device nvme,id=nvme0,serial=nvme-data \
#   -device nvme-ns,drive=datadisk,bus=nvme0,nsid=12 \