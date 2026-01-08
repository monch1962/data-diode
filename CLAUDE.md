# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Data Diode** implementation in Elixir - a unidirectional data transfer system that physically prevents reverse data flow. The architecture mimics a hardware data diode by logically separating ingress (Service 1 - untrusted) from egress (Service 2 - secure) connected only via UDP.

**Core Security Model**: S1 accepts TCP/UDP connections, encapsulates packets with source metadata, and forwards via UDP to S2. S2 never sends data back, only writes to storage.

## Development Commands

### Building & Dependencies

```bash
mix deps.get          # Install dependencies
mix compile           # Compile the project
mix format            # Format code (run before commits)
mix format --check-formatted  # Check if code is formatted
```

### Testing

```bash
mix test              # Run all tests (495 tests, ~35-40 seconds)
mix test test/specific_test.exs           # Run single test file
mix test test/specific_test.exs:42         # Run specific test at line 42
mix test --trace                            # Run with verbose output

# Run specific test suites by tag
mix test --only chaos      # Chaos engineering tests (120s timeout)
mix test --only concurrent  # Concurrent state tests (60s timeout)
mix test --only shutdown    # Graceful shutdown tests (60s timeout)
mix test --only property    # Property-based tests

# Coverage
mix test --cover          # Run tests with coverage report (85%+ coverage)
mix test --cover --cover-html  # Generate HTML coverage report in cover/
```

### Linting & Static Analysis

```bash
mix credo              # Run code quality checks (see .credo.exs for config)
mix credo --strict     # Run with strict rules
mix dialyzer           # Run dialyzer for type analysis (requires PLT build first)
mix dialyzer --plt     # Build/update PLT for dialyzer
```

### Documentation

```bash
npx markdownlint-cli "*.md" "docs/*.md"           # Check Markdown files
npx markdownlint-cli "*.md" "docs/*.md" --fix     # Auto-fix Markdown issues
```

### Docker & Deployment

```bash
docker build -t data_diode:latest .              # Build Docker image
docker run --env-file config/docker.env -p 4000:4000 data_diode:latest
mix release           # Build production release (requires rebar3)
```

## Architecture Overview

### Data Flow

```text
External Clients (TCP/UDP)
    ↓
Service 1 (S1) - Untrusted Side
├── S1.Listener (TCP) / S1.UDPListener (UDP)
├── S1.HandlerSupervisor (DynamicSupervisor) - spawns TCPHandler per connection
├── S1.Encapsulator - encapsulates with source IP/port + CRC32
└── S1.Heartbeat - sends keepalive packets
    ↓ (UDP packets with metadata)
Service 2 (S2) - Secure Side
├── S2.Listener (UDP)
├── S2.Decapsulator - validates CRC32, extracts metadata
├── S2.TaskSupervisor (max 200 children) - async file writes
└── S2.HeartbeatMonitor - monitors S1 health
    ↓
Secure Storage (atomic writes with monotonic filenames)
```

### Key Design Patterns

**Circuit Breaker Pattern** (`lib/data_diode/circuit_breaker.ex`)

- State machine: `closed → open → half_open → closed`
- Registry-based process management for dynamic circuit breakers
- Used to protect S1 from S2 failures/network partitions
- Call via `DataDiode.CircuitBreaker.call(:name, fun)` - returns `{:ok, result}` or `{:error, :circuit_open}`

**Token Bucket Rate Limiting** (`lib/data_diode/connection_rate_limiter.ex`, `lib/data_diode/rate_limiter.ex`)

- Global: 10 conn/sec with 100 burst capacity (ConnectionRateLimiter)
- Per-IP: 100 packets/sec per source IP (RateLimiter with ETS)
- GenServer-based with continuous token refill every 1000ms
- Returns `:allow` or `{:deny, reason}`

### Supervision Strategy

- One-for-one supervision with harsh environment tolerance
- `max_restarts: 50` (increased from 20) in 10 seconds
- TCPHandler processes are `:temporary` (not restarted) to prevent supervisor saturation

### Protocol Whitelisting (DPI)

Deep Packet Inspection in `S1.Encapsulator` validates packets against protocol signatures:

- `:modbus` - Modbus TCP (Protocol ID = 0x0000)
- `:dnp3` - DNP3 (starts with 0x0564)
- `:mqtt` - MQTT (Control Packet 0x1X-0xEX)
- `:snmp` - SNMP (ASN.1 BER SEQUENCE)
- `:any` - Allows all protocols (default)

**Configuration**: `export ALLOWED_PROTOCOLS="MODBUS,MQTT"`

**Implementation**: `DataDiode.ProtocolDefinitions.matches?(:modbus, payload)`

