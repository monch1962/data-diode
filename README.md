# Data Diode

This repository contains an Elixir application simulating a unidirectional data diode proxy. It is designed to demonstrate a secure network architecture where data flows from an unsecured network (Service 1) to a secure network (Service 2) without any possibility of a reverse connection.

The entire application runs under a single Elixir supervisor, but the design cleanly separates the network-facing components (S1) from the secure components (S2), mimicking deployment on two sides of a physical data diode.

## 🤔 Why not just use a firewall?

While firewalls are essential components of network security, a data diode offers a fundamentally different and stronger guarantee of unidirectional data flow, particularly in high-security environments.

**Firewall:**

- **Function:** A firewall acts as a gatekeeper, inspecting network traffic and enforcing rules to permit or deny communication based on IP addresses, ports, protocols, and sometimes application-layer content.
- **Bidirectional by Design:** Firewalls are inherently bidirectional. They can be configured to allow traffic in one direction, but their underlying architecture is capable of two-way communication. This means there's always a theoretical (and sometimes practical) risk of misconfiguration, vulnerabilities, or advanced attacks that could bypass the rules and establish a reverse channel.
- **Software-based:** Most firewalls are software-based, running on general-purpose computing platforms, making them susceptible to software bugs, exploits, and complex attack vectors.

**Data Diode (Unidirectional Gateway):**

- **Function:** A data diode is a hardware-enforced security device that physically prevents data from flowing in more than one direction. It typically uses optical technology or specialized electronics to ensure that a return path for data is impossible.
- **Physical Unidirectionality:** Its core strength lies in its physical design. There is no electrical or optical path for data to travel back, making it immune to misconfiguration or software vulnerabilities that could create a reverse channel.
- **Use Cases:** Data diodes are used in environments where absolute assurance of one-way data flow is critical, such as:
  - **Critical Infrastructure (SCADA/ICS):** Protecting operational technology networks from external threats while allowing monitoring data out.
  - **Military and Government:** Ensuring classified networks remain isolated from less secure networks.
  - **Nuclear Facilities:** Preventing control signals from leaving a secure zone while allowing sensor data to be extracted.
  - **Industrial Control Systems:** Isolating control networks from enterprise networks.

**In summary:** While a firewall attempts to *manage* bidirectional traffic, a data diode *physically enforces* unidirectional traffic. For scenarios demanding the highest level of assurance against reverse data flow, a data diode provides a security guarantee that a firewall cannot. This Elixir application simulates the logical separation and one-way data flow that a physical data diode provides.

## 🛑 Architecture Overview

The system is split into two logical services connected by a simulated network path (UDP):

**1. Service 1 (S1): Unsecured Network Ingress (TCP to UDP)**
The function of Service 1 is to accept connections from potentially untrusted clients (e.g., IoT devices, legacy systems) and forward the data securely.

- **Ingress:** Listens for incoming connections on a TCP socket (LISTEN_PORT).
- **Encapsulation:** When data is received, it extracts the original TCP source IP address (4 bytes) and Port (2 bytes). This metadata is prepended to the original payload, creating a custom packet header.
- **Egress:** Forwards the newly encapsulated binary packet across the simulated security boundary using a UDP socket to Service 2.

**2. Service 2 (S2): Secured Network Egress (UDP to Storage)**

The function of Service 2 is to safely receive data from the unsecured side, verify the format, and write the contents to the secure system.

- **Ingress:** Listens for encapsulated data on a UDP socket (LISTEN_PORT_S2).
- **Decapsulation:** Parses the custom 6-byte header to recover the original source IP and Port.
- **Processing:** Logs the metadata and simulates writing the original payload to secure storage. Crucially, S2 never opens any TCP connection and does not send any data back.

## 🛡️ Protocol Whitelisting & DPI
To prevent unauthorized command-and-control (C2) or data exfiltration, the Data Diode uses **Deep Packet Inspection (DPI)** to verify the contents of every packet against known industrial protocol signatures.

### Configuration
Use the `ALLOWED_PROTOCOLS` environment variable to define a comma-separated list of allowed protocols:

```bash
# Example: Allow only Modbus and MQTT
export ALLOWED_PROTOCOLS="MODBUS,MQTT"
```

