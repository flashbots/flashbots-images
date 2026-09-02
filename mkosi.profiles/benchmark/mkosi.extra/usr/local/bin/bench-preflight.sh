#!/usr/bin/env bash
# Pre-flight check: detect and optionally stop application services
# that would skew benchmark results.
#
# Usage: bench-preflight.sh
#
# Environment variables:
#   BENCH_STOP_SERVICES=1    stop detected services automatically
#
# Interactive (TTY detected):   prompts user to stop services
# Non-interactive (no TTY):     stops only if BENCH_STOP_SERVICES=1, otherwise warns
set -euo pipefail

# ── iperf3 firewall check ─────────────────────────────────────────────────────
# Only runs when IPERF_SERVER is set (same env var bench-app.sh uses).
# Uses nc with a short timeout — if the port is unreachable, the OUTPUT chain
# is likely blocking it (the VM firewall defaults to DROP).
if [[ -n "${IPERF_SERVER:-}" ]]; then
  _iperf_port="${IPERF_PORT:-5201}"
  if ! nc -z -w2 "$IPERF_SERVER" "$_iperf_port" 2>/dev/null; then
    echo "=== iperf3 firewall check ==="
    echo "Cannot reach iperf3 server at $IPERF_SERVER:$_iperf_port"
    echo "The VM firewall (default OUTPUT DROP) is likely blocking TCP port $_iperf_port."
    echo ""

    _should_unblock=false
    if [[ "${BENCH_UNBLOCK_IPERF:-0}" == "1" ]]; then
      _should_unblock=true
    elif [[ -t 0 ]]; then
      read -rp "Add iptables rules to allow iperf3 on port $_iperf_port? [Y/n] " _reply
      if [[ -z "$_reply" || "$_reply" =~ ^[Yy] ]]; then
        _should_unblock=true
      fi
    else
      echo "WARNING: iperf3 test will likely fail — set BENCH_UNBLOCK_IPERF=1 to unblock automatically."
    fi

    if $_should_unblock; then
      iptables -I OUTPUT 1 -p tcp  --dport "$_iperf_port" -m comment --comment "bench-iperf3" -j ACCEPT
      iptables -I INPUT  1 -p tcp  --sport "$_iperf_port" -m comment --comment "bench-iperf3" -j ACCEPT
      iptables -I OUTPUT 1 -p icmp                        -m comment --comment "bench-iperf3" -j ACCEPT
      iptables -I INPUT  1 -p icmp                        -m comment --comment "bench-iperf3" -j ACCEPT
      echo "iptables rules added — port $_iperf_port and ICMP unblocked (comment: bench-iperf3)."
    fi
    echo ""
  fi
fi

APP_SERVICES=(
  lighthouse
  searcher-container
  cvm-reverse-proxy
  ssh-pubkey-server
  input-only-proxy
  delay-pipe
)

running=()
for svc in "${APP_SERVICES[@]}"; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    running+=("$svc")
  fi
done

if [[ ${#running[@]} -eq 0 ]]; then
  echo "Pre-flight OK: no application services running."
  exit 0
fi

echo "=== Pre-flight check ==="
echo "Running application services that may skew results:"
for svc in "${running[@]}"; do
  pid=$(systemctl show -p MainPID --value "$svc" 2>/dev/null)
  if [[ -n "$pid" && "$pid" != "0" ]]; then
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null || echo "?")
    mem=$(ps -p "$pid" -o %mem= 2>/dev/null || echo "?")
    printf "  %-30s  CPU: %s%%  MEM: %s%%\n" "$svc" "${cpu// /}" "${mem// /}"
  else
    printf "  %-30s  (no main PID)\n" "$svc"
  fi
done
echo ""

if [[ "${BENCH_STOP_SERVICES:-0}" == "1" ]]; then
  should_stop=true
elif [[ -t 0 ]]; then
  read -rp "Stop these services before benchmarking? [Y/n] " reply
  if [[ -z "$reply" || "$reply" =~ ^[Yy] ]]; then
    should_stop=true
  else
    should_stop=false
  fi
else
  echo "WARNING: benchmarking with application services active — results may be noisy."
  echo "Set BENCH_STOP_SERVICES=1 to stop them automatically."
  should_stop=false
fi

if $should_stop; then
  for svc in "${running[@]}"; do
    echo "Stopping $svc..."
    systemctl stop "$svc"
  done
  echo "All application services stopped."
elif ! $should_stop; then
  echo "WARNING: benchmarking with application services active — results may be noisy."
fi
