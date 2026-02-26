#!/bin/bash
set -eu -o pipefail

source /tmp/acme-le-cert-path
rm -f /tmp/acme-le-cert-path
install -D -m 600 --owner=operator-api --group=operator-api \
  "$PRIV_KEY" /var/lib/persistent/operator-api/key.pem
ln -fsr "$(dirname $CERT_PATH)/fullchain.cer" /var/lib/persistent/operator-api/cert.pem

install -D -m 600 --owner=attested-tls-proxy-server --group=attested-tls-proxy-server \
  "$PRIV_KEY" /var/lib/persistent/attested-tls-proxy-server/key.pem
ln -fsr "$(dirname $CERT_PATH)/fullchain.cer" /var/lib/persistent/attested-tls-proxy-server/cert.pem

chmod 660 /var/lib/persistent/haproxy/certs/*.pem
chown haproxy:haproxy /var/lib/persistent/haproxy/certs/*.pem
systemctl reload haproxy.service