### Supported Protocols
| Key | Protocol | Primary Transport | Standard Port | Description |
| :--- | :--- | :--- | :--- | :--- |
| **MODBUS** | Modbus TCP | TCP | 502 | Industry standard for PLC communication. |
| **DNP3** | DNP3 | TCP/UDP | 20000 | Standard for utilities and substations. |
| **MQTT** | MQTT | TCP | 1883 / 8883 | IoT messaging protocol (DPI checks Control Types). |
| **SNMP** | SNMP | UDP | 161 / 162 | Network management (Checks ASN.1 BER Sequence). |
| **ANY** | All Protocols | - | - | (Default) Allows any valid packet through. |

> **NOTE:** Transport Ingress Note - The current `S1.Listener` is configured for **TCP Ingress**. While the DPI logic supports UDP-based protocols (SNMP, DNP3-UDP), they would require the deployment of a corresponding UDP Ingress listener at Service 1.

**Note:** Packets that do not match the configured signatures are dropped at the ingress (S1) and recorded as errors in the metrics.

## 🛠️ Project Setup

### Prerequisites

- Elixir (1.10+)
- Erlang/OTP (21+)

### Installation

Clone the repository:

```bash
git clone [your-repo-link] data_diode
cd data_diode
```

Install dependencies:

```bash
mix deps.get
```

## ⚙️ Configuration

The application is configured via environment variables. For OT deployments (e.g., Raspberry Pi), explicit interface binding is recommended.

| Variable | Purpose | Default | Example |
| -------- | ------- | ------- | ------- |
| `LISTEN_PORT_TCP` | S1 TCP Ingress Port | 8080 | 502 (Modbus) |
| `LISTEN_PORT_UDP` | S1 UDP Ingress Port (Optional) | `nil` | 161 (SNMP) |
| `LISTEN_IP` | S1 Interface Bind IP | `0.0.0.0` | `192.168.1.10` |
| `LISTEN_PORT_S2` | S2 Ingress Port (UDP) | 42001 | 42001 |
| `LISTEN_IP_S2` | S2 Interface Bind IP | `0.0.0.0` | `192.168.1.20` |
| `DATA_DIR` | S2 Data Storage Directory | `.` | `/var/lib/data_diode` |
| `ALLOWED_PROTOCOLS` | Protocol Whitelist | `ANY` | `MODBUS,MQTT` |
| `MAX_PACKETS_PER_SEC` | Rate Limit | 1000 | 500 |
| `DISK_CLEANUP_BATCH_SIZE` | Files to Delete Per Cleanup | 100 | 50 |

### Harsh Environment Configuration
Additional environment variables for harsh environment monitoring:

| Variable | Purpose | Default |
|----------|---------|---------|
| `MEMINFO_PATH` | Memory info file path | `/proc/meminfo` |
| `THERMAL_ZONE_PATH` | Thermal sensor path | `/sys/class/thermal/thermal_zone0/temp` |
| `POWER_SUPPLY_PATH` | Power supply directory | `/sys/class/power_supply` |
| `ENABLE_EMERGENCY_SHUTDOWN` | Allow emergency shutdown | `false` (for safety) |
| `HEALTH_API_TOKEN` | API authentication token | (generate with openssl) |
| `S1_INTERFACE` | S1 network interface name | `eth0` |
| `S2_INTERFACE` | S2 network interface name | `eth1` |

