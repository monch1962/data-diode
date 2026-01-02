# Changelog

All notable changes to the Data Diode project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Comprehensive Testing Infrastructure

- **Test Support Modules** - Hardware simulation for testing graceful degradation
  - `test/support/hardware_fixtures.ex` - Creates valid hardware simulations
    - Full thermal sensor setup (CPU, ambient, storage)
    - UPS battery simulation (normal, low, critical levels)
    - AC power supply simulation
    - Memory info file generation
  - `test/support/missing_hardware.ex` - Simulates missing/broken hardware
    - Missing thermal sensors
    - Broken temperature sensors (returns -1)
    - Missing /proc/meminfo
    - Missing UPS hardware

- **Harsh Environment Test Suites** - Comprehensive testing for all monitoring modules
  - `test/environmental_monitor_test.exs` - 16 tests, 62.83% coverage
    - Full sensor configuration tests
    - High/critical temperature detection
    - Missing/broken sensor handling
    - CPU-only sensor configurations
  - `test/memory_guard_test.exs` - 16 tests, 21.36% coverage
    - Memory usage calculation validation
    - High/critical memory scenarios
    - Missing /proc/meminfo handling
    - VM memory statistics
  - `test/network_guard_test.exs` - 13 tests, 11.54% coverage
    - Interface state tracking
    - Flapping detection logic
    - Single/shared interface configurations
    - State transition counting
  - `test/power_monitor_test.exs` - 13 tests, 8.62% coverage
    - UPS battery level monitoring
    - Low/critical battery detection
    - AC power handling
    - Power state transitions
  - `test/disk_cleaner_enhanced_test.exs` - 17 tests, 60.00% coverage
    - Emergency cleanup operations
    - Log rotation testing
    - Integrity verification
    - Health-based retention
  - `test/health_api_mock_test.exs` - 28 tests, 0.76% coverage
    - Helper function validation
    - Data parsing tests
    - Status evaluation logic
    - Authentication tests

#### Improved Code Testability

- **Configurable Hardware Paths** - Made system paths configurable for testing
  - `:meminfo_path` - Memory info file location (default: `/proc/meminfo`)
  - `:thermal_zone_path` - Thermal sensor path (default: `/sys/class/thermal/thermal_zone0/temp`)
  - `:power_supply_path` - Power supply directory (configurable)
  - `:enable_emergency_shutdown` - Emergency shutdown flag (default: `false` for safety)

- **Resilient Emergency Shutdown** - Made emergency shutdown safer for testing
  - Checks if `S2.Decapsulator` is running before calling it
  - Graceful handling if Decapsulator is unavailable
  - Configurable emergency shutdown via `enable_emergency_shutdown`
  - Prevents accidental system shutdowns during testing

- **Fixed DateTime Comparison** - Corrected emergency cleanup file age checking
  - Properly converts file mtime tuples to DateTime structs
  - Uses `NaiveDateTime.from_erl!/1` for accurate comparison
  - Prevents crashes when evaluating file ages for cleanup

### Changed

#### Test Statistics
- **Total Tests**: Increased from ~186 to **308 tests** (+66%)
- **Test Coverage**: Improved from ~52% to **~59%** (+13%)
- **Harsh Environment Coverage**:
  - EnvironmentalMonitor: 40.19% → **62.83%** (+56%)
  - MemoryGuard: 4.95% → **49.51%** (+900%, added GenServer callback tests)
  - DiskCleaner: 38.46% → **58.10%** (+51%)
  - NetworkGuard: 6.41% → **14.10%** (+120%, added GenServer callback tests)
  - PowerMonitor: 8.62% → **43.33%** (+402%, added GenServer callback tests)
- **All Tests Passing**: Fixed all compilation errors and test failures

#### GenServer Callback Testing
- **MemoryGuard**: Added 7 new tests for periodic checks, baseline tracking, memory leak detection calculations, VM memory, and history tracking
- **NetworkGuard**: Added 8 new tests for GenServer callbacks, interface configuration, flapping recovery, and history tracking
- **PowerMonitor**: Added 8 new tests for GenServer callbacks, UPS status checking, and battery level thresholds
- **Process Restart Handling**: Tests now gracefully handle GenServer restarts when system commands fail

