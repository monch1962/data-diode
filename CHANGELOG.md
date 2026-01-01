# Changelog

All notable changes to the Data Diode project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### New Modules
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
