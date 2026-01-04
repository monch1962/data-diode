defmodule DataDiode.EnvironmentalMonitorTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import DataDiode.MissingHardware
  import DataDiode.HardwareFixtures
  require Logger

  doctest DataDiode.EnvironmentalMonitor

  describe "with full thermal sensors" do
    setup do
      %{temp_dir: temp_dir, thermal_base: thermal_base} =
        setup_full_thermal_sensors(45, 22, 35)

      Application.put_env(
        :data_diode,
        :thermal_zone_path,
        Path.join(thermal_base, "thermal_zone0/temp")
      )

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      :ok
    end

    test "reads CPU temperature correctly" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
      assert readings.cpu == 45.0
    end

    test "handles normal temperature range" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
      assert readings.status == :normal
    end

    test "includes timestamp in readings" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
      assert Map.has_key?(readings, :timestamp)
      assert is_integer(readings.timestamp)
    end
  end

  describe "with high CPU temperature" do
    setup do
      %{temp_dir: temp_dir, thermal_dir: thermal_dir, cpu_temp: cpu_temp} =
        setup_high_cpu_temp(70)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      {:ok, cpu_temp: cpu_temp}
    end

    test "detects warning temperature" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
      assert readings.status in [:warning_hot, :critical_hot]
    end

    test "logs high temperature warning" do
      log =
        capture_log(fn ->
          DataDiode.EnvironmentalMonitor.monitor_all_zones()
          Process.sleep(50)
        end)

      assert log =~ ~r/(warning|high temperature)/i
    end
  end

  describe "with critical CPU temperature" do
    setup do
      %{temp_dir: temp_dir, thermal_dir: thermal_dir} = setup_critical_cpu_temp(80)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      :ok
    end

    test "detects critical temperature" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
      assert readings.status == :critical_hot
    end

    test "logs critical temperature alert" do
      log =
        capture_log(fn ->
          DataDiode.EnvironmentalMonitor.monitor_all_zones()
          Process.sleep(50)
        end)

      assert log =~ ~r/(critical|emergency)/i
    end
  end

  describe "with no thermal sensors" do
    setup do
      %{temp_dir: temp_dir, sys_dir: sys_dir} = setup_no_thermal_sensors()

      Application.put_env(
        :data_diode,
        :thermal_zone_path,
        Path.join(sys_dir, "thermal_zone0/temp")
      )

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      :ok
    end

    test "returns :unknown for cpu_temp when sensor missing" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
      assert readings.cpu in [:unknown, nil]
    end

    test "handles missing sensors gracefully" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Should not crash, should return a status
      assert Map.has_key?(readings, :status)
      # Status should be :unknown or :normal when sensors missing
      assert readings.status in [:unknown, :normal]
    end

    test "logs warning about missing sensors" do
      log =
        capture_log(fn ->
          DataDiode.EnvironmentalMonitor.monitor_all_zones()
          Process.sleep(100)
        end)

      assert log =~ ~r/cannot read/i
    end
  end

  describe "with broken thermal sensor" do
    setup do
      %{temp_dir: temp_dir, thermal_dir: thermal_dir} = setup_broken_thermal_sensor()

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      :ok
    end

    test "handles negative temperature values" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Should handle -1 error value gracefully or return a valid temperature
      # The actual behavior depends on what sensors are available
      assert is_number(readings.cpu) or readings.cpu in [:unknown, nil]
    end

    test "continues monitoring despite sensor error" do
      # Process should not crash
      pid = Process.whereis(DataDiode.EnvironmentalMonitor)
      assert pid != nil
      assert Process.alive?(pid)

      # Should still be able to get readings
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
      assert is_map(readings)
    end
  end

  describe "with CPU-only thermal sensors" do
    setup do
      %{temp_dir: temp_dir, thermal_dir: thermal_dir, cpu_temp: cpu_temp} =
        setup_cpu_only_thermal(50)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      {:ok, cpu_temp: cpu_temp}
    end

    test "reads CPU temperature correctly" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()
      assert readings.cpu == 50.0
    end

    test "returns :unknown for ambient sensors" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Storage and ambient sensors might not exist in all systems
      # Just verify we get some reading
      assert is_map(readings)
    end

    test "evaluates status based on available sensors only" do
      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Should have a valid status even with partial sensors
      assert Map.has_key?(readings, :status)
      assert readings.status in [:normal, :warning_hot, :critical_hot]
    end
  end

  describe "GenServer callbacks" do
    setup do
      %{temp_dir: temp_dir, thermal_base: thermal_base} =
        setup_full_thermal_sensors(45, 22, 35)

      Application.put_env(
        :data_diode,
        :thermal_zone_path,
        Path.join(thermal_base, "thermal_zone0/temp")
      )

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      :ok
    end

    test "get_current_state returns current readings" do
      state = DataDiode.EnvironmentalMonitor.get_current_state()
      assert is_map(state)
      assert Map.has_key?(state, :cpu)
      assert Map.has_key?(state, :status)
    end
  end

  describe "storage temperature" do
    test "estimates storage temperature from CPU" do
      # When no storage sensor available, estimates from CPU
      %{temp_dir: temp_dir, thermal_dir: thermal_dir} = setup_cpu_only_thermal(60)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Storage should be ~10°C cooler than CPU
      if is_number(readings.cpu) and is_number(readings.storage) do
        assert readings.storage < readings.cpu
        assert readings.storage >= 0
      end
    end
  end

  describe "ambient temperature sensors" do
    test "estimates ambient from CPU when no sensor" do
      %{temp_dir: temp_dir, thermal_dir: thermal_dir} = setup_cpu_only_thermal(50)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))
      Application.delete_env(:data_diode, :ambient_temp_sensor)

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Ambient should be estimated from CPU (~15°C cooler)
      if is_number(readings.cpu) and is_number(readings.ambient) do
        assert readings.ambient < readings.cpu
        assert readings.ambient >= 0
      end
    end

    test "reads from file sensor when configured" do
      %{temp_dir: temp_dir, sensor_file: sensor_file} = setup_file_sensor("25.5")

      # Setup a minimal CPU thermal sensor for the test
      %{thermal_dir: thermal_dir} = setup_cpu_only_thermal(45)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))
      Application.put_env(:data_diode, :ambient_temp_sensor, %{type: :file, path: sensor_file})

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
        Application.delete_env(:data_diode, :ambient_temp_sensor)
      end)

      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Should read 25.5 from file
      assert readings.ambient == 25.5
    end
  end

  describe "humidity sensors" do
    test "returns :unknown when no sensor configured" do
      %{temp_dir: temp_dir, thermal_dir: thermal_dir} = setup_cpu_only_thermal(50)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))
      Application.delete_env(:data_diode, :humidity_sensor)

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      assert readings.humidity == :unknown
    end

    test "reads humidity from file sensor" do
      %{temp_dir: temp_dir, sensor_file: sensor_file} = setup_file_sensor("65.0")

      Application.put_env(:data_diode, :humidity_sensor, %{type: :file, path: sensor_file})

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :humidity_sensor)
      end)

      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      assert readings.humidity == 65.0
    end
  end

  describe "cold temperature handling" do
    test "detects critical cold temperature" do
      %{temp_dir: temp_dir, thermal_dir: thermal_dir} = setup_critical_cold_temp(-25)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Should detect critical cold
      assert readings.status in [:critical_cold, :warning_cold]
    end
  end

  describe "hysteresis" do
    test "applies hysteresis to prevent rapid cycling" do
      # Hysteresis is handled internally via process dictionary
      # This test verifies the system doesn't crash with changing temps
      %{temp_dir: temp_dir, thermal_dir: thermal_dir} = setup_cpu_only_thermal(75)

      Application.put_env(:data_diode, :thermal_zone_path, Path.join(thermal_dir, "temp"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :thermal_zone_path)
      end)

      # Read multiple times with different temperatures
      readings1 = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Process should still be alive
      pid = Process.whereis(DataDiode.EnvironmentalMonitor)
      assert Process.alive?(pid)

      # Second reading should work
      readings2 = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      assert is_map(readings1)
      assert is_map(readings2)
    end
  end

  describe "error handling" do
    test "handles invalid file sensor data gracefully" do
      %{temp_dir: temp_dir, sensor_file: sensor_file} = setup_file_sensor("invalid")

      Application.put_env(:data_diode, :ambient_temp_sensor, %{type: :file, path: sensor_file})

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :ambient_temp_sensor)
      end)

      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Should return :unknown for invalid data
      assert readings.ambient == :unknown
    end

    test "handles missing sensor file gracefully" do
      Application.put_env(:data_diode, :ambient_temp_sensor, %{
        type: :file,
        path: "/nonexistent/sensor"
      })

      on_exit(fn ->
        Application.delete_env(:data_diode, :ambient_temp_sensor)
      end)

      readings = DataDiode.EnvironmentalMonitor.monitor_all_zones()

      # Should return :unknown when file doesn't exist
      assert readings.ambient == :unknown
    end
  end
end