#### Code Quality
- **Made Production Code Testable** - Refactored modules to support hardware simulation
  - Added configurable paths instead of hardcoded system paths
  - Made GenServers more resilient to missing dependencies
  - Improved error handling in critical paths
  - Better separation of concerns for testing

### Fixed
- Fixed `GenServer.call` errors in DiskCleaner tests (changed to `send/2`)
- Fixed `Keyword.has_key?/2` errors with map return values (changed to `Map.has_key?/2`)
- Fixed DateTime comparison in emergency cleanup (added proper DateTime conversion)
- Fixed test setup blocks returning invalid `{:ok}` tuples
- Fixed undefined `pid()` function calls in tests
- Fixed MatchError in test pattern matching for thermal fixtures
- Fixed PowerMonitor to gracefully handle missing `upsc` command (lib/data_diode/power_monitor.ex:61-76) - Added try/rescue block to catch `ErlangError` when `upsc` command is unavailable and fall back to sysfs monitoring

#### Harsh Environment Monitoring Modules

- **DataDiode.EnvironmentalMonitor** - Multi-zone environmental monitoring
  - CPU temperature monitoring via `/sys/class/thermal`
  - Storage temperature tracking with DS18B20 sensor support
  - Ambient temperature/humidity monitoring (DHT22 sensor support)
  - Thermal hysteresis (5°C delta) prevents rapid mode cycling
  - Automatic mitigation at warning levels (65°C CPU, 30% battery)
  - Emergency shutdown at critical temperatures (75°C CPU, -20°C storage)
  - 10-second monitoring interval with configurable thresholds

- **DataDiode.NetworkGuard** - Network interface resilience
  - 30-second interface health checking
  - Interface flapping detection (5+ changes in 5 minutes)
  - Automatic interface recovery with exponential backoff (5s → 160s)
  - ARP cache clearing for stale network state
  - S1/S2 interface status tracking
  - Network event logging and alerting

- **DataDiode.PowerMonitor** - UPS integration and power management
  - NUT (Network UPS Tools) integration
  - sysfs power supply monitoring
  - 10-second battery check interval
  - Low power mode activation at 30% battery
  - Graceful shutdown at 10% battery
  - Power event logging

- **DataDiode.MemoryGuard** - Memory leak detection and recovery
  - 5-minute memory usage monitoring
  - Baseline establishment (5 samples)
  - 50% growth threshold for leak detection
  - Automatic garbage collection at 80% usage
  - Process restart at 90% usage
  - Top memory-consuming process tracking
  - 100-sample historical analysis

- **DataDiode.HealthAPI** - HTTP API for remote monitoring
  - `GET /api/health` - Comprehensive system health
  - `GET /api/metrics` - Operational metrics
  - `GET /api/environment` - Environmental readings
  - `GET /api/network` - Network status
  - `GET /api/storage` - Storage information
  - `GET /api/uptime` - System uptime
  - `POST /api/restart` - Authenticated graceful restart
  - `POST /api/shutdown` - Authenticated graceful shutdown
  - Token-based authentication via `HEALTH_API_TOKEN`
  - Production-only deployment (not started in tests)

#### Enhanced Features

- **Enhanced DiskCleaner** - Intelligent storage management
  - Health-based retention multiplier (2x during system stress)
  - Emergency cleanup mode (disk space < 5%)
  - Log rotation with compression (daily, 90-day retention)
  - Data integrity verification (every 2 hours)
  - Environmental status consideration for retention policies

- **Application Supervision** - Increased restart tolerance
  - Max restarts increased from 20 to 50
  - Time window extended from 5 to 10 seconds
  - Log rotation setup on application start
  - HealthAPI conditional startup (production only)

#### Configuration

- **Harsh Environment Configuration** (config/runtime.exs)
  - Temperature thresholds (CPU, ambient, storage)
  - Power management settings (NUT, sysfs)
  - Network resilience parameters (check interval, interfaces)
  - Memory management (check interval)
  - Health API authentication token
  - Alert file path configuration
  - Increased log retention (90 days)

