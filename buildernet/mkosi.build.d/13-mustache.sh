#!/usr/bin/env bash
set -euo pipefail

echo "Installing mustache..."

EXPECTED_SHA256="5f3a9722a071bb9e2aa16d7d575881ff93223e0103059afae6d52c01d15eb96a"
VERSION="1.4.0"

mkdir -p $DESTDIR/usr/bin
curl -fSsL -o $DESTDIR/usr/bin/mustache "https://github.com/cbroglie/mustache/releases/download/v${VERSION}/mustache_${VERSION}_linux_amd64.tar.gz"
sha256sum $DESTDIR/usr/bin/mustache | grep -q $EXPECTED_SHA256 || { echo "SHA256 checksum verification failed"; exit 1; }
