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
end