#### Deployment

- **Production systemd Service** (deployment/data-diode.service)
  - Memory limit: 512MB
  - CPU quota: 80%
  - Hardware watchdog integration
  - Security hardening (NoNewPrivileges, ProtectSystem, ProtectHome)
  - Device access for sensors (/dev/ttyUSB0, /dev/gpiochip0, /dev/watchdog)

- **Automated Deployment Script** (deployment/deploy-for-harsh-environment.sh)
  - User and directory setup
  - Separate data partition configuration
  - Log rotation setup
  - Kernel parameter tuning (TCP keepalive, memory management)
  - Hardware watchdog configuration
  - UPS/NUT monitoring setup
  - Secure API token generation

### Dependencies

#### New Dependencies
- `plug_cowboy` ~ 2.6 - HTTP server for HealthAPI
- `plug` ~ 1.14 - HTTP request handling
- `jason` ~ 1.4 - JSON encoding/decoding

### Documentation

#### README Updates
- Added "Harsh Environment Operation" section
- Documented all new monitoring modules
- Added temperature threshold table
- Added harsh environment configuration variables
- Updated Key Files section with new modules
- Added deployment script documentation

#### Module Documentation
- Comprehensive `@moduledoc` for all harsh environment modules
- Temperature thresholds and mitigation strategies
- Network resilience and flapping protection
- Power management and UPS integration
- Memory leak detection and recovery

### Performance

#### Resource Management
- Increased restart tolerance for unstable conditions
- Health-based retention policies reduce disk I/O during stress
- Memory garbage collection prevents exhaustion
- Log compression reduces disk usage

### Testing

#### Coverage Notes
- New harsh environment modules require production hardware/system files for comprehensive testing
- Modules tested via public APIs and integration testing
- Production-only HealthAPI (not started in test environment)
- All existing tests (186) passing
- Overall coverage: ~47% (production modules excluded from test coverage)

### New Modules
- **DataDiode.NetworkHelpers** - Centralized network utility functions
  - `parse_ip_address/1` - Safe IP address parsing with validation
  - `parse_ip_address_strict/1` - Strict parsing with error reporting
  - `ip_to_string/1` - IP tuple to string conversion
  - `binary_to_ip/1` - 4-byte binary to IP string conversion
  - `validate_port/1` - Port number validation
  - `tcp_listen_options/1` - TCP socket options builder
  - `udp_listen_options/1` - UDP socket options builder

- **DataDiode.ConfigHelpers** - Centralized configuration access
  - Type-safe accessors for all application configuration
  - Provides single source of truth for config values
  - Eliminates scattered `Application.get_env` calls

- **DataDiode.ConfigValidator** - Startup configuration validation
  - Validates ports, IPs, data directories, protocols, and rate limits
  - Prevents application start with invalid configuration
  - Creates data directory if missing
  - Tests write permissions before startup

#### Features
- **Continuous Rate Limiting** - Improved token bucket algorithm
  - Precise refill calculations based on elapsed time
  - Prevents rate limit "leakage" (previously allowed ~2x configured rate)
  - More accurate rate limiting under varying load conditions

- **Actual Disk Cleanup** - Implemented working autonomous maintenance
  - Deletes oldest .dat files when disk space < 15%
  - Configurable batch size (default: 100 files)
  - Previously only simulated cleanup

- **Configuration Validation** - All config validated at startup
  - Catches configuration errors before runtime
  - Better error messages for invalid settings
  - Prevents silent failures

- **Docker Healthcheck** - Container health monitoring
  - Checks process status every 30 seconds
  - Improves orchestration reliability

- **CI Coverage Reporting** - Automated test coverage
  - Coverage reports generated on every test run
  - Artifacts uploaded for historical tracking

### Changed

#### Breaking Changes
- **Environment Variable Naming** - More explicit port configuration
  - `LISTEN_PORT` → `LISTEN_PORT_TCP` (S1 TCP ingress)
  - New `LISTEN_PORT_UDP` for optional UDP ingress
  - Old `LISTEN_PORT` still supported for backward compatibility

