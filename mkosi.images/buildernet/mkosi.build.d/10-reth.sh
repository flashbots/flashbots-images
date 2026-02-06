#!/bin/bash
set -euo pipefail

EXPECTED_SHA256=3636fb261b9dd05e359b835055cc1b64b54c80b044d2207a18c7640713b7372c
curl -sSfL https://github.com/paradigmxyz/reth/releases/download/v1.10.2/reth-v1.10.2-x86_64-unknown-linux-gnu-reproducible.deb -o $PACKAGEDIR/reth.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/reth.deb | sha256sum --check
