# Data Diode

This repository contains an Elixir application simulating a unidirectional data diode proxy. It is designed to demonstrate a secure network architecture where data flows from an unsecured network (Service 1) to a secure network (Service 2) without any possibility of a reverse connection.

The entire application runs under a single Elixir supervisor, but the design cleanly separates the network-facing components (S1) from the secure components (S2), mimicking deployment on two sides of a physical data diode.

## 🤔 Why not just use a firewall?

While firewalls are essential components of network security, a data diode offers a fundamentally different and stronger guarantee of unidirectional data flow, particularly in high-security environments.

**Firewall:**

* **Function:** A firewall acts as a gatekeeper, inspecting network traffic and enforcing rules to permit or deny communication based on IP addresses, ports, protocols, and sometimes application-layer content.
* **Bidirectional by Design:** Firewalls are inherently bidirectional. They can be configured to allow traffic in one direction, but their underlying architecture is capable of two-way communication. This means there's always a theoretical (and sometimes practical) risk of misconfiguration, vulnerabilities, or advanced attacks that could bypass the rules and establish a reverse channel.
* **Software-based:** Most firewalls are software-based, running on general-purpose computing platforms, making them susceptible to software bugs, exploits, and complex attack vectors.

**Data Diode (Unidirectional Gateway):**

* **Function:** A data diode is a hardware-enforced security device that physically prevents data from flowing in more than one direction. It typically uses optical technology or specialized electronics to ensure that a return path for data is impossible.
* **Physical Unidirectionality:** Its core strength lies in its physical design. There is no electrical or optical path for data to travel back, making it immune to misconfiguration or software vulnerabilities that could create a reverse channel.
* **Use Cases:** Data diodes are used in environments where absolute assurance of one-way data flow is critical, such as:
  * **Critical Infrastructure (SCADA/ICS):** Protecting operational technology networks from external threats while allowing monitoring data out.
  * **Military and Government:** Ensuring classified networks remain isolated from less secure networks.
  * **Nuclear Facilities:** Preventing control signals from leaving a secure zone while allowing sensor data to be extracted.
  * **Industrial Control Systems:** Isolating control networks from enterprise networks.

**In summary:** While a firewall attempts to *manage* bidirectional traffic, a data diode *physically enforces* unidirectional traffic. For scenarios demanding the highest level of assurance against reverse data flow, a data diode provides a security guarantee that a firewall cannot. This Elixir application simulates the logical separation and one-way data flow that a physical data diode provides.

## 🛑 Architecture Overview

The system is split into two logical services connected by a simulated network path (UDP):

**1. Service 1 (S1): Unsecured Network Ingress (TCP to UDP)**
The function of Service 1 is to accept connections from potentially untrusted clients (e.g., IoT devices, legacy systems) and forward the data securely.

* **Ingress:** Listens for incoming connections on a TCP socket (LISTEN_PORT).

* **Encapsulation:** When data is received, it extracts the original TCP source IP address (4 bytes) and Port (2 bytes). This metadata is prepended to the original payload, creating a custom packet header.

* **Egress:** Forwards the newly encapsulated binary packet across the simulated security boundary using a UDP socket to Service 2.

**2. Service 2 (S2): Secured Network Egress (UDP to Storage)**
The function of Service 2 is to safely receive data from the unsecured side, verify the format, and write the contents to the secure system.

* **Ingress:** Listens for encapsulated data on a UDP socket (LISTEN_PORT_S2).

* **Decapsulation:** Parses the custom 6-byte header to recover the original source IP and Port.

* **Processing:** Logs the metadata and simulates writing the original payload to secure storage. Crucially, S2 never opens any TCP connection and does not send any data back.
## 🛡️ Protocol Whitelisting & DPI
To prevent unauthorized command-and-control (C2) or data exfiltration, the Data Diode uses **Deep Packet Inspection (DPI)** to verify the contents of every packet against known industrial protocol signatures.

### Configuration
Use the `ALLOWED_PROTOCOLS` environment variable to define a comma-separated list of allowed protocols:

```bash
# Example: Allow only Modbus and MQTT
export ALLOWED_PROTOCOLS="MODBUS,MQTT"
```

### Supported Protocols
| Key | Protocol | Description |
| :--- | :--- | :--- |
| **MODBUS** | Modbus TCP | Industry standard for PLC communication. Checks for Protocol ID 0x0000. |
| **DNP3** | DNP3 | Standard for utilities/substations. Checks for start bytes `0x05 0x64`. |
| **MQTT** | MQTT | IoT messaging protocol. Validates common Control Packet types (1-14). |
| **ANY** | All Protocols | (Default) Allows any valid packet size through the diode. |

*Note: Packets that do not match the configured signatures are dropped at the ingress (S1) and recorded as errors in the metrics.*

## 🛠️ Project Setup

### Prerequisites

* Elixir (1.10+)

* Erlang/OTP (21+)

### Installation

Clone the repository:

```git clone [your-repo-link] data_diode```
```cd data_diode```

Install dependencies:

```mix deps.get```

## ⚙️ Configuration

The application is configured via environment variables. For OT deployments (e.g., Raspberry Pi), explicit interface binding is recommended.

