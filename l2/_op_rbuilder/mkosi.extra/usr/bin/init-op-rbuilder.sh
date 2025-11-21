#!/bin/sh

set -eu

mkdir -p /home/op-rbuilder
chown -R op-rbuilder:optimism /home/op-rbuilder
chmod 0750 /home/op-rbuilder

if [ ! -d /var/opt/optimism/rbuilder ]; then
  mkdir -p /var/opt/optimism/rbuilder
  chown op-rbuilder:optimism /var/opt/optimism/rbuilder
  chmod 0750 /var/opt/optimism/rbuilder
fi

if [ -f /var/opt/optimism/rbuilder/genesis.json.tar.gz.base64 ]; then
  if [ -s /var/opt/optimism/rbuilder/genesis.json.tar.gz.base64 ]; then
    if [ ! -f /var/opt/optimism/rbuilder/genesis.json ]; then
      cat /var/opt/optimism/rbuilder/genesis.json.tar.gz.base64 | base64 -d | tar -xz -C /var/opt/optimism/rbuilder
      chown op-rbuilder:optimism /var/opt/optimism/rbuilder/genesis.json
      chmod 0640 /var/opt/optimism/rbuilder/genesis.json
    fi
  fi
fi

if [ -f /var/opt/optimism/rbuilder/genesis.json ]; then
  if [ ! -f /var/opt/optimism/rbuilder/db/database.version ]; then
    sudo -u op-rbuilder /usr/bin/op-rbuilder init \
      --chain /var/opt/optimism/rbuilder/genesis.json \
      --color never \
      --datadir /var/opt/optimism/rbuilder \
      --log.stdout.format json
    chown -R op-rbuilder:optimism /var/opt/optimism/rbuilder
  fi
fi
