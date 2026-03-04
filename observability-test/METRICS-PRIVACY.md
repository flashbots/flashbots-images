# Metrics Privacy

## Timing

- L1: ~12s/block, L2: ~2s/block
- All rules eval every 30s
- Bucketed levels use 15m `avg_over_time` → ~75 L1 blocks / ~450 L2 blocks of smoothing
- A spike needs to sustain minutes before a level changes

## What leaves the TEE

Only `flashbox:*` metrics are forwarded via remote_write. Base percentages use a `local:` prefix and stay inside.

| Metric | Type | Notes |
|--------|------|-------|
| `flashbox:cpu_level` | bucket (15m avg) | host CPU, integer 1-4 |
| `flashbox:memory_level` | bucket (15m avg) | host memory, integer 1-4 |
| `flashbox:container_cpu_level` | bucket (15m avg) | searcher CPU, integer 1-4 |
| `flashbox:container_memory_level` | bucket (15m avg) | searcher memory, integer 1-4 |
| `flashbox:container_alive` | binary | process up/down |
| `flashbox:disk_usage_percent_root` | instant | slow-moving |
| `flashbox:disk_usage_percent_persistent` | instant | slow-moving |
| `flashbox:disk_io_read_mb_per_sec` | 5m rate | summed across devices |
| `flashbox:disk_io_write_mb_per_sec` | 5m rate | summed across devices |
| `flashbox:network_receive_mb_per_sec` | 5m rate | summed across interfaces |
| `flashbox:network_transmit_mb_per_sec` | 5m rate | summed across interfaces |

## Bucket thresholds

**CPU**: 🟢 0-20 🟡 20-40 🟠 40-85 🔴 85+

**Memory**: 🟢 0-30 🟡 30-70 🟠 70-90 🔴 90+

Container memory = % of total VM RAM (no cgroup limit, container has access to all VM RAM).

Thresholds are initial guesses — need tuning with real workloads.

## Recording rules

[`recording_rules.yml`](recording_rules.yml)
