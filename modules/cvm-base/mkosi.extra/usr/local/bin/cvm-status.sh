#!/bin/sh
# cvm-status.sh: human-readable snapshot of the cvm-base runtime state.
# Invoked by cvm-shell as the `status` command.

set -u

echo "=== /persistent mount ==="
if grep -q " /persistent " /proc/mounts; then
    grep " /persistent " /proc/mounts
else
    echo "not mounted (run 'initialize' first)"
fi

echo
echo "=== RTMR3 (sha384 hex) ==="
RTMR3_NODE=/sys/class/misc/tdx_guest/measurements/rtmr3:sha384
if [ -r "$RTMR3_NODE" ]; then
    od -An -tx1 -v "$RTMR3_NODE" | tr -d ' \n'
    echo
else
    echo "RTMR3 sysfs node not present (not on TDX host)"
fi

echo
echo "=== cvm-provisioner ==="
if curl -fsS --max-time 2 http://127.0.0.1:8888/status; then
    echo
else
    echo "(provisioner not reachable on 127.0.0.1:8888)"
fi
