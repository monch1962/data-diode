defmodule DataDiode.HardwareFixtures do
  @moduledoc """
  Creates test fixtures that simulate valid hardware for testing.
  """

  # Simple temporary directory creation
  defp create_temp_dir(prefix) do
    temp_dir =
      Path.join([
        System.tmp_dir!(),
        "data_diode_test_#{prefix}_#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(temp_dir)
    temp_dir
  end

  @doc """
  Creates a complete sysfs thermal setup with CPU, ambient, and storage sensors.
  """
  def setup_full_thermal_sensors(cpu_temp \\ 45, ambient_temp \\ 22, storage_temp \\ 35) do
    temp_dir = create_temp_dir("full_thermal")
    thermal_base = Path.join([temp_dir, "sys/class/thermal"])

    # CPU sensor (thermal_zone0)
    cpu_zone = Path.join(thermal_base, "thermal_zone0")
    File.mkdir_p!(cpu_zone)
    File.write!(Path.join(cpu_zone, "temp"), "#{trunc(cpu_temp * 1000)}")
    File.write!(Path.join(cpu_zone, "type"), "cpu-0")

    # Ambient sensor (thermal_zone1)
    ambient_zone = Path.join(thermal_base, "thermal_zone1")
    File.mkdir_p!(ambient_zone)
    File.write!(Path.join(ambient_zone, "temp"), "#{trunc(ambient_temp * 1000)}")
    File.write!(Path.join(ambient_zone, "type"), "ambient-0")

    # Storage sensor (thermal_zone2)
    storage_zone = Path.join(thermal_base, "thermal_zone2")
    File.mkdir_p!(storage_zone)
    File.write!(Path.join(storage_zone, "temp"), "#{trunc(storage_temp * 1000)}")
    File.write!(Path.join(storage_zone, "type"), "storage-0")

    %{
      temp_dir: temp_dir,
      thermal_base: thermal_base,
      cpu_temp: cpu_temp,
      ambient_temp: ambient_temp,
      storage_temp: storage_temp
    }
  end

  @doc """
  Creates a UPS power_supply directory with battery status.
  """
  def setup_ups_battery(battery_level \\ 75, status \\ "Discharging") do
    temp_dir = create_temp_dir("ups_battery")
    power_dir = Path.join([temp_dir, "sys/class/power_supply/BAT0"])
    File.mkdir_p!(power_dir)

    File.write!(Path.join(power_dir, "capacity"), "#{battery_level}")
    File.write!(Path.join(power_dir, "status"), status)
    File.write!(Path.join(power_dir, "type"), "Battery")
    File.write!(Path.join(power_dir, "present"), "1")

    %{
      temp_dir: temp_dir,
      power_dir: power_dir,
      battery_level: battery_level,
      status: status
    }
  end

  @doc """
  Creates a UPS with critical battery level.
  """
  def setup_critical_ups do
    setup_ups_battery(8, "Discharging")
  end

  @doc """
  Creates a UPS with low battery level.
  """
  def setup_low_ups do
    setup_ups_battery(25, "Discharging")
  end

  @doc """
  Creates AC power (no battery).
  """
  def setup_ac_power do
    temp_dir = create_temp_dir("ac_power")
    power_dir = Path.join([temp_dir, "sys/class/power_supply/AC"])
    File.mkdir_p!(power_dir)

    File.write!(Path.join(power_dir, "online"), "1")
    File.write!(Path.join(power_dir, "type"), "Mains")

    %{temp_dir: temp_dir, power_dir: power_dir, online: true}
  end

  @doc """
  Cleans up fixtures.
  """
  def cleanup(%{temp_dir: temp_dir}) do
    File.rm_rf!(temp_dir)
  end

  @doc """
  Creates a file-based sensor for ambient temperature or humidity.
  """
  def setup_file_sensor(value) do
    temp_dir = create_temp_dir("file_sensor")
    sensor_file = Path.join(temp_dir, "sensor.txt")
    File.write!(sensor_file, value)

    %{
      temp_dir: temp_dir,
      sensor_file: sensor_file
    }
  end
end
