#!/usr/bin/env bash
set -euo pipefail

EXPECTED_SHA256="815d6734ac2f78ea7e9e12b02efa8f9b0b3b283e07f898ebf90ede6910eb1843"
curl -sSfL https://github.com/flashbots/attested-tls-proxy/releases/download/vtest00/attested-tls-proxy_1.vtest00_amd64.deb -o $PACKAGEDIR/attested-tls-proxy.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/attested-tls-proxy.deb | sha256sum --check