### OT Hardening & Stability
- **Configuration Validation**: All configuration is validated at application startup to prevent runtime failures with invalid settings.
- **Centralized Utilities**: Shared `NetworkHelpers` and `ConfigHelpers` modules eliminate code duplication and provide consistent configuration access.
- **Continuous Rate Limiting**: Improved token bucket algorithm with precise refill calculations prevents rate limit "leakage" (previously allowed ~2x configured rate).
- **Actual Disk Cleanup**: Implemented working autonomous disk cleanup that deletes oldest .dat files when space is low (previously simulated).
- **Atom Safety**: Safe protocol atom conversion prevents atom table exhaustion attacks.
- **Systemd Hardening**: Enabled security hardening options in systemd service template (PrivateTmp, ProtectSystem, NoNewPrivileges, etc.).
- **Docker Healthcheck**: Added container health monitoring for improved orchestration reliability.
- **CI Coverage Reporting**: Automated test coverage reporting with artifact uploads.
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
   export LISTEN_PORT_TCP=502     # Map incoming Modbus to S1 (TCP)
   export LISTEN_PORT_UDP=161     # Map incoming SNMP to S1 (UDP)
   export LISTEN_IP_S2=127.0.0.1
   export LISTEN_PORT_S2=42001    # Internal diode link (UDP)
   ```
4. **Start Service**:
   ```bash
   ./bin/data_diode start
   ```

## 🔋 Power Recovery & Persistence

In remote deployments, power cuts are a common occurrence. To ensure the Data Diode resumes operation automatically after power is restored to the Raspberry Pi:

### 1. Systemd Service Deployment
Technicians should use `systemd` to manage the application. This ensures the app starts on boot and restarts automatically if it ever exits.

A template is provided in [`deploy/data_diode.service.sample`](deploy/data_diode.service.sample). To use it:

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
- **Stateless Recovery**: S1 and S2 do not maintain long-term session state. Once the service is up, it is immediately ready to handle new packets
- **Retry Logic**: If the OS takes time to release ports after a hard reboot, the Elixir supervisor will automatically retry binding (20 attempts every 5 seconds)
- **Network Dependency**: The `After=network.target` directive ensures the app waits for the network stack before attempting to bind listeners

### 3. SD Card Protection
To prevent filesystem corruption during power loss, it is highly recommended to use the Raspberry Pi's "Overlay File System" (via `raspi-config`) to make the system partition read-only.

## 🌡️ Harsh Environment Operation

For deployments in extreme or inaccessible environments (remote field sites, industrial plants, outdoor enclosures), the data diode includes comprehensive autonomous monitoring and self-healing capabilities:

### Environmental Monitoring
The `DataDiode.EnvironmentalMonitor` module continuously tracks thermal conditions:
- **Multi-Zone Temperature Monitoring**: CPU, storage, and ambient temperature tracking
- **Humidity Sensing**: Support for DHT22 and DS18B20 environmental sensors
- **Thermal Hysteresis**: 5°C delta prevents rapid cooling/heating cycling
- **Automatic Mitigation**: Activates protective modes at warning levels (65°C CPU, 30% battery)
- **Emergency Shutdown**: Prevents hardware damage at critical temperatures (75°C CPU, -20°C storage)

### Network Resilience
The `DataDiode.NetworkGuard` module ensures network reliability in unstable conditions:
- **Interface Flapping Detection**: Identifies rapid state changes (5+ transitions in 5 minutes)
- **Automatic Recovery**: Attempts interface restart with exponential backoff (5s → 160s)
- **ARP Cache Management**: Clears stale ARP entries to restore connectivity
- **Status Monitoring**: Tracks S1/S2 interface health every 30 seconds

### Power Management
The `DataDiode.PowerMonitor` module provides UPS integration for power stability:
- **UPS Monitoring**: Supports NUT (Network UPS Tools) and sysfs power supply monitoring
- **Graceful Shutdown**: Automatic safe shutdown at 10% battery
- **Low Power Mode**: Activates at 30% battery to extend runtime
- **Power Event Logging**: Records all power transitions for analysis

### Memory Protection
The `DataDiode.MemoryGuard` module prevents memory exhaustion in long-running systems:
- **Memory Leak Detection**: Tracks baseline and alerts on 50% growth
- **Automatic Garbage Collection**: Triggers at 80% memory usage
- **Recovery Actions**: Restarts non-critical processes at 90% usage
- **Historical Analysis**: Maintains 100-sample memory history for trend detection

### Enhanced Storage Management
The `DataDiode.DiskCleaner` module provides intelligent storage management:
- **Health-Based Retention**: Doubles data retention during system stress (2x multiplier)
- **Emergency Cleanup**: Immediate action when disk space < 5%
- **Log Rotation**: Automatic daily rotation with 90-day retention
- **Integrity Verification**: Periodic data integrity checks every 2 hours

### Remote Monitoring API
The `DataDiode.HealthAPI` module provides HTTP endpoints for remote monitoring (production only):
- **Health Status**: `GET /api/health` - Comprehensive system health
- **Metrics**: `GET /api/metrics` - Operational metrics and throughput
- **Environment**: `GET /api/environment` - Temperature and sensor readings
- **Network**: `GET /api/network` - Interface status and connection counts
- **Storage**: `GET /api/storage` - Disk usage and file statistics
- **Control**: `POST /api/restart` or `/api/shutdown` - Authenticated remote control

**Authentication**: Requires `HEALTH_API_TOKEN` environment variable for control endpoints.

### Deployment Script
A comprehensive deployment script is provided for harsh environment setups:
```bash
./deployment/deploy-for-harsh-environment.sh
```

This script configures:
- Separate data partition on `/data`
- Log rotation with compression
- Kernel parameter tuning (TCP keepalive, memory management)
- Hardware watchdog setup
- UPS/NUT monitoring configuration
- Secure API token generation

### Temperature Thresholds
| Condition | CPU Temp | Ambient Temp | Action |
|-----------|----------|--------------|--------|
| Normal | < 65°C | 5-70°C | None |
| Warning Hot | > 65°C | > 70°C | Activate cooling mode |
| Warning Cold | N/A | < 5°C | Activate heating mode |
| Critical Hot | > 75°C | N/A | Emergency shutdown |
| Critical Cold | N/A | < -20°C | Emergency shutdown |

### Harsh Environment Configuration
Additional environment variables for harsh environments:

| Variable | Purpose | Default |
|----------|---------|---------|
| `DATA_DIR` | Data storage path | `.` |
| `HEALTH_API_TOKEN` | API authentication token | (generate with openssl) |
| `S1_INTERFACE` | S1 network interface name | `eth0` |
| `S2_INTERFACE` | S2 network interface name | `eth1` |
| `ALERT_FILE` | Alert event log path | `/var/log/data-diode/alerts.log` |

## 📡 Advanced Remote Support & Self-Healing

For mission-critical deployments where on-site access is limited, the application includes autonomous health management:

### 1. JSON Health Pulses (Telemetry)
The `DataDiode.SystemMonitor` emits a structured JSON log every 60 seconds (look for `HEALTH_PULSE` in logs). This includes:
- **Uptime**: Total seconds since service start
- **Resource Usage**: CPU Temperature, Memory (MB), and Disk Free %
- **Throughput**: Total packets forwarded and error counts

**Tip:** Remote monitoring platforms can alert on `cpu_temp > 80` or `disk_free_percent < 10`.

### 2. End-to-End Channel Heartbeat
Service 1 automatically generates a "HEARTBEAT" packet every 5 minutes.

- **S1.Heartbeat**: Simulates a packet through the entire code path
- **S2.HeartbeatMonitor**: Logs a `CRITICAL FAILURE` if a heartbeat is missed for more than 6 minutes

**Note:** This verifies both services and the physical diode hardware.

### 3. Autonomous Disk Maintenance
The `DataDiode.DiskCleaner` monitors storage hourly. If disk space falls below **15%**, it automatically deletes the oldest .dat files (configurable batch size) to prevent service interruption.

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
- **Current Coverage**: **~59%** (308 passing tests)
- **Robustness Suite**: Includes `test/long_term_robustness_test.exs` which simulates:
  - Disk-full scenarios.
  - Network interface flapping.
  - Large connection churn (Soak testing).
  - Clock jumps (NTP drift).
- **Security Suite**: Comprehensive MITRE ATT&CK attack simulation in `test/security_attack_test.exs`.
- **Property Tests**: Verification of protocol parsing, rate limiting, and data integrity.
- **Harsh Environment Tests**: Comprehensive testing for environmental monitoring, power management, and network resilience.
- **GenServer Callback Tests**: Full coverage of periodic checks, state management, and error recovery.

To run verification locally:
```bash
mix test --cover
```

### Harsh Environment Testing
The project includes specialized test infrastructure for validating graceful degradation when hardware is unavailable:

**Test Support Modules**:
- `test/support/hardware_fixtures.ex` - Creates simulated hardware (thermal sensors, UPS, memory, network interfaces)
- `test/support/missing_hardware.ex` - Simulates missing or broken hardware for testing graceful degradation

**Test Coverage by Module**:
| Module | Coverage | Tests |
|--------|----------|-------|
| EnvironmentalMonitor | 62.83% | Temperature sensors, critical conditions, missing sensors |
| MemoryGuard | 49.51% | Memory monitoring, leak detection, baseline tracking, GenServer callbacks |
| DiskCleaner | 58.10% | Emergency cleanup, log rotation, integrity checks |
| NetworkGuard | 14.10% | Interface flapping, recovery, configuration variations, GenServer callbacks |
| PowerMonitor | 43.33% | UPS monitoring, battery levels, AC power, GenServer callbacks |
| HealthAPI | 0.76% | Helper functions, data parsing (API tested in integration) |

**Testing Capabilities**:
- Simulates temperature sensors (CPU, ambient, storage) in `/sys/class/thermal`
- Mocks UPS battery levels and power supply status
- Creates fake `/proc/meminfo` for memory testing
- Tests network interface monitoring without physical interfaces
- Validates graceful degradation when sensors are missing or broken

### Running Harsh Environment Tests
To run tests for specific harsh environment modules:

```bash
# Test all harsh environment modules
mix test test/environmental_monitor_test.exs test/memory_guard_test.exs \
         test/network_guard_test.exs test/power_monitor_test.exs \
         test/disk_cleaner_enhanced_test.exs test/health_api_mock_test.exs

