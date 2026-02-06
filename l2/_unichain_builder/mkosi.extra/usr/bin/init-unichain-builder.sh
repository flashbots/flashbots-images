#!/bin/sh

set -eu

if [ ! -d /home/unichain-builder ]; then
  mkdir -p /home/unichain-builder
  chown -R unichain-builder:optimism /home/unichain-builder
  chmod 0750 /home/unichain-builder
fi

if [ ! -d /var/opt/optimism/unichain-builder ]; then
  if [ -d /var/opt/optimism/rbuilder ]; then
    mv /var/opt/optimism/rbuilder /var/opt/optimism/unichain-builder
  else
    mkdir -p /var/opt/optimism/unichain-builder
  fi

  chown -R unichain-builder:optimism /var/opt/optimism/unichain-builder
  chmod 0750 /var/opt/optimism/unichain-builder
fi

if [ -f /var/opt/optimism/unichain-builder/genesis.json.tar.gz.base64 ]; then
  if [ -s /var/opt/optimism/unichain-builder/genesis.json.tar.gz.base64 ]; then
    if [ ! -f /var/opt/optimism/unichain-builder/genesis.json ]; then
      cat /var/opt/optimism/unichain-builder/genesis.json.tar.gz.base64 | base64 -d | tar -xz -C /var/opt/optimism/unichain-builder
      chown unichain-builder:optimism /var/opt/optimism/unichain-builder/genesis.json
      chmod 0640 /var/opt/optimism/unichain-builder/genesis.json
    fi
  fi
fi

if [ -f /var/opt/optimism/unichain-builder/genesis.json ]; then
  if [ ! -f /var/opt/optimism/unichain-builder/db/database.version ]; then
    sudo -u unichain-builder /usr/bin/unichain-builder init \
      --chain /var/opt/optimism/unichain-builder/genesis.json \
      --color never \
      --datadir /var/opt/optimism/unichain-builder \
      --log.stdout.format json
    chown -R unichain-builder:optimism /var/opt/optimism/unichain-builder
  fi
fi
