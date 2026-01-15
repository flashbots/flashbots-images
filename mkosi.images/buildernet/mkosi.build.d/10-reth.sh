#!/bin/bash
set -euo pipefail

EXPECTED_SHA256=a092377ed4249108a8b51f48f882d96dd00090c1b28677266273258f765795c8
curl -sSfL https://github.com/paradigmxyz/reth/releases/download/v1.10.0/reth-v1.10.0-x86_64-unknown-linux-gnu-reproducible.deb -o $PACKAGEDIR/reth.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/reth.deb | sha256sum --check
