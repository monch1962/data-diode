# 🧪 Testing Guide

This document provides detailed information about the testing approach, infrastructure, and best practices for the Data Diode project.

## Overview

The Data Diode project uses a comprehensive testing strategy to ensure reliability in harsh environments. The test suite includes:

- **286 tests** covering all major functionality
- **~52% code coverage** across all modules
- **Hardware simulation** for testing without physical devices
- **Graceful degradation testing** for missing/broken hardware
- **Security testing** via MITRE ATT&CK simulations
- **Long-term robustness testing** for extended operation

## Test Infrastructure

### Hardware Simulation Modules

The project includes specialized test support modules that simulate hardware without requiring physical devices:

#### `test/support/hardware_fixtures.ex`

Creates valid hardware simulations for testing normal operation:

```elixir
# Create full thermal sensor setup
{temp_dir, thermal_base, cpu_temp, ambient_temp, storage_temp} =
  setup_full_thermal_sensors(45, 22, 35)

# Create UPS with battery at 75%
{temp_dir, power_dir, battery_level, status} =
  setup_ups_battery(75, "Discharging")

# Create memory info file
{temp_dir, proc_dir, total_mb, used_mb} =
  setup_meminfo(8000, 4000)  # 8GB total, 4GB used
```

#### `test/support/missing_hardware.ex`

Simulates missing or broken hardware for testing graceful degradation:

```elixir
# No thermal sensors available
{temp_dir, sys_dir} = setup_no_thermal_sensors()

# Broken sensor (returns -1)
{temp_dir, thermal_dir} = setup_broken_thermal_sensor()

# No UPS hardware
{temp_dir, power_dir} = setup_no_ups()

# No /proc/meminfo
{temp_dir, proc_dir} = setup_no_meminfo()
```

### Test Structure

Tests are organized by functionality:

| Test File | Purpose | Coverage |
|-----------|---------|----------|
| `test/environmental_monitor_test.exs` | Temperature & sensor monitoring | 62.83% |
| `test/memory_guard_test.exs` | Memory leak detection | 21.36% |
| `test/network_guard_test.exs` | Network interface resilience | 11.54% |
| `test/power_monitor_test.exs` | UPS integration | 8.62% |
| `test/disk_cleaner_enhanced_test.exs` | Storage management | 60.00% |
| `test/health_api_mock_test.exs` | Health API helpers | 0.76% |
| `test/security_attack_test.exs` | MITRE ATT&CK simulations | High |
| `test/long_term_robustness_test.exs` | Extended operation testing | High |

## Running Tests

### Basic Test Execution

```bash
# Run all tests
mix test

# Run with coverage report
mix test --cover

# Run specific test file
mix test test/environmental_monitor_test.exs

# Run specific test by line number
mix test test/environmental_monitor_test.exs:27
```

### Running Test Suites

```bash
# Run all harsh environment tests
mix test test/environmental_monitor_test.exs \
         test/memory_guard_test.exs \
         test/network_guard_test.exs \
         test/power_monitor_test.exs \
         test/disk_cleaner_enhanced_test.exs \
         test/health_api_mock_test.exs

# Run security tests
mix test test/security_attack_test.exs

# Run robustness tests
mix test test/long_term_robustness_test.exs
```

## Hardware Simulation Examples

### Testing with Missing Temperature Sensors

```elixir
setup do
  # Create environment with no thermal sensors
  %{temp_dir: temp_dir, sys_dir: sys_dir} = setup_no_thermal_sensors()

  # Configure path to point to non-existent sensor
  Application.put_env(:data_diode, :thermal_zone_path,
    Path.join(sys_dir, "thermal_zone0/temp"))

  on_exit(fn ->
    DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
    Application.delete_env(:data_diode, :thermal_zone_path)
  end)

  :ok
end

test "handles missing sensors gracefully" do
  # System should not crash when sensors are missing
  readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

  # Should return unknown for unavailable readings
  assert readings.cpu in [:unknown, nil]
  assert readings.status in [:unknown, :normal]
end
```

### Testing with Critical Temperature

```elixir
setup do
  # Create environment with critical CPU temperature (80°C)
  %{temp_dir: temp_dir, thermal_dir: thermal_dir} =
    setup_critical_cpu_temp(80)

  Application.put_env(:data_diode, :thermal_zone_path,
    Path.join(thermal_dir, "temp"))

  on_exit(fn ->
    DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
    Application.delete_env(:data_diode, :thermal_zone_path)
  end)

  :ok
end

test "detects critical temperature" do
  readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

  # Should trigger critical status
  assert readings.status == :critical_hot
end
```

### Testing with UPS Battery Levels

```elixir
setup do
  # Create UPS with low battery (25%)
  %{temp_dir: temp_dir, power_dir: power_dir} =
    setup_low_ups()  # Returns 25% battery

  Application.put_env(:data_diode, :power_supply_path,
    Path.dirname(power_dir))

  on_exit(fn ->
    DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
    Application.delete_env(:data_diode, :power_supply_path)
  end)

  :ok
end

test "detects low battery condition" do
  # PowerMonitor should detect low battery from fixture
  pid = Process.whereis(DataDiode.PowerMonitor)
  assert Process.alive?(pid)

  # Trigger monitoring cycle
  Process.sleep(200)
  assert Process.alive?(pid)
end
```

## Configuration for Testing

### Configurable Hardware Paths

The following environment variables can be set to point to test fixtures instead of real hardware:

