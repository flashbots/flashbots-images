#!/bin/bash
set -euo pipefail

echo "==> Stopping containers..."
podman stop flashbox-grafana flashbox-prometheus-passive 2>/dev/null || true
podman rm flashbox-grafana flashbox-prometheus-passive 2>/dev/null || true
echo "==> Done."
