#!/usr/bin/env bash
set -euo pipefail

echo "Installing mustache..."

EXPECTED_SHA256="fa775964b5789e30a32bb0dc714e6b5f2234556eded779648eb1571b29502a5e"
VERSION="1.4.0"

mkdir -p $DESTDIR/usr/bin
curl -fSsL "https://github.com/cbroglie/mustache/releases/download/v${VERSION}/mustache_${VERSION}_linux_amd64.tar.gz" | \
  tar xzf - -C $DESTDIR/usr/bin
echo "${EXPECTED_SHA256}" $DESTDIR/usr/bin/mustache | sha256sum --check
