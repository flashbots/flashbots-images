#!/usr/bin/env bash
set -euo pipefail

#REF=TODO
BUILDDIR="$BUILDDIR/bid-scraper"

echo "Installing bid-scraper..."

mkdir -p $BUILDDIR

curl -sSfL https://snapshots.flashbots.dev/bid-scraper_1~9d83884_amd64.deb -o $BUILDDIR/bid-scraper.deb
mkosi-chroot dpkg -i $BUILDDIR/bid-scraper.deb
rm -f $BUILDDIR/bid-scraper.deb
