# Metrics Privacy

## Timing

- L1: ~12s/block, L2: ~2s/block
- All rules eval every 30s
- Boolean metrics use 15m `avg_over_time` or 5m `rate` windows — no instantaneous values leave the TEE
- CPU metric includes a spike guard: `max_over_time` with `offset 5m` prevents rapid transitions from leaking side-channel information

## What leaves the TEE

Only `flashbox:*` metrics are forwarded via remote_write. The single local helper (`local:container_cpu_percent`) stays inside.

| Metric | Type | Notes |
|--------|------|-------|
| `flashbox:container_alive` | bool | searcher process up/down |
| `flashbox:container_average_cpu_is_under_80_percent` | bool | 15m avg < 80% AND spike-guarded (10m max offset 5m < 70%) |
| `flashbox:container_oom_kills_count` | counter | system-wide OOM kill count (`node_vmstat_oom_kill`) |
| `flashbox:disk_free_space_is_over_10_percent` | bool | root filesystem has >10% available |
| `flashbox:disk_free_space_is_over_128_gb` | bool | persistent volume has >128GB available |
| `flashbox:network_is_up` | bool | any non-loopback traffic in last 5m |

## Spike guard

The CPU metric uses Anton's spike guard formula to prevent side-channel signaling via rapid metric transitions:

```
(avg_over_time(local:container_cpu_percent[15m]) < bool 80)
* (max_over_time(local:container_cpu_percent[10m] offset 5m) < bool 70)
```

Both conditions must be true for the metric to report `1` (healthy). The `offset 5m` lookback means a spike that occurred in the last 5 minutes will keep the metric at `0` even if current average is below threshold.

## Recording rules

[`recording_rules.yml`](recording_rules.yml)
