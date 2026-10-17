#!/usr/bin/env bash
# Warmup: prime subsystems before benchmark iterations to avoid cold-start skew.
#
# Currently warms up:
#   - iperf3:          short run to establish SLIRP buffers and TCP state
#   - stress-ng syscall
#
# Add future warmup steps here as needed.
#
# Environment variables:
#   IPERF_SERVER — iperf3 server address (same as bench-app.sh); warmup skipped if unset
#   IPERF_PORT   — iperf3 port (default: 5201)
set -euo pipefail

IPERF_PORT="${IPERF_PORT:-5201}"

# ── iperf3 ────────────────────────────────────────────────────────────────────
if [[ -n "${IPERF_SERVER:-}" ]]; then
  echo "Warming up iperf3 (5s, discarded)..."
  iperf3 -c "$IPERF_SERVER" -p "$IPERF_PORT" -t 5 > /dev/null 2>&1 || true
fi

# ── stress-ng syscall ─────────────────────────────────────────────────────────
# Iter 1 shows a 20x cold-boot spike (370 vs stable 17 ops/s). Running once
# here consumes the anomaly so all measured iterations land at the stable value.
echo "Warming up stress-ng syscall (5s, discarded)..."
stress-ng --syscall 1 --timeout 5 > /dev/null 2>&1 || true

echo "Warmup done."
