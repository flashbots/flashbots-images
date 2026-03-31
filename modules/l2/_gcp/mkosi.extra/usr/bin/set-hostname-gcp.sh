#!/bin/bash

set -euxo pipefail

hostname=$(
  curl \
    --fail \
    --header "Metadata-Flavor: Google" \
    --retry 100 \
    --retry-all-errors \
    --retry-delay 1 \
    --show-error \
    --silent \
  http://169.254.169.254/computeMetadata/v1/instance/name
)

echo "Setting hostname to '${hostname}'..."

hostname "${hostname}"
echo "127.0.0.1 ${hostname}" >> /etc/hosts

systemctl restart rsyslog.service || true