| Variable | Purpose | Default | Example |
| -------- | ------- | ------- | ------- |
| `LISTEN_PORT` | S1 Ingress Port (TCP) | 8080 | 42000 |
| `LISTEN_IP` | S1 Interface Bind IP | `0.0.0.0` | `192.168.1.10` |
| `LISTEN_PORT_S2` | S2 Ingress Port (UDP) | 42001 | 42001 |
| `LISTEN_IP_S2` | S2 Interface Bind IP | `0.0.0.0` | `192.168.1.20` |

### OT Hardening & Stability
- **Race Condition Audit**: Underwent a comprehensive audit to eliminate concurrent race conditions and timing-based flakiness.
- **Task Exhaustion Safety**: S2 Listener now gracefully handles `TaskSupervisor` saturation with explicit error logging and metric increments.
- **SD Card Protection**: Logs are formatted as JSON via `:logger_json` to minimize metadata I/O.
- **Interface Binding**: Supports binding to specific industrial network interfaces to prevent cross-talk.
- **Clock Drift Immunity**: Filenames on the secure side (S2) use monotonic unique integers to prevent collisions during sudden NTP jumps.
- **Resilient Supervision**: The app uses a multi-layered supervisor tree. Service 1 handlers are `:temporary` to prevent supervisor saturation during network flapping.


## 🛡️ Security Posture & MITRE ATT&CK Analysis

This project implements specific defenses against common OT/ICS attack vectors, verified by the `test/security_attack_test.exs` suite.

| MITRE ATT&CK ID | Tactic | Technique | Defense Implemented | Verified By |
| :--- | :--- | :--- | :--- | :--- |
| **T1499.001** | Impact | Endpoint DoS (Service Exhaustion) | **Token Bucket Rate Limiter**:<br>Drops packets exceeding configured PPS limit (default 1000). | `MITRE T1499: DoS Flooding` |
| **T1499.002** | Impact | Endpoint DoS (App Exploitation) | **Fuzzing Resilience**:<br>Robust handling of oversized/garbage TCP/UDP packets. | `TCP Fuzzing` (NegativeTest) |
| **T1071** | C2 | Application Layer Protocol | **Protocol Guarding (DPI)**:<br>Configurable allow-list blocks unauthorized protocols (e.g. HTTP on Modbus port). | `MITRE T1071: Protocol Impersonation` |
| **T1565.002** | Impact | Data Manipulation (Transmitted) | **CRC32 Integrity Check**:<br>Packets with invalid checksums are dropped and logged. | `MITRE T1565: Data Manipulation` |
| **T1496** | Impact | Resource Hijacking (Disk Fill) | **Atomic Writes & Accounting**:<br>Graceful handling of ENOSPC (Disk Full) errors; random tokens prevent overwrite. | `Disk Full Resilience` (NegativeTest) |
| **T0837** | Impact | Loss of Availability (Thermal) | **Thermal Watchdog**:<br>Hardware watchdog stops pulsing if CPU temp > 80°C, forcing safety reboot. | `Thermal Cutoff` (NegativeTest) |

### Running Security Tests
To execute the security simulation suite:
```bash
mix test test/security_attack_test.exs
```

## 🚀 Remote Deployment (Raspberry Pi)

Instructions for technicians deploying in isolated OT networks:

1. **Build the Release**:
   ```bash
   MIX_ENV=prod mix release
   ```
2. **Transfer to Pi**: Copy the `_build/prod/rel/data_diode` directory to the target device.
3. **Environment Setup**: Create an `.env` file or export variables:
   ```bash
   export LISTEN_IP=10.0.0.5
   export LISTEN_PORT=80
   export LISTEN_IP_S2=127.0.0.1
   export LISTEN_PORT_S2=42001
   ```
4. **Start Service**:
   ```bash
   ./bin/data_diode start
   ```

## 🔋 Power Recovery & Persistence

In remote deployments, power cuts are a common occurrence. To ensure the Data Diode resumes operation automatically after power is restored to the Raspberry Pi:

### 1. Systemd Service Deployment
Technicians should use `systemd` to manage the application. This ensures the app starts on boot and restarts automatically if it ever exits.

