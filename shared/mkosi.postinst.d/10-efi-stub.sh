#!/usr/bin/env bash
set -euo pipefail

# Copy the efi stub to the place where bootctl expects it
bootctl="$(which -a bootctl | grep /nix | head -n 1)"
nix_dir="$(dirname $(dirname $bootctl))"
boot_dir="lib/systemd/boot"
mkosi-chroot mkdir -p $nix_dir/$boot_dir
mkosi-chroot cp -r /usr/$boot_dir/efi $nix_dir/$boot_dir/efi
