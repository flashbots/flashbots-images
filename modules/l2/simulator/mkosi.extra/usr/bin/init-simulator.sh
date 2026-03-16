#!/bin/sh

set -eu

if [ ! -d /home/simulator ]; then
  mkdir -p /home/simulator
  chown -R simulator:optimism /home/simulator
  chmod 0750 /home/simulator
fi

if [ ! -d /var/opt/optimism/simulator ]; then
  if [ -d /var/opt/optimism/rbuilder ]; then
    mv /var/opt/optimism/rbuilder /var/opt/optimism/simulator
  else
    mkdir -p /var/opt/optimism/simulator
  fi

  chown -R simulator:optimism /var/opt/optimism/simulator
  chmod 0750 /var/opt/optimism/simulator
fi

if [ -f /var/opt/optimism/simulator/genesis.json.tar.gz.base64 ]; then
  if [ -s /var/opt/optimism/simulator/genesis.json.tar.gz.base64 ]; then
    if [ ! -f /var/opt/optimism/simulator/genesis.json ]; then
      cat /var/opt/optimism/simulator/genesis.json.tar.gz.base64 | base64 -d | tar -xz -C /var/opt/optimism/simulator
      chown simulator:optimism /var/opt/optimism/simulator/genesis.json
      chmod 0640 /var/opt/optimism/simulator/genesis.json
    fi
  fi
fi

if [ -f /var/opt/optimism/simulator/genesis.json ]; then
  if [ ! -f /var/opt/optimism/simulator/db/database.version ]; then
    sudo -u simulator /usr/bin/simulator init \
      --chain /var/opt/optimism/simulator/genesis.json \
      --color never \
      --datadir /var/opt/optimism/simulator \
      --log.stdout.format json
    chown -R simulator:optimism /var/opt/optimism/simulator
  fi
fi
