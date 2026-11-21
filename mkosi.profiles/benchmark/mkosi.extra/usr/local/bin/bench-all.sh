#!/usr/bin/env bash
# Wrapper: runs both kernel-level and application-level benchmarks.
# Usage: bench-all.sh [ITERATIONS]
set -euo pipefail

export ITERATIONS="${1:-3}"

bench-preflight.sh
bench-warmup.sh

echo "=== Running kernel-level benchmarks ==="
bench-kernel.sh

echo ""
echo "=== Running application-level benchmarks ==="
bench-app.sh

echo ""
echo "=== Done ==="
echo "Results in: kernel_benchmark_report.txt, benchmark_report.txt"
