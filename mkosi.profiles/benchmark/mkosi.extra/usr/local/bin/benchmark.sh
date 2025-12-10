#!/usr/bin/env bash
set -euo pipefail

ITERATIONS="${ITERATIONS:-1}"
REPORT="benchmark_report.txt"

TESTDIR="${TESTDIR:-$PWD/fio-tmp}"
TESTFILE="$TESTDIR/fio.test"
SIZE="${SIZE:-2G}"

IPERF_SERVER="${IPERF_SERVER:-152.228.221.198}"
IPERF_PORT="${IPERF_PORT:-3535}"

mkdir -p "$TESTDIR"
chmod 700 "$TESTDIR"

: > "$REPORT"

for i in $(seq 1 "$ITERATIONS"); do
  echo "========================================" | tee -a "$REPORT"
  echo "=== ITERATION $i/$ITERATIONS ===" | tee -a "$REPORT"

  echo "=== CPU TEST ===" | tee -a "$REPORT"
  sysbench cpu --cpu-max-prime=50000 --time=60 --threads=1 run | tee -a "$REPORT"
  openssl speed --seconds 30 aes-256-cbc rsa2048 sha256 | tee -a "$REPORT"

  echo "=== MEMORY TEST ===" | tee -a "$REPORT"
  sysbench memory --memory-total-size=256G --memory-block-size=1Kb \
    --memory-oper=write --memory-access-mode=rnd --threads=1 run | tee -a "$REPORT"

  echo "=== DISK TESTS ===" | tee -a "$REPORT"

  echo "--- Throughput (iodepth=1) ---" | tee -a "$REPORT"
  fio --name=seqwrite1 --runtime=30 --time_based=1 \
    --filename="$TESTFILE" --size="$SIZE" --create_on_open=1 --unlink=1 \
    --bs=1M --direct=1 --sync=0 --randrepeat=0 --rw=write --end_fsync=1 \
    --iodepth=1 --ioengine=libaio 2>&1 | tee -a "$REPORT"

  echo "--- Throughput (iodepth=128) ---" | tee -a "$REPORT"
  fio --name=seqwrite128 --runtime=30 --time_based=1 \
    --filename="$TESTFILE" --size="$SIZE" --create_on_open=1 --unlink=1 \
    --bs=1M --direct=1 --sync=0 --randrepeat=0 --rw=write --end_fsync=1 \
    --iodepth=128 --ioengine=libaio 2>&1 | tee -a "$REPORT"

  echo "--- Latency (iodepth=1) ---" | tee -a "$REPORT"
  fio --time_based=1 --name=randlat1 --runtime=30 \
    --filename="$TESTFILE" --size="$SIZE" --create_on_open=1 --unlink=1 \
    --ioengine=libaio --randrepeat=0 --iodepth=1 --direct=1 --invalidate=1 \
    --verify=0 --verify_fatal=0 --numjobs=1 --rw=randwrite --blocksize=4k \
    --group_reporting --norandommap 2>&1 | tee -a "$REPORT"

  echo "--- Latency (iodepth=128) ---" | tee -a "$REPORT"
  fio --time_based=1 --name=randlat128 --runtime=30 \
    --filename="$TESTFILE" --size="$SIZE" --create_on_open=1 --unlink=1 \
    --ioengine=libaio --randrepeat=0 --iodepth=128 --direct=1 --invalidate=1 \
    --verify=0 --verify_fatal=0 --numjobs=1 --rw=randwrite --blocksize=4k \
    --group_reporting --norandommap 2>&1 | tee -a "$REPORT"

  # echo "=== NETWORK TEST ===" | tee -a "$REPORT"
  # # Run iperf3 server on another host: iperf3 -s -p $IPERF_PORT
  # iperf3 -c "$IPERF_SERVER" -p "$IPERF_PORT" -t 30 | tee -a "$REPORT"

  echo "=== STRESS TEST (CPU, memory, I/O) ===" | tee -a "$REPORT"
  stress-ng --cpu 4 --io 2 --vm 2 --vm-bytes 1G --timeout 60s --metrics-brief 2>&1 | tee -a "$REPORT"

done

echo "Report saved to $REPORT"