### Critical Modules & Their Responsibilities

**Encapsulation** (`lib/data_diode/s1/encapsulator.ex`)

- Extracts source IP (4 bytes) + port (2 bytes) from TCP connection
- Calculates CRC32 checksum over: `<<ip_bin::4, port::2, payload::binary>>`
- Sends via UDP with retry logic (exponential backoff: 10ms → 80ms)
- Rate limiting: per-IP (100 pps) and global (1000 pps default)

**Decapsulation** (`lib/data_diode/s2/decapsulator.ex`)

- Receives UDP packets, validates CRC32
- Extracts source IP/port from header
- Writes to storage using atomic writes + monotonic unique integers (NTP-jump safe)
- Implements `flush_buffers/0` for graceful shutdown (calls `sync` command)

**Environmental Monitoring** (`lib/data_diode/environmental_monitor.ex`)

- GenServer-based (refactored from process dictionary anti-pattern)
- Multi-zone thermal monitoring (CPU, GPU, storage, ambient)
- Thermal hysteresis (5°C delta) to prevent rapid cycling
- Thresholds: CPU 85°C critical, Storage 60°C critical
- Activates throttling/shutdown modes based on state

**Network Guard** (`lib/data_diode/network_guard.ex`)

- Monitors network interface status (S1: eth0, S2: eth1)
- Detects flapping: 6 state changes in 300 seconds
- Uses `ip` command for interface checks (falls back gracefully on macOS)
- Activates flapping protection with 300-second penalty period

### Configuration Management

**Environment Variables** (see README.md for full list)

- `LISTEN_PORT_TCP` / `LISTEN_PORT_UDP` - S1 ingress ports
- `LISTEN_IP_S2` / `LISTEN_PORT_S2` - S2 bind config
- `DATA_DIR` - S2 storage directory
- `ALLOWED_PROTOCOLS` - Comma-separated protocol whitelist
- `MAX_PACKETS_PER_SEC` - Global rate limit (default: 1000)
- `S1_INTERFACE` / `S2_INTERFACE` - Network interface names
- `ENABLE_EMERGENCY_SHUTDOWN` - Allow thermal shutdown (default: false, safety)

**Config Validation** (`lib/data_diode/config_validator.ex`)

- Validates all configuration at application startup
- Prevents runtime failures from invalid settings
- Use `DataDiode.ConfigValidator.validate!/0` to check config

### Testing Strategy

**Test Organization** (39 test files, 495 tests total)

- `chaos_engineering_test.exs` - Process crashes, cascading failures
- `concurrent_state_test.exs` - Race conditions, state consistency
- `graceful_shutdown_test.exs` - Buffer flush, socket cleanup
- `property_test.exs` - Property-based testing with StreamData
- `long_term_robustness_test.exs` - 24-hour soak tests
- `nerves_compatibility_test.exs` - OTP/Nerves compatibility

**Test Tags** (for selective execution)

- `@moduletag :chaos` - Chaos engineering (120s timeout)
- `@moduletag :concurrent` - Concurrent state (60s timeout)
- `@moduletag :shutdown` - Graceful shutdown (60s timeout)
- `@moduletag :property` - Property-based tests
- `@moduletag :test` - Standard tests (default)

### Important Testing Patterns

```elixir
# For tests that modify Application environment
on_exit(fn -> Application.delete_env(:data_diode, :key) end)

# For tests involving process termination
use GenServer, restart: :temporary  # Don't restart crashed test processes

# For concurrent testing
tasks = for i <- 1..100 do
  Task.async(fn ->
    DataDiode.SomeModule.call(i)
  end)
end
Task.await_many(tasks, 5000)

# For GenServer state testing
state = :sys.get_state(pid)
:sys.replace_state(pid, fn _ -> new_state end)
```

## Code Style & Conventions

### Elixir Conventions

- Use `@moduledoc` for module documentation
- Use `@doc` for public function documentation
- Use `@spec` for type specs (especially in public APIs)
- Pattern matching preferred over `cond`/`case` for simple conditions
- Use `when` guards for function clauses

### GenServer Patterns

```elixir
# Use @impl true for callback annotations
@impl true
def handle_call(:request, _from, state) do
  {:reply, :ok, state}
end

# Use terminate/2 for cleanup (not after_ callbacks)
@impl true
def terminate(_reason, %{socket: socket}) do
  :gen_udp.close(socket)
  :ok
end
```

### Error Handling

