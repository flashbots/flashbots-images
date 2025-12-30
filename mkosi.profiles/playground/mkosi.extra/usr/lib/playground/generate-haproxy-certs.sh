#!/bin/bash
# Generate self-signed TLS certificates for HAProxy in playground mode.
set -eu -o pipefail

CERT_DIR="/var/lib/persistent/haproxy/certs"
STATIC_DIR="/var/lib/persistent/haproxy/static"

# Skip if certs already exist
if ls "$CERT_DIR"/*.pem 1>/dev/null 2>&1; then
    echo "playground: HAProxy certs already exist, skipping generation"
    exit 0
fi

KEY=$(mktemp)
CERT=$(mktemp)
trap 'rm -f "$KEY" "$CERT"' EXIT

openssl ecparam -name prime256v1 -genkey -noout -out "$KEY"
openssl req -new -x509 -key "$KEY" -sha256 -days 3650 \
    -subj "/O=Playground/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:10.0.2.2" \
    -out "$CERT"

cat "$KEY" "$CERT" > "$CERT_DIR/localhost.pem"
chown haproxy:haproxy "$CERT_DIR/localhost.pem"
chmod 660 "$CERT_DIR/localhost.pem"

cp "$CERT" "$STATIC_DIR/le.cer"
chown haproxy:haproxy "$STATIC_DIR/le.cer"

echo "playground: Generated self-signed TLS certificate for HAProxy"
