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

# `echo -e` is not supported by dash on Debian
patch=$(
cat <<'EOF'
359c359
<       _socat_cert_set_cmd="echo -e '${_cmdpfx}set ssl cert ${_pem} <<\n$(cat "${_pem}")\n' | socat '${_statssock}' - | grep -q 'Transaction created'"
---
>       _socat_cert_set_cmd="{ printf 'set ssl cert %s <<\n' '${_pem}'; cat -- '${_pem}'; printf '\n'; } | socat '${_statssock}' - | grep -q 'Transaction created'"
EOF
)

echo "$patch" | patch "$DESTDIR/etc/acme-le/deploy/haproxy.sh" -

chmod +x "$DESTDIR/usr/bin/acme.sh"
chmod +x "$DESTDIR/etc/acme-le/deploy/haproxy.sh"
chmod +x "$DESTDIR/etc/acme-le/dnsapi/dns_cf.sh"