- Never use `try/rescue` in hot paths (use Supervision tree instead)
- Use `{:ok, result}` / `{:error, reason}` tuples for public APIs
- Log errors at appropriate level: `Logger.debug/1`, `Logger.info/1`, `Logger.warning/1`, `Logger.error/1`
- For expected failures (rate limits, bad input): log at `:warning` or `:debug`
- For unexpected failures: log at `:error`

### Process Management

- Use Registry for dynamic process discovery (CircuitBreakerRegistry pattern)
- Use `Process.whereis/1` to check if process exists (returns pid or `nil`)
- For GenServer calls from async contexts, add timeout and error handling
- Never call GenServer from within `handle_cast` (causes deadlocks)

### Testing Anti-Patterns to Avoid

- Don't use `Process.sleep` to synchronize concurrent tests (use proper synchronization)
- Don't rely on `Application.ensure_all_started` in test setup - check if already started
- Don't leave state in Application environment - use `on_exit` to cleanup
- Don't use process dictionary for state storage - use GenServer state instead

## Deployment Targets

### Nerves / Raspberry Pi

- Target deployment: `mix release` (not `mix firmware`)
- Uses systemd service file: `deploy/data_diode.service.sample`
- Environment variables set in systemd unit or `/etc/default/data_diode`
- Log rotation configured for SD card protection (`logger_json`)
- Health API on port 4000 in production only

### Docker

- Multi-stage Dockerfile included
- Exposes health endpoint on port 4000
- Volume mount for data persistence
- Environment file: `config/docker.env`

### systemd Hardening

The systemd service includes security hardening:

- `PrivateTmp=true` - Isolated /tmp
- `ProtectSystem=full` - Read-only system paths
- `NoNewPrivileges=true` - Prevent privilege escalation
- `ReadWritePaths=/var/lib/data_diode` - Only data dir writable

## Performance Considerations

### UDP Packet Handling

- Default MTU is 1500 bytes, large packets are dropped with `:emsgsize`
- Encapsulator limits packet size to 1MB (`@max_packet_size`)
- CRC32 calculation on every packet (fast, Erlang built-in)

### Rate Limiting

- Connection rate limiting prevents DoS on accept loop
- Per-IP rate limiting prevents single-source floods
- Token bucket refill: `tokens = min(limit, tokens + elapsed_ms * limit / 1000)`

### Concurrent Processing

- S2.TaskSupervisor limited to 200 concurrent file operations
- TCP handlers are `:temporary` (not restarted) to prevent supervisor thrashing
- Use `Task.Supervisor.async_nolink/4` for fire-and-forget operations

## Troubleshooting

### Common Issues

1. **"Process not alive or there's no process currently associated"**
   - CircuitBreaker not started: use `CircuitBreaker.ensure_started(:name)`
   - Race condition in tests: add `Process.sleep(50)` after process start

2. **"attempted to call itself"**
   - GenServer calling itself via `GenServer.call/3`
   - Fix: Access state directly in `handle_call` instead of making call

3. **UDP packets not received in tests**
   - Socket closed too early: use `:active: :once` for controlled message flow
   - Port mismatch: Check `Application.get_env(:data_diode, :s2_port)`

4. **Test order dependencies**
   - Tests leaving state in Application environment
   - Fix: Use `on_exit` callbacks to restore environment
   - Tests killing supervised processes
   - Fix: Use `Process.whereis` and handle already-started processes

### Debugging Tips

```elixir
# View GenServer state
:sys.get_state(pid)

# View all processes for a module
Registry.select(DataDiode.SomeRegistry, [{:_, :_, :_}])

# Trace GenServer messages
:sys.trace(pid, true)

# Get process info
Process.info(pid, :message_queue_len)
Process.info(pid, :dictionary)
```

## Reliability Features

### Circuit Breaker Integration

When adding new UDP send operations, wrap them in circuit breaker:

```elixir
case DataDiode.CircuitBreaker.call(:udp_send, fn ->
  :gen_udp.send(socket, host, port, packet)
end) do
  {:ok, _} -> :ok
  {:error, :circuit_open} -> {:error, :circuit_open}
end
```

### Graceful Shutdown Requirements

All modules writing to storage must implement `flush_buffers/0`:

- Flush pending writes
- Call `System.cmd("sync", [])` for filesystem persistence
- Called by `Application.stop/1` before termination

### Retry Pattern

For transient failures (UDP sends), use exponential backoff:

```elixir
defp send_with_retry(socket, dest_port, packet, retries \\ 3) do
  case :gen_udp.send(socket, @target, dest_port, packet) do
    :ok -> :ok
    {:error, :eagain} when retries > 0 ->
      Process.sleep(calculate_backoff(retries))
      send_with_retry(socket, dest_port, packet, retries - 1)
    {:error, reason} -> {:error, reason}
  end
end
```
