#!/bin/bash
set -euo pipefail

curl -sSfL https://snapshots.flashbots.dev/bid-scraper_1~9d83884_amd64.deb -o $SRCDIR/buildernet/mkosi.packages/bid-scraper.deb
# TODO
