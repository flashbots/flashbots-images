#!/bin/bash

set -euxo pipefail

if hostname=$(
    curl \
      --connect-timeout 1 \
      --fail \
      --header "Metadata-Flavor: Google" \
      --retry 10 \
      --retry-all-errors \
      --retry-delay 1 \
      --show-error \
      --silent \
    http://169.254.169.254/computeMetadata/v1/instance/name
  ); then

  echo "Setting hostname to '${hostname}'..."

  hostname "${hostname}"
  echo "127.0.0.1 ${hostname}" >> /etc/hosts

  systemctl restart rsyslog.service || true
else
  echo "Failed to get instance name from metadata service"
  exit 1
fi
