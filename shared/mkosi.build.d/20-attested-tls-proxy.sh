#!/usr/bin/env bash
set -euo pipefail

echo "Installing attested-tls-proxy..."

VERSION="vtest-print-measurements-00"
EXPECTED_SHA256="3b5ce35f160dfb5eafd4a400e3a2985ad1115fc4f97a7584e4418acdaba74970"

curl -sSfL "https://github.com/flashbots/attested-tls-proxy/releases/download/${VERSION}/attested-tls-proxy_1.${VERSION}_amd64.deb" \
  -o $PACKAGEDIR/attested-tls-proxy.deb

echo "${EXPECTED_SHA256}" $PACKAGEDIR/attested-tls-proxy.deb | sha256sum --check

