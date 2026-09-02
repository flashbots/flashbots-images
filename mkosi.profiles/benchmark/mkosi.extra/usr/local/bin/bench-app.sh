#!/usr/bin/env bash
# bench-app.sh — Application-level benchmarks for kernel performance regression testing.
#
# Disk I/O tests use psync/mmap engines (CONFIG_AIO and CONFIG_IO_URING are
# disabled per KSPP hardening). Test profiles reflect Ethereum node workloads:
#   - 4K random mixed 75R/25W  (chain-following steady state)
#   - 4K random write + fsync  (MDBX commit path)
#   - Buffered/mmap 4K reads   (memory-mapped database access)
#   - Sequential 1M r/w        (bulk data, compaction, snapshots)
#
# References:
#   fio I/O engines (psync, libaio, io_uring):
#     https://fio.readthedocs.io/en/latest/fio_doc.html
#   MDBX I/O model (mmap reads, fdatasync commits):
#     https://libmdbx.dqdkfa.ru/intro.html
#     https://libmdbx.dqdkfa.ru/group__sync__modes.html
#   Intel TDX performance benchmarking (MLC, fio, iperf3):
#     https://www.intel.com/content/www/us/en/developer/articles/technical/tdx-performance-analysis-reference-documentation.html
#   Ethereum node disk requirements:
#     https://docs.nethermind.io/get-started/system-requirements/
#     https://geth.ethereum.org/docs/getting-started/hardware-requirements
#     https://reth.rs/run/system-requirements/
#
# Environment variables:
#   ITERATIONS   — benchmark iterations      (default: 1)
#   TESTDIR      — fio working directory       (default: /persistent/fio-tmp)
#   SIZE         — fio test file size         (default: 2G)
#   FIO_RUNTIME  — seconds per fio test       (default: 30)
#   IPERF_SERVER — iperf3 server; skipped if unset
#   IPERF_PORT   — iperf3 port               (default: 5201)
set -uo pipefail

ITERATIONS="${ITERATIONS:-1}"
REPORT="benchmark_report.txt"

TESTDIR="${TESTDIR:-/persistent/fio-tmp}"
TESTFILE=""  # set after mkdir
SIZE="${SIZE:-2G}"
FIO_RUNTIME="${FIO_RUNTIME:-30}"

IPERF_PORT="${IPERF_PORT:-5201}"

mkdir -p "$TESTDIR"
chmod 700 "$TESTDIR"
TESTFILE="$TESTDIR/fio.test"

: > "$REPORT"

# Run a benchmark command, log output, continue on failure.
run_bench() {
  local label="$1"; shift
  echo "=== $label ===" | tee -a "$REPORT"
  if "$@" 2>&1 | tee -a "$REPORT"; then
    :
  else
    echo "*** FAILED (exit $?): $label ***" | tee -a "$REPORT"
  fi
  echo "" | tee -a "$REPORT"
}

# Common fio arguments
fio_common="--time_based --runtime=${FIO_RUNTIME} --group_reporting --thread"

