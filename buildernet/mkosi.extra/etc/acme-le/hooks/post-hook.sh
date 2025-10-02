#!/bin/bash
set -eu -o pipefail

source /usr/bin/helper-functions.sh

MAIN_DOMAIN=$(echo "$DNS_NAMES" | cut -d',' -f1)
CERT_PATH=$(find "$ACME_HOME" -name "${MAIN_DOMAIN}.cer" | head -n 1)
# sed puts '\\n' at the end of every line, then tr removes the newlines.
CERT_ESCAPED=$(sed 's/$/\\n/g' "$CERT_PATH" | tr -d '\n')

# Register the certificate with BuilderHub
curl -fsSL --retry 3 --retry-delay 60 --retry-connrefused \
  -H "Content-Type: application/json" \
  -d "{\"tls_cert\": \"$CERT_ESCAPED\"}" \
  http://localhost:7937/api/l1-builder/v1/register_credentials/instance || (

  log "acme-le (post-hook): Failed to register TLS certificate with BuilderHub."
  exit 1
)
log "acme-le (post-hook): TLS certificate registered successfully with BuilderHub."

# Export cert expiration date as a metric
EXPIRATION_DATE=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)
EXPIRATION_DATE_UNIX_SECONDS=$(date -d "$EXPIRATION_DATE" +%s)
METRICS_FILE="$RUNTIME_DIRECTORY/acme_le_cert_expiration.prom"
printf "# HELP acme_le_cert_expiration_seconds The expiration date of the ACME certificate in Unix time.
# TYPE acme_le_cert_expiration_seconds gauge
acme_le_cert_expiration_seconds{domain=\"$MAIN_DOMAIN\"} $EXPIRATION_DATE_UNIX_SECONDS\n" > "$METRICS_FILE"

# Create a symlink to the private key so acme.sh can find it
ln -fsr "$PRIV_KEY" "$(dirname $CERT_PATH)/${MAIN_DOMAIN}.key"

# Copy Let's Encrypt certificate to HAProxy certs directory to serve
# it through CVM proxy.
mkdir -p /var/lib/persistent/haproxy/static
install -m 644 --no-target-directory "$CERT_PATH" /var/lib/persistent/haproxy/static/le.cer

install -D -m 600 --owner=operator-api --group=operator-api \
  "$PRIV_KEY" /var/lib/persistent/operator-api/key.pem
install -D -m 644 --owner=operator-api --group=operator-api \
  "$CERT_PATH" /var/lib/persistent/operator-api/cert.pem
