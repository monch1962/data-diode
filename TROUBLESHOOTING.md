# Data Diode Troubleshooting Guide

This guide is designed for field engineers to diagnose and solve issues with the `data_diode` application during deployment and maintenance.

## 🛠️ Quick Diagnostics

Run the automated health check script first:
```bash
./bin/diode_check.sh
```

## 🚩 Symptom: "The app is running, but no data is arriving at Service 2"

1. **Verify Interface Binding**:
   - Check if `LISTEN_IP` (S1) is reachable from the source device.
   - Run `ss -tulpn | grep 8080` (or your S1 port).
2. **Check the Encapsulator Gateway**:
   - Ensure the S1 side can "see" the S2 side over UDP.
   - Run `tcpdump -ni any port 42001` to see if UDP packets are leaving S1.
3. **Verify S2 UDP Listener**:
   - Check if S2 is bound to the correct `LISTEN_IP_S2`.
   - If S2 is only on `127.0.0.1`, ensure S1 is also sending to `127.0.0.1`.

## 🚩 Symptom: "App crashes immediately after starting"

1. **Port Conflicts**:
   - Check logs for `eaddrinuse`. Another process is using the port.
   - Run `sudo lsof -i :8080` to find the culprit.
2. **Environment Variable Mismatch**:
   - Ensure `LISTEN_PORT` and `LISTEN_PORT_S2` are valid numbers (1-65535).
   - Ensure `LISTEN_IP` is a valid IP address or `0.0.0.0`.

## 🚩 Symptom: "Performance is slow or data is being dropped"

1. **Payload Size**:
   - S1 limits payloads to 1MB. If the source sends more, S1 will drop it.
   - Check logs for: `S1: Dropping oversized packet`.
2. **CPU/Memory Exhaustion**:
   - Run `./bin/diode_status.sh` to check memory usage.
   - If memory is high, check if `S1.HandlerSupervisor` has too many active children.

4. **Protocol Guard (DPI)**:
   - S1 checks for specific OT protocol signatures if configured.
   - Check logs for: `S1: Protocol guard blocked packet`.
   - Verify `ALLOWED_PROTOCOLS` matches the source device traffic.

## 🚩 Symptom: "System clock jumps are causing issues"

1. **Monotonic Filenames**:
   - The app is designed to handle this. Files in S2 are named with monotonic integers: `data_<timestamp>_<unique_id>_<port>.dat`.
   - If you see file collisions, verify that the Pi is not running multiple instances writing to the same directory.

---
**Escalation**: If diagnostics fail, capture the output of `journalctl -u data_diode -n 100` and `bin/diode_status.sh` and send to the engineering team.
