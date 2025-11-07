#!/bin/bash

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
  fi

  sleep 1
done
