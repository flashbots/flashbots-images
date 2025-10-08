#!/usr/bin/env bash
set -euo pipefail

echo "Installing acme.sh..."

COMMIT_HASH=42bbd1b44af48a5accce07fa51740644b1c5f0a0

mkdir -p $DESTDIR/usr/bin
mkdir -p $DESTDIR/etc/acme-le/deploy
mkdir -p $DESTDIR/etc/acme-le/dnsapi

curl -fSsL -o $DESTDIR/usr/bin/acme.sh "https://raw.githubusercontent.com/acmesh-official/acme.sh/$COMMIT_HASH/acme.sh"
curl -fSsL -o $DESTDIR/etc/acme-le/deploy/haproxy.sh "https://raw.githubusercontent.com/acmesh-official/acme.sh/$COMMIT_HASH/deploy/haproxy.sh"
curl -fSsL -o $DESTDIR/etc/acme-le/dnsapi/dns_cf.sh "https://raw.githubusercontent.com/acmesh-official/acme.sh/$COMMIT_HASH/dnsapi/dns_cf.sh"

chmod +x "$DESTDIR/usr/bin/acme.sh"
chmod +x "$DESTDIR/etc/acme-le/deploy/haproxy.sh"
chmod +x "$DESTDIR/etc/acme-le/dnsapi/dns_cf.sh"
