# Operational Monitoring Guide (SLIs, SLOs, SLAs)

This document defines the Service Level Indicators (SLIs), Objectives (SLOs), and Agreements (SLAs) for the `data_diode` application, designed for Security Operations Centre (SOC) and Site Reliability Engineering (SRE) teams.

## 📊 Service Level Indicators (SLIs)

These metrics provide real-time visibility into the health of the unidirectional data flow.

| SLI Name | Definition | Metric Source |
| :--- | :--- | :--- |
| **Ingress Availability** | % of time the S1 TCP Listener is bound and accepting connections. | `bin/diode_check.sh` / Logs |
| **Path Integrity** | Time since the last validated end-to-end `HEARTBEAT` packet in S2. | `HEALTH_PULSE` Logs |
| **Packet Throughput** | Count of successfully decapsulated packets in S2 per minute. | `bin/diode_status.sh` |
| **Resource Headroom** | Available Disk Space (%) and CPU Temperature (°C). | `HEALTH_PULSE` Logs |
| **Handler Saturation** | Number of active S1 TCP handlers vs. maximum limit (100). | `DataDiode.Metrics` |

## 🎯 Service Level Objectives (SLOs)

Target performance levels for stable, unintended operation.

| Objective | Target Level | Measurement Interval |
| :--- | :--- | :--- |
| **System Uptime** | > 99.9% | Monthly |
| **Heartbeat Continuity** | < 1 missed heartbeat (> 6 min gap) | Daily |
| **Storage Availability** | > 15% Free Disk Space | Continuous |
| **Thermal Stability** | CPU Temp < 80°C | Continuous |
| **Data Integrity** | Zero software-induced packet drops | Per 1k packets |

## 🤝 Service Level Agreements (SLAs)

Recommended response commitments for support teams.

1. **Critical Failure (Missed Heartbeat)**:
   - SOC Alerting: Immediate.
   - Engineering Triage: Within 2 hours.
   - Field Dispatch: Within 4 hours (if remote).
2. **Resource Warning (Low Disk/High Temp)**:
   - Triage: Within 12 hours.
   - Resolution: Within 48 hours (e.g., manual cleanup or thermal mitigation).

## 🚨 Alerting Recommendations for SOC

SOC teams should configure alerts on the `HEALTH_PULSE` JSON logs:

- **CRITICAL**: `heartbeat_missed == true` (End-to-end path broken).
- **WARNING**: `disk_free_percent < 20` (Nearing autonomous cleanup threshold).
- **WARNING**: `cpu_temp > 75` (Potential hardware cooling failure).
- **INFO**: `error_count > 5` (Potential network flapping or malformed ingress).

## 🛡️ Protocol Configuration & Security

To harden the system against malicious traffic, the `data_diode` includes a Deep Packet Inspection (DPI) protocol guard.

### Configuring Whitelists

Technicians can lock the diode to specific industrial protocols via the `ALLOWED_PROTOCOLS` environment variable in the `data_diode.service` file:

- **Strict Mode**: `ALLOWED_PROTOCOLS="MODBUS"` (Only Modbus TCP allowed).
- **Multi-Protocol Mode**: `ALLOWED_PROTOCOLS="DNP3,MQTT"` (Allows both DNP3 and MQTT).
- **Open Mode**: `ALLOWED_PROTOCOLS="ANY"` (Allows all traffic with valid diode headers).

### Protocol Transport Matrix

| Protocol | Transport | Port |
| :--- | :--- | :--- |
| **Modbus TCP** | TCP | 502 |
| **DNP3** | TCP/UDP | 20000 |
| **MQTT** | TCP | 1883 / 8883 |
| **SNMP** | UDP | 161 / 162 |

### SOC Monitoring of Protocol Violations

When a protocol violation occurs (e.g., someone attempts to send HTTP through a Modbus-only diode):

1. The packet is **dropped immediately** on the S1 side.
2. A `warning` is emitted in the logs: `S1 Encapsulator: Protocol guard blocked packet from 1.2.3.4`.
3. The `error_count` metric is incremented.

**SOC Action**: Persistent protocol violations from a single IP should trigger an investigation into the source device for potential compromise or misconfiguration.

---
**Maintenance**: Review these metrics quarterly to adjust thresholds based on actual site performance.
