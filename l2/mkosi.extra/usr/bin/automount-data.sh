#!/bin/sh

set -eu

udevadm trigger --subsystem-match=block
udevadm settle --timeout=30

if [ -e /dev/disk/by-id/google-data ]; then
  device=$( realpath /dev/disk/by-id/google-data )
  if ! grep -qs "${device}" /proc/mounts; then
    eval $( blkid --output export ${device} )
    if [ -z "${TYPE:-}" ]; then
      mkfs.ext4 -m 0 ${device}
      eval $( blkid --output export ${device} )
    fi
    AUTOMOUNT_PATH_DATA=${AUTOMOUNT_PATH_DATA:-/var/opt/data}
    echo "UUID=${UUID} ${AUTOMOUNT_PATH_DATA} ${TYPE} defaults 0 0" >> /etc/fstab
    mkdir -p "${AUTOMOUNT_PATH_DATA}"
    chmod 0777 "${AUTOMOUNT_PATH_DATA}"
    systemctl daemon-reload
    mount --all
  else
    echo "Device ${device} is already mounted, skipping..."
  fi
else
  echo "Directory /dev/disk/by-id/google-data doesn't exist, skipping..."
fi
