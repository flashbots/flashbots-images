#!/usr/bin/env bash
# bench-kernel.sh — Kernel-level benchmarks for hardening overhead measurement.
#
# Isolates kernel-level costs from hardening options (ASLR, FORTIFY_SOURCE,
# INIT_ON_ALLOC, RANDSTRUCT, SLAB hardening, etc.) by testing syscall latency,
# scheduler throughput, memory allocation, IPC, and scheduling jitter.
# Compare results between hardened and baseline kernel configs.
#
# Environment variables:
#   ITERATIONS — number of benchmark iterations (default: 3)
set -euo pipefail

ITERATIONS="${ITERATIONS:-3}"
REPORT="kernel_benchmark_report.txt"

: > "$REPORT"

echo "=== System Info ===" | tee -a "$REPORT"
uname -r | tee -a "$REPORT"
date -u | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

for i in $(seq 1 "$ITERATIONS"); do
  echo "========================================" | tee -a "$REPORT"
  echo "=== ITERATION $i/$ITERATIONS ===" | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  # ── Syscall & context-switch latency ──────────────────────────────
  echo "=== PERF BENCH: sched pipe (syscall + context-switch latency) ===" | tee -a "$REPORT"
  perf bench sched pipe -l 1000000 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  echo "=== PERF BENCH: sched messaging (scheduler throughput, 20 groups) ===" | tee -a "$REPORT"
  perf bench sched messaging -g 20 -l 1000 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  # ── Memory bandwidth & latency ────────────────────────────────────
  echo "=== PERF BENCH: mem memcpy (1 GB, FORTIFY_SOURCE overhead) ===" | tee -a "$REPORT"
  perf bench mem memcpy -s 1GB -l 5 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  echo "=== PERF BENCH: mem memset (1 GB, INIT_ON_ALLOC zeroing overhead) ===" | tee -a "$REPORT"
  perf bench mem memset -s 1GB -l 5 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  # ── IPC & scheduler saturation ────────────────────────────────────
  echo "=== HACKBENCH: pipes + threads ===" | tee -a "$REPORT"
  hackbench --pipe --threads -l 1000 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  echo "=== HACKBENCH: sockets + processes ===" | tee -a "$REPORT"
  hackbench -l 1000 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  # ── Targeted stressors (30s each) ────────────────────────────────
  echo "=== STRESS-NG: syscall overhead ===" | tee -a "$REPORT"
  stress-ng --syscall 1 --timeout 30 --metrics-brief 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  echo "=== STRESS-NG: malloc (INIT_ON_ALLOC / SLAB hardening overhead) ===" | tee -a "$REPORT"
  stress-ng --malloc 1 --timeout 30 --metrics-brief 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  echo "=== STRESS-NG: fork (ASLR / stack canaries / RANDSTRUCT overhead) ===" | tee -a "$REPORT"
  stress-ng --fork 1 --timeout 30 --metrics-brief 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  echo "=== STRESS-NG: context switch ===" | tee -a "$REPORT"
  stress-ng --switch 1 --timeout 30 --metrics-brief 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  echo "=== STRESS-NG: pipe (IPC throughput) ===" | tee -a "$REPORT"
  stress-ng --pipe 1 --timeout 30 --metrics-brief 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  # ── Scheduling latency ───────────────────────────────────────────
  echo "=== CYCLICTEST: scheduling latency (30s, 1000μs interval) ===" | tee -a "$REPORT"
  cyclictest --mlockall -p80 -t1 -i1000 -l30000 -q 2>&1 | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

done

echo "Report saved to $REPORT"