A template is provided in [`deploy/data_diode.service.sample`](file:///Users/davidm/Projects/elixir-spike/data_diode/deploy/data_diode.service.sample). To use it:

1. Copy the sample file:
   ```bash
   sudo cp deploy/data_diode.service.sample /etc/systemd/system/data_diode.service
   ```
2. Edit the file to match the local network configuration:
   ```bash
   sudo nano /etc/systemd/system/data_diode.service
   ```
3. Enable and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable data_diode
   sudo systemctl start data_diode
   ```

### 2. Startup Resilience
The application is designed to be "cold-start" resilient:
- **Stateless Recovery**: S1 and S2 do not maintain long-term session state. Once the service is up, it is immediately ready to handle new packets.
- **Retry Logic**: If the OS takes time to release ports after a hard reboot, the Elixir supervisor will automatically retry binding (20 attempts every 5 seconds).
- **Network Dependency**: The `After=network.target` directive ensures the app waits for the network stack before attempting to bind listeners.

### 3. SD Card Protection
To prevent filesystem corruption during power loss, it is highly recommended to use the Raspberry Pi's "Overlay File System" (via `raspi-config`) to make the system partition read-only.

## 📡 Advanced Remote Support & Self-Healing

For mission-critical deployments where on-site access is limited, the application includes autonomous health management:

### 1. JSON Health Pulses (Telemetry)
The `DataDiode.SystemMonitor` emits a structured JSON log every 60 seconds (look for `HEALTH_PULSE` in logs). This includes:
- **Uptime**: Total seconds since service start.
- **Resource Usage**: CPU Temperature, Memory (MB), and Disk Free %.
- **Throughput**: Total packets forwarded and error counts.
*Tip: Remote monitoring platforms can alert on `cpu_temp > 80` or `disk_free_percent < 10`.*

### 2. End-to-End Channel Heartbeat
Service 1 automatically generates a "HEARTBEAT" packet every 5 minutes.
- **S1.Heartbeat**: Simulates a packet through the entire code path.
- **S2.HeartbeatMonitor**: Logs a `CRITICAL FAILURE` if a heartbeat is missed for more than 6 minutes.
*This verifies both services and the physical diode hardware.*

### 3. Autonomous Disk Maintenance
The `DataDiode.DiskCleaner` monitors storage hourly. If disk space falls below **15%**, it triggers an autonomous cleanup to prevent service interruption.

### 4. Hardware Watchdog (Pi Integration)
To recover from hard OS/VM hangs, enable the Raspberry Pi hardware watchdog:
1. Load the module: `sudo modprobe bcm2835_wdt`
2. Add `heart=on` to your environment variables or configure the `heart` daemon to pulse the watchdog.

## 🛠️ Troubleshooting for Remote Technicians

If the diode stops forwarding data, follow these steps:

### 1. Check Connectivity
Verify the listener is bound to the correct interface:
```bash
ss -tulpn | grep 42000  # S1 (TCP)
ss -tulpn | grep 42001  # S2 (UDP)
```

### 2. Inspect JSON Logs
Logs are located in `stdout` or the system journal. Look for `error` level events:
- `S1: Listener socket fatal error`: Usually means the port is already in use by another process.
- `S1: Failed to activate handler`: Local network congestion or socket ownership race.
- `S2: UDP Listener fatal error`: UDP socket closed by the OS/Kernel.

### 3. Supervisor Recovery
The system automatically attempts to restart crashed components up to 20 times every 5 seconds. If it exceeds this, the entire application will exit. Check for:
- `reached_max_restart_intensity`: Indicates a persistent hardware/OS failure (e.g., interface down).

### 4. Direct Node Inspection
If IEx is included in the release, you can attach to the running node:
```bash
./bin/data_diode remote
```
Run `DataDiode.S1.Listener.port()` to confirm the active port.

## ⚡ Performance Benchmarking
To establish operational baselines and verify scaling on industrial hardware, the project includes an automated load testing suite.

### Automated Load Test
The turn-key solution automates the "start -> test -> results -> stop" lifecycle:
```bash
# Usage: ./bin/run_load_test.sh <concurrency> <payload_bytes> <duration_ms>
./bin/run_load_test.sh 10 1024 10000
```
Detailed results, including packets per second and bandwidth throughput, are automatically captured into timestamped log files. See [`PERFORMANCE.md`](./PERFORMANCE.md) for deeper analysis.

## 🧪 Testing & Quality Assurance

### Test Coverage
The project maintains a high quality bar for unattended operation through an exhaustive test suite.
- **Current Coverage**: **~90%**
- **Robustness Suite**: Includes `test/long_term_robustness_test.exs` which simulates:
  - Disk-full scenarios.
  - Network interface flapping.
  - Large connection churn (Soak testing).
  - Clock jumps (NTP drift).

To run verification locally:
```bash
mix test --cover
```

## 🗃️ Key Files

| Filepath | Description |
| --- | --- |
| `lib/data_diode/application.ex` | Main Supervision Tree. |
| `lib/data_diode/s1/listener.ex` | S1 TCP Ingress (Passive mode for handover). |
| `lib/data_diode/s1/tcp_handler.ex` | S1 Stream Processing (Deferred activation). |
| `lib/data_diode/s2/listener.ex` | S2 UDP Ingress (Async Task spawning). |
| `lib/data_diode/s2/decapsulator.ex`| S2 Core logic & Secure Storage (Clock-drift safe). |
| `config/runtime.exs` | Environment variable binding. |
| `bin/automate_load_test.exs` | Automated load test script (lifecycle managed). |
| `bin/run_load_test.sh` | Shell wrapper for automated performance testing. |
| `OPERATIONS.md` | SOC Monitoring (SLIs, SLOs, SLAs). |
| `TROUBLESHOOTING.md` | Field Engineering Field Guide. |
| `PACKAGING.md` | Raspberry Pi Packaging Options (Nerves, .deb). |
| `HARDWARE.md` | Industrial Hardware Recommendations. |
| `PERFORMANCE.md` | Performance Benchmarking & Load Testing. |
