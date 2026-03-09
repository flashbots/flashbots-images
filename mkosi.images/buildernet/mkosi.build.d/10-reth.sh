#!/bin/bash
set -euo pipefail

EXPECTED_SHA256=05d2358f591856077e5d79789ec1aab9462ebdf630055973ef6e18580aabfaed
curl -sSfL https://github.com/paradigmxyz/reth/releases/download/v1.11.1/reth-v1.11.1-x86_64-unknown-linux-gnu-reproducible.deb -o $PACKAGEDIR/reth.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/reth.deb | sha256sum --check
