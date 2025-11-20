#!/bin/bash

if ! which curl; then
  echo "curl is not present on system, exiting..."
  exit 0
fi

while true; do
  if hostname=$(
    curl --header "Metadata-Flavor: Google" --silent --show-error \
      http://169.254.169.254/computeMetadata/v1/instance/name
  ); then
    echo "Setting up hostname to '${hostname}'..."
    hostname ${hostname}
    echo 127.0.0.1 "${hostname}" >> /etc/hosts
    systemctl restart rsyslog
    exit 0
  else
    echo "Failed to query metadata service, will retry in 1s"
  fi

  sleep 1
done
