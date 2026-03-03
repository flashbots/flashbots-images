#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Clean up any existing containers
podman rm -f flashbox-prometheus-passive flashbox-grafana 2>/dev/null || true

echo "==> Starting passive Prometheus (port 9999, receives remote_write)..."
podman run -d \
  --name flashbox-prometheus-passive \
  --network=host \
  -v "$SCRIPT_DIR/prometheus-passive.yml:/etc/prometheus/prometheus.yml:ro" \
  docker.io/prom/prometheus:latest \
  --config.file=/etc/prometheus/prometheus.yml \
  --web.listen-address=:9999 \
  --web.enable-remote-write-receiver \
  --storage.tsdb.retention.time=24h

echo "==> Starting Grafana (port 3000)..."
podman run -d \
  --name flashbox-grafana \
  --network=host \
  -v "$SCRIPT_DIR/grafana/provisioning:/etc/grafana/provisioning:ro" \
  -v "$SCRIPT_DIR/grafana/dashboards:/var/lib/grafana/dashboards:ro" \
  -e GF_SECURITY_ADMIN_PASSWORD=flashboxes \
  -e GF_AUTH_ANONYMOUS_ENABLED=false \
  -e GF_SERVER_HTTP_ADDR=0.0.0.0 \
  docker.io/grafana/grafana:latest

echo ""
echo "==> Done! Services running:"
echo "    Grafana:              http://localhost:3000"
echo "    Prometheus (local):   http://localhost:9090  (existing, all metrics)"
echo "    Prometheus (passive): http://localhost:9999  (remote_write receiver, flashbox:* only)"
echo ""
echo "    Stop with: bash $SCRIPT_DIR/stop.sh"
