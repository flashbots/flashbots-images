#!/bin/bash
set -euo pipefail

curl -sSfL https://snapshots.flashbots.dev/rbuilder-operator_1~9d83884_amd64.deb -o $SRCDIR/buildernet/mkosi.packages/rbuilder-operator.deb
# TODO