# Test specific modules
mix test test/environmental_monitor_test.exs
mix test test/memory_guard_test.exs

# Run with coverage for harsh environment modules
mix test test/environmental_monitor_test.exs test/memory_guard_test.exs \
         test/network_guard_test.exs test/power_monitor_test.exs \
         test/disk_cleaner_enhanced_test.exs --cover
```

### Testing Graceful Degradation
The test infrastructure allows you to verify that the system behaves correctly when hardware is unavailable:

```bash
# Tests simulate missing sensors and verify the system continues operating
mix test test/environmental_monitor_test.exs

# Tests verify proper error handling and logging
mix test test/memory_guard_test.exs

# Tests confirm network resilience without physical interfaces
mix test test/network_guard_test.exs
```

### Code Quality Improvements
Recent codebase improvements include:
- Removed all unreachable dead code and duplicate configurations
- Fixed deprecated Mix configuration syntax
- Extracted 100+ lines of duplicate code into shared utilities
- Added comprehensive @moduledoc, @spec, and @doc annotations
- Eliminated overly broad exception handling
- Implemented actual functionality (not simulation) where needed
- Fixed PowerMonitor to gracefully handle missing `upsc` command (lib/data_diode/power_monitor.ex:61-76)
- Added comprehensive GenServer callback testing for harsh environment modules
- Added static analysis tools (Dialyzer, Credo) for type checking and code quality

## 🛠️ Development Tools

The project includes several tools to maintain code quality and catch bugs early:

### Static Analysis

#### Dialyzer (Type Checking)
Dialyzer performs static analysis of Elixir code to find type discrepancies and bugs.

```bash
# Build PLT (Persistent Lookup Table) - first time only
mix dialyzer --plt

