#!/bin/bash
set -euo pipefail

VERSION="v1.11.2"
EXPECTED_SHA256=66f1460040aabd30bbc4c4b0bfe098da0fb009d7f42fc24e23be5404c5f8f26c
curl -sSfL https://github.com/paradigmxyz/reth/releases/download/${VERSION}/reth-${VERSION}-x86_64-unknown-linux-gnu-reproducible.deb -o $PACKAGEDIR/reth.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/reth.deb | sha256sum --check
