#!/bin/bash
set -euo pipefail

curl -sSfL https://snapshots.flashbots.dev/reth_1~1.9.3_amd64.deb -o $PACKAGEDIR/reth.deb
# TODO
