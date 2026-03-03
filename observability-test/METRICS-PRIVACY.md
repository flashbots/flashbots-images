# Metrics Privacy

## Block times

- L1: ~12s → 1 datapoint per ~25 blocks (at 5m eval)
- L2: ~2s → 1 datapoint per ~150 blocks (at 5m eval)

## Current state (Moe's branch)

Single rule group, 30s eval interval. All `flashbox:*` forwarded via remote_write.

| Metric | Aggregation | Problem |
|--------|------------|---------|
| `cpu_usage_percent` | 5m rate | |
| `cpu_usage_percent_by_mode` | 5m rate | |
| `memory_usage_percent` | **instant** | exact value every 30s, no smoothing |
| `memory_available_gb` | **instant** | same |
| `disk_usage_percent_root` | instant | ok, slow-moving |
| `disk_usage_percent_persistent` | instant | ok, slow-moving |
| `disk_io_*_mb_per_sec` | 5m rate | |
| `network_receive_mb_total` | **raw counter** | can diff consecutive points → exact 30s throughput |
| `network_transmit_mb_total` | **raw counter** | same |
| `container_alive` | instant | ok, binary |
| `container_cpu_percent` | 5m rate | leaks `mode` label (user/system split) |
| `container_memory_mb` | **instant** | leaks `memtype` label (resident/virtual/swapped) |

With 30s eval, each datapoint covers ~2 L1 blocks or ~15 L2 blocks. Enough to correlate activity spikes with on-chain events.

## Proposed changes

Split into two rule groups with independent eval intervals:
- `flashbox_host_metrics`: 30s eval (ops needs responsiveness)
- `flashbox_container_metrics`: **5m eval** (1 datapoint per ~25 L1 blocks / ~150 L2 blocks)

| Change | Current | Proposed |
|--------|---------|----------|
| host memory | instant | `avg_over_time(...[5m:])` |
| network | raw counters (`_mb_total`) | 5m windowed rates (`_mb_per_sec`) |
| container memory | instant, all memtypes | `avg_over_time(...[5m:])`, resident only |
| container CPU | leaks mode label | `sum()` across modes |
| container eval interval | 30s | 5m |

Proposed recording rules are in [`observability-test/recording_rules.yml`](recording_rules.yml).

## Open questions

1. **Container-level metrics**: `container_cpu_percent` and `container_memory_mb` isolate the searcher process. Should these be forwarded at all, or is host-level enough? Liveness could be a simple heartbeat instead.
2. **Rate window sizing**: 5m windows cover ~25 L1 blocks / ~150 L2 blocks. Go to 15m (~75 L1 / ~450 L2)?
