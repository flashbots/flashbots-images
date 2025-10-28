#!/usr/bin/env bash
set -euo pipefail

echo "Installing mustache..."

EXPECTED_SHA256="5f3a9722a071bb9e2aa16d7d575881ff93223e0103059afae6d52c01d15eb96a"
VERSION="1.4.0"

mkdir -p $DESTDIR/usr/bin
curl -fSsL "https://github.com/cbroglie/mustache/releases/download/v${VERSION}/mustache_${VERSION}_linux_amd64.tar.gz" | \
  tar xzf - -C $DESTDIR/usr/bin
echo "${EXPECTED_SHA256}" $DESTDIR/usr/bin/mustache | sha256sum --check