# Run type checking
mix dialyzer

# Run with format suitable for CI
mix dialyzer --format short
```

**What it catches:**
- Type mismatches in function calls
- Pattern matching errors
- Race conditions
- Unused functions

#### Credo (Code Quality)
Credo is a static code analysis tool that checks code style and design consistency.

```bash
# Run all checks
mix credo

# Run with strict mode (fails on warnings)
mix credo --strict

# Show suggestions in a readable format
mix credo --format oneline

# Generate HTML report
mix credo --format html
```

**What it checks:**
- Code complexity (cyclomatic complexity, nesting depth)
- Code readability (line length, naming conventions)
- Design issues (code duplication, module design)
- Consistency violations

### Pre-commit Hooks

The project includes automated pre-commit hooks to ensure code quality before commits:

```bash
# Install pre-commit hooks (already installed if you ran setup)
./bin/install_hooks

# The hooks run automatically on git commit and check:
# - Code formatting (mix format)
# - Code quality (mix credo)
# - Quick test suite (mix test --max-failures=3)

# To skip hooks for a single commit:
git commit --no-verify
```

### Property-Based Testing

The project includes property-based tests that verify invariants across many randomly generated inputs:

```bash
# Run property-based tests
mix test test/property_test.exs

# These tests use StreamData to generate random inputs and verify:
# - IP address format validation
# - Port validation
# - Memory percentage calculations
# - CRC32 checksum properties
```

### Development Workflow

Recommended workflow for contributing:

1. **Make your changes**
   ```bash
   # Edit code
   ```

2. **Format code**
   ```bash
   mix format
   ```

3. **Run static analysis**
   ```bash
   mix credo --strict
   mix dialyzer
   ```

4. **Run tests**
   ```bash
   mix test                    # Run all tests
   mix test --cover            # With coverage report
   mix test --max-failures=1   # Stop at first failure
   ```

5. **Commit**
   ```bash
   git add .
   git commit -m "Description of changes"
   # Pre-commit hooks will run automatically
   ```

## 🗃️ Key Files

### Core Modules

| Filepath | Description |
| --- | --- |
| `lib/data_diode/application.ex` | Main Supervision Tree with startup validation |
| `lib/data_diode/network_helpers.ex` | Shared network utility functions (IP parsing, validation) |
| `lib/data_diode/config_helpers.ex` | Centralized configuration access |
| `lib/data_diode/config_validator.ex` | Startup configuration validation |
| `lib/data_diode/s1/listener.ex` | S1 TCP Ingress (Passive mode for handover) |
| `lib/data_diode/s1/tcp_handler.ex` | S1 Stream Processing (Deferred activation) |
| `lib/data_diode/s1/encapsulator.ex` | Packet encapsulation with continuous rate limiting |
| `lib/data_diode/s1/udp_listener.ex` | S1 UDP Ingress (Optional SNMP/DNP3 support) |
| `lib/data_diode/s2/listener.ex` | S2 UDP Ingress (Async Task spawning) |
| `lib/data_diode/s2/decapsulator.ex`| S2 Core logic & Secure Storage (Clock-drift safe) |
| `lib/data_diode/disk_cleaner.ex` | Autonomous disk maintenance (actual file deletion) |

### Harsh Environment Modules

| Filepath | Description |
| --- | --- |
| `lib/data_diode/environmental_monitor.ex` | Multi-zone temperature & humidity monitoring |
| `lib/data_diode/network_guard.ex` | Network interface flapping detection & recovery |
| `lib/data_diode/power_monitor.ex` | UPS integration & graceful power management |
| `lib/data_diode/memory_guard.ex` | Memory leak detection & recovery |
| `lib/data_diode/health_api.ex` | HTTP API for remote monitoring and control |
| `lib/data_diode/system_monitor.ex` | System health telemetry and metrics |
| `lib/data_diode/watchdog.ex` | Hardware watchdog management |

### Configuration & Operations

| Filepath | Description |
| --- | --- |
| `config/runtime.exs` | Environment variable binding with safe atom conversion |
| `.github/workflows/elixir.yml` | CI pipeline with coverage reporting |
| `Dockerfile` | Container build with healthcheck |
| `deploy/data_diode.service.sample` | Systemd service template with security hardening |
| `deployment/data-diode.service` | Production systemd service with resource limits |
| `deployment/deploy-for-harsh-environment.sh` | Automated deployment script for harsh environments |

### Test Infrastructure

| Filepath | Description |
| --- | --- |
| `test/support/hardware_fixtures.ex` | Creates simulated hardware for testing |
| `test/support/missing_hardware.ex` | Simulates missing/broken hardware |
| `test/environmental_monitor_test.exs` | Temperature and sensor testing |
| `test/memory_guard_test.exs` | Memory monitoring and leak detection |
| `test/network_guard_test.exs` | Network resilience testing |
| `test/power_monitor_test.exs` | UPS and power management testing |
| `test/disk_cleaner_enhanced_test.exs` | Storage management testing |
| `test/health_api_mock_test.exs` | HealthAPI helper function testing |

### Documentation

| Filepath | Description |
| --- | --- |
| `TESTING.md` | Comprehensive testing guide and infrastructure documentation |
| `bin/automate_load_test.exs` | Automated load test script (lifecycle managed) |
| `bin/run_load_test.sh` | Shell wrapper for automated performance testing |
| `OPERATIONS.md` | SOC Monitoring (SLIs, SLOs, SLAs) |
| `TROUBLESHOOTING.md` | Field Engineering Field Guide |
| `PACKAGING.md` | Raspberry Pi Packaging Options (Nerves, .deb) |
| `HARDWARE.md` | Industrial Hardware Recommendations |
| `PERFORMANCE.md` | Performance Benchmarking & Load Testing |