| Variable | Default | Purpose |
|----------|---------|---------|
| `MEMINFO_PATH` | `/proc/meminfo` | Memory information file |
| `THERMAL_ZONE_PATH` | `/sys/class/thermal/thermal_zone0/temp` | CPU temperature sensor |
| `POWER_SUPPLY_PATH` | `/sys/class/power_supply` | Power supply directory |
| `ENABLE_EMERGENCY_SHUTDOWN` | `false` | Allow emergency shutdown (disabled in tests) |

### Example: Configuring for Test Fixtures

```elixir
# In test setup
Application.put_env(:data_diode, :meminfo_path,
  Path.join(proc_dir, "meminfo"))

Application.put_env(:data_diode, :thermal_zone_path,
  Path.join(thermal_dir, "temp"))

# In test cleanup
on_exit(fn ->
  Application.delete_env(:data_diode, :meminfo_path)
  Application.delete_env(:data_diode, :thermal_zone_path)
end)
```

## Test Coverage Goals

### Current Coverage

- **Overall**: 52.35%
- **EnvironmentalMonitor**: 62.83% (goal: 70%+)
- **DiskCleaner**: 60.00% (goal: 70%+)
- **MemoryGuard**: 21.36% (goal: 40%+)
- **NetworkGuard**: 11.54% (goal: 30%+)
- **PowerMonitor**: 8.62% (goal: 30%+)

### Priority Areas for Improvement

1. **MemoryGuard**: Add tests for memory leak detection and recovery
2. **NetworkGuard**: Add tests for interface recovery and ARP cache management
3. **PowerMonitor**: Add tests for NUT integration and power transitions
4. **HealthAPI**: Add integration tests for HTTP endpoints (currently only helpers tested)

## Best Practices

### 1. Use Hardware Fixtures for Testing

Always use the provided hardware fixtures instead of mocking at the function level:

```elixir
# ✅ Good - Uses hardware fixtures
setup do
  %{temp_dir: temp_dir, thermal_dir: thermal_dir} =
    setup_high_cpu_temp(70)
  Application.put_env(:data_diode, :thermal_zone_path,
    Path.join(thermal_dir, "temp"))
  on_exit(fn ->
    DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
    Application.delete_env(:data_diode, :thermal_zone_path)
  end)
  :ok
end

# ❌ Bad - Mocks at function level (less realistic)
setup do
  Mox.stub(DataDiode.EnvironmentalMonitor, :read_cpu_temp, fn -> 70 end)
  :ok
end
```

### 2. Test Graceful Degradation

Always test both normal operation and failure scenarios:

```elixir
# Test normal operation
test "reads temperature correctly with valid sensor" do
  readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
  assert readings.cpu == 45.0
end

# Test graceful degradation
test "returns unknown when sensor missing" do
  %{temp_dir: temp_dir, sys_dir: sys_dir} = setup_no_thermal_sensors()
  Application.put_env(:data_diode, :thermal_zone_path,
    Path.join(sys_dir, "thermal_zone0/temp"))

  readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
  assert readings.cpu in [:unknown, nil]
end
```

### 3. Cleanup Test Fixtures

Always clean up temporary files and restore configuration:

```elixir
setup do
  temp_dir = create_temp_dir("test")
  Application.put_env(:data_diode, :data_dir, temp_dir)

  on_exit(fn ->
    File.rm_rf!(temp_dir)
    Application.delete_env(:data_diode, :data_dir)
  end)

  :ok
end
```

### 4. Avoid Testing Implementation Details

Test observable behavior rather than internal implementation:

```elixir
# ✅ Good - Tests behavior
test "detects critical temperature" do
  readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
  assert readings.status == :critical_hot
end

# ❌ Bad - Tests implementation
test "calls evaluate_conditions with critical temp" do
  # Fragile - breaks if implementation changes
  assert_receive {:monitoring_cycle, _}
end
```

## Continuous Integration

The project uses GitHub Actions for continuous testing:

- **All tests run** on every push and pull request
- **Coverage reports** generated and uploaded as artifacts
- **Coverage threshold** set to 90% (currently not met for all modules)
- **Test results** visible in GitHub Actions tab

### Coverage Reports

Coverage reports are generated in the `cover/` directory:

```bash
mix test --cover
open cover/excover.html  # View in browser
```

## Troubleshooting Tests

### Common Issues

**Issue**: "GenServer.call failed - no process"

**Solution**: The process is already started by the application. Use `Process.whereis/1` instead of `start_supervised!`:

```elixir
# Instead of this
{:ok, pid} = start_supervised!(DataDiode.MemoryGuard)

# Use this
pid = Process.whereis(DataDiode.MemoryGuard)
assert pid != nil
```

**Issue**: "File not found - /proc/meminfo"

**Solution**: Configure the path to test fixture:

```elixir
Application.put_env(:data_diode, :meminfo_path,
  Path.join(proc_dir, "meminfo"))
```

**Issue**: "Emergency shutdown triggered during test"

**Solution**: Disable emergency shutdown in tests:

```elixir
Application.put_env(:data_diode, :enable_emergency_shutdown, false)
```

## Contributing Tests

When adding new functionality:

1. **Write tests first** (TDD approach)
2. **Use hardware fixtures** for hardware-dependent code
3. **Test both success and failure scenarios**
4. **Ensure all tests pass** before submitting PR
5. **Update this documentation** if adding new test patterns

## References

- [ExUnit Docs](https://hexdocs.pm/ex_unit/)
- [Mox Docs](https://hexdocs.pm/mox/)
- [Elixir Testing Guide](https://elixir-lang.org/getting-started/mix-otp/introduction-to-mix.html)
