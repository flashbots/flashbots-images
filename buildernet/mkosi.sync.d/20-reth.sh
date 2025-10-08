#!/bin/bash
set -euo pipefail

curl -sSfL https://snapshots.flashbots.dev/reth_1.8.2-1_amd64.deb -o $SRCDIR/buildernet/mkosi.packages/reth.deb
# TODO
