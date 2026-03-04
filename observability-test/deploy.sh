#!/bin/bash
set -euo pipefail

HOST="${1:?usage: ./deploy.sh root@<host>}"
REMOTE_DIR="/root/observability-test"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Deploying to $HOST:$REMOTE_DIR ..."
COPYFILE_DISABLE=1 tar czf - -C "$SCRIPT_DIR" --exclude='._*' . | ssh "$HOST" "mkdir -p $REMOTE_DIR && tar xzf - -C $REMOTE_DIR"

echo "==> Updating recording rules on VM Prometheus..."
ssh "$HOST" "cp $REMOTE_DIR/recording_rules.yml /etc/prometheus/recording_rules.yml"

echo "==> Ensuring vmstat metrics are scraped..."
ssh "$HOST" "sed -i 's/node_(cpu|memory|disk|filesystem|network)_/node_(cpu|memory|disk|filesystem|network|vmstat)_/' /etc/prometheus/prometheus.yml"

echo "==> Ensuring vmstat collector is enabled..."
ssh "$HOST" "sed -i 's/--no-collector.vmstat/--collector.vmstat/' /etc/systemd/system/node-exporter.service && systemctl daemon-reload && systemctl restart node-exporter 2>/dev/null || true"

echo "==> Reloading Prometheus..."
ssh "$HOST" "kill -HUP \$(pgrep -x prometheus)"

echo "==> Restarting containers..."
ssh "$HOST" "cd $REMOTE_DIR && bash run.sh"
