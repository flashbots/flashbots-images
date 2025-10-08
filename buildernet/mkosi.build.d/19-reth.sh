#!/usr/bin/env bash
set -euo pipefail

#REF=TODO
BUILDDIR="$BUILDDIR/reth"

echo "Installing reth..."

mkdir -p $BUILDDIR

curl -sSfL https://snapshots.flashbots.dev/reth_1.8.2-1_amd64.deb -o $BUILDDIR/reth.deb
mkosi-chroot dpkg -i $BUILDDIR/reth.deb
rm -f $BUILDDIR/reth.deb
