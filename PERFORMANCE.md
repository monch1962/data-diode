# ⚡ Performance Benchmarking Guide

This document outlines how to measure and optimize the performance of the `data_diode` application.

## 📊 Key Performance Metrics

| Metric | Goal | Measurement Tool |
| :--- | :--- | :--- |
| **Throughput (PPS)** | Max Packets Per Second without drops. | `bin/diode_load_test.exs` |
| **Bandwidth (Mbps)** | Max sustained data flow (e.g., for file transfers). | `bin/diode_load_test.exs` |
| **E2E Latency** | Time from S1 Ingress to S2 Storage. | Logs / OpenTelemetry |
| **Concurrency Ceiling** | Max simultaneous TCP connections. | `bin/diode_load_test.exs` |

## 🧪 Running Benchmarks

### 1. Simple Load Testing

Use the built-in Elixir load generator to test throughput with different payload sizes and concurrency levels.

```bash
# Example: 50 concurrent clients, 4KB payloads, for 30 seconds
LISTEN_IP=127.0.0.1 LISTEN_PORT=8080 \\
elixir bin/diode_load_test.exs 50 4096 30000
```

### 2. Monitoring Under Load

While running the load test, monitor system health in a separate terminal:

```bash
./bin/diode_status.sh
```

Watch the **Error Count** and **Packet Count** to identify the saturation point.

## 🚀 Scaling & Optimization

### BEAM Tuning

The application runs on the Erlang VM (BEAM), which is highly scalable. For high-throughput requirements:

- **Scheduler Tuning**: Use `+S` beam flags if deploying on multi-core hardware.
- **Port Limits**: Increase `ERL_MAX_PORTS` if handling > 1000 concurrent sockets.

### Hardware Bottlenecks

- **CPU**: Encapsulation/Decapsulation is relatively lightweight, but JSON logging can become a bottleneck at > 10k packets/sec.
- **Network**: UDP buffer sizes in the Linux kernel may need tuning (`sysctl net.core.rmem_max`) to prevent drops at ultra-high speeds.

## 🏁 Expected Benchmarks (Pi 4 Reference)

- **Small Packets (64B)**: ~5,000 - 8,000 PPS.
- **Large Packets (1MB)**: Near-wire speed (wired ethernet).
- **Concurrency**: Up to 100 simultaneous connections (limited by current app config).

---
**Recommendation**: For production, always benchmark on the actual target hardware (e.g., RevPi vs standard Pi) to establish your local baseline.
