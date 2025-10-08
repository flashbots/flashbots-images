#!/usr/bin/env bash
set -euo pipefail

#REF=TODO
BUILDDIR="$BUILDDIR/rbuilder"

echo "Installing rbuilder..."

mkdir -p $BUILDDIR

curl -sSfL https://snapshots.flashbots.dev/rbuilder-operator_1~9d83884_amd64.deb -o $BUILDDIR/rbuilder.deb
mkosi-chroot dpkg -i $BUILDDIR/rbuilder.deb
rm -f $BUILDDIR/rbuilder.deb