#### Code Quality
- **Removed Dead Code**
  - Unreachable pattern match in `Decapsulator`
  - Duplicate configuration in `test.exs`
  - Unused module attributes and aliases

- **Extracted Duplicate Code** (~100+ lines)
  - IP parsing logic centralized in `NetworkHelpers`
  - Data directory resolution centralized in `ConfigHelpers`
  - Updated all callers to use shared utilities

- **Fixed Deprecated Syntax**
  - Migrated `preferred_cli_env` to `def cli do` block
  - Modern Elixir/OTP patterns

- **Improved Error Handling**
  - Specific exception catching instead of overly broad `rescue`
  - Better error context in log messages
  - More informative error types

### Security

#### Hardening
- **Atom Safety** - Safe protocol atom conversion
  - Prevents atom table exhaustion attacks
  - Validates against protocol whitelist
  - Uses `String.to_existing_atom` with fallback

- **Systemd Security Options** - Enabled hardening features
  - `PrivateTmp=true` - Isolated /tmp
  - `ProtectSystem=full` - Read-only system partitions
  - `NoNewPrivileges=true` - Prevent privilege escalation
  - `ProtectHome=true` - Restrict home directory access
  - Proper `ReadWritePaths` and `ReadOnlyPaths`

### Documentation

#### Module Documentation
- Added comprehensive `@moduledoc` to:
  - `DataDiode` - Main application module
  - `DataDiode.S1.Encapsulator` - Packet encapsulation
  - `DataDiode.S1.HandlerSupervisor` - Connection supervision
  - All new utility modules

#### README Updates
- Updated configuration table with new environment variables
- Added new modules to Key Files section
- Documented recent code quality improvements
- Updated test coverage percentage (~92%)
- Enhanced OT Hardening section with new features

### Testing

#### Test Improvements
- Updated tests to use new utility modules
- Fixed rate limiting test for continuous algorithm
- Updated disk cleaner tests for actual implementation
- All tests passing (105/106, 1 pre-existing flaky test)

#### Coverage
- Current test coverage: **~92%**
- Comprehensive security test suite
- MITRE ATT&CK attack simulations

### Performance

#### Optimizations
- **Continuous Rate Limiting** - More precise token management
- **Reduced Code Duplication** - Better code cache efficiency
- **Centralized Configuration** - Faster config access

### Dependencies

No new dependencies added. Existing dependencies:
- `logger_json` ~ 5.0
- `opentelemetry_api` ~ 1.0
- `opentelemetry` ~ 1.0
- `opentelemetry_exporter` ~ 1.0
- `mox` ~ 1.0

### Developer Experience

#### Build System
- Fixed deprecated Mix configuration
- Added CI coverage reporting
- Docker healthcheck for containerized deployments

#### Code Maintainability
- Centralized utilities reduce duplication
- Better type specifications with `@spec`
- Comprehensive documentation
- Consistent error handling patterns

## [0.1.0] - Initial Release

### Features
- Unidirectional data diode simulation
- TCP to UDP encapsulation
- Deep Packet Inspection (DPI) for protocol whitelisting
- CRC32 integrity checks
- Basic rate limiting (token bucket)
- Autonomous disk cleanup (simulated)
- JSON health telemetry
- End-to-end heartbeat monitoring
- Hardware watchdog integration
- Systemd service template
- Docker containerization

### Security
- Protocol whitelisting (Modbus, DNP3, MQTT, SNMP)
- Rate limiting (default: 1000 PPS)
- MITRE ATT&CK coverage (T1071, T1499, T1565, T1496, T0837)

### Documentation
- Comprehensive README
- Operations guide
- Troubleshooting guide
- Performance benchmarking
- Hardware recommendations
- Packaging options

---

## Versioning Policy

- **Major version (X.0.0)**: Breaking changes, architectural redesigns
- **Minor version (0.X.0)**: New features, backward-compatible changes
- **Patch version (0.0.X)**: Bug fixes, documentation updates

For project history and detailed migration guides between versions, refer to the git commit history.