for i in $(seq 1 "$ITERATIONS"); do
  echo "========================================" | tee -a "$REPORT"
  echo "=== ITERATION $i/$ITERATIONS ===" | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  # ── CPU ──────────────────────────────────────────────────────────────
  run_bench "CPU: sysbench prime" \
    sysbench cpu --cpu-max-prime=50000 --time=30 --threads=1 run

  run_bench "CPU: openssl speed" \
    openssl speed --seconds 10 aes-256-cbc rsa2048 sha256

  # ── Memory ───────────────────────────────────────────────────────────
  run_bench "MEMORY: sysbench random write" \
    sysbench memory --memory-total-size=256G --memory-block-size=1Kb \
      --memory-oper=write --memory-access-mode=rnd --threads=1 run

  # ── Disk I/O ─────────────────────────────────────────────────────────
  echo "=== DISK I/O (ioengine=psync, direct=1 unless noted) ===" | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"

  # Sequential throughput — bulk data: WAL, compaction, snapshots
  run_bench "DISK: sequential write throughput (1M, 4 jobs)" \
    fio --name=seq-write $fio_common \
      --ioengine=psync --direct=1 --rw=write --bs=1M \
      --numjobs=4 --size="$SIZE" \
      --filename="$TESTFILE"

  run_bench "DISK: sequential read throughput (1M, 4 jobs)" \
    fio --name=seq-read $fio_common \
      --ioengine=psync --direct=1 --rw=read --bs=1M \
      --numjobs=4 --size="$SIZE" \
      --filename="$TESTFILE"

  # Random 4K IOPS — database state access (dominant I/O pattern)
  run_bench "DISK: random 4K read IOPS (16 jobs)" \
    fio --name=rand-read $fio_common \
      --ioengine=psync --direct=1 --rw=randread --bs=4k \
      --numjobs=16 --size="$SIZE" \
      --filename="$TESTFILE"

  run_bench "DISK: random 4K write IOPS (16 jobs)" \
    fio --name=rand-write $fio_common \
      --ioengine=psync --direct=1 --rw=randwrite --bs=4k \
      --numjobs=16 --size="$SIZE" \
      --filename="$TESTFILE"

  # Mixed 4K 75R/25W — Ethereum node steady-state profile
  # Reference: Nethermind requires ≥10K IOPS (r/w); all clients require NVMe SSD
  run_bench "DISK: random 4K mixed 75R/25W (16 jobs) — steady state" \
    fio --name=rand-mixed $fio_common \
      --ioengine=psync --direct=1 --rw=randrw --rwmixread=75 --bs=4k \
      --numjobs=16 --size="$SIZE" \
      --filename="$TESTFILE"

  # fsync-per-write — measures full commit cycle (write + fdatasync)
  # Key metric: "sync" percentiles in output, not "clat"
  run_bench "DISK: random 4K write + fsync (1 job) — commit latency" \
    fio --name=rand-fsync $fio_common \
      --ioengine=psync --direct=1 --rw=randwrite --bs=4k \
      --numjobs=1 --size="$SIZE" --fsync=1 \
      --filename="$TESTFILE"

  # Buffered mmap reads — page-cache path used by memory-mapped databases
  # Validate: output should show major page faults (majf); if zero, data was cached
  run_bench "DISK: buffered random 4K read (mmap, 4 jobs) — page-cache path" \
    fio --name=mmap-read $fio_common \
      --ioengine=mmap --direct=0 --rw=randread --bs=4k \
      --numjobs=4 --size="$SIZE" \
      --filename="$TESTFILE"

  # ── Network ──────────────────────────────────────────────────────────
  if [[ -n "${IPERF_SERVER:-}" ]]; then
    run_bench "NETWORK: iperf3 upload (VM → host)" \
      iperf3 -c "$IPERF_SERVER" -p "$IPERF_PORT" -t 30
    run_bench "NETWORK: iperf3 download (host → VM)" \
      iperf3 -c "$IPERF_SERVER" -p "$IPERF_PORT" -t 30 -R
    run_bench "NETWORK: ping latency (100 packets)" \
      ping -c 100 -i 0.2 -W 1 "$IPERF_SERVER"
  else
    echo "=== NETWORK: skipped (set IPERF_SERVER to enable) ===" | tee -a "$REPORT"
    echo "" | tee -a "$REPORT"
  fi

  # ── Entropy ──────────────────────────────────────────────────────────
  # TDX attestation and key generation depend on RDRAND/entropy throughput.
  run_bench "ENTROPY: /dev/urandom throughput (256 MB)" \
    dd if=/dev/urandom of=/dev/null bs=1M count=256 iflag=fullblock

  # ── Stress ───────────────────────────────────────────────────────────
  run_bench "STRESS: combined (4 cpu, 2 io, 2 vm)" \
    stress-ng --cpu 4 --io 2 --vm 2 --vm-bytes 1G --timeout 30s --metrics-brief

  # Clean up test file between iterations
  rm -f "$TESTFILE"

done

rm -rf "$TESTDIR"
echo "========================================" | tee -a "$REPORT"
echo "Report saved to $REPORT"
