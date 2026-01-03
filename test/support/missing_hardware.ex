defmodule DataDiode.MissingHardware do
  @moduledoc """
  Creates test environments with missing or incomplete hardware.
  This tests graceful degradation when sensors are unavailable.
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

  def create!(opts) do
    prefix = Keyword.get(opts, :prefix, "temp")
    temp_dir = create_temp_dir(prefix)
    %{temp_dir: temp_dir}
  end

  @doc """
  Creates a minimal sysfs tree with NO temperature sensors.
  This is common on VMs and SBCs without thermal sensors.
  """
  def setup_no_thermal_sensors do
    temp_dir = create_temp_dir("no_thermal")
    sys_dir = Path.join(temp_dir, "sys/class/thermal")
    File.mkdir_p!(sys_dir)
    # Intentionally empty - no thermal_zone0 directory

    %{temp_dir: temp_dir, sys_dir: sys_dir}
  end

  @doc """
  Creates sysfs with temperature sensor that returns ERROR.
  Common when sensor is present but not functioning.
  """
  def setup_broken_thermal_sensor do
    temp_dir = create_temp_dir("broken_thermal")
    thermal_dir = Path.join([temp_dir, "sys/class/thermal/thermal_zone0"])
    File.mkdir_p!(thermal_dir)

    # Write error value (some sensors write "-1" or "error")
    File.write!(Path.join(thermal_dir, "temp"), "-1")

    %{temp_dir: temp_dir, thermal_dir: thermal_dir}
  end

  @doc """
  Creates sysfs with ONLY CPU sensor (no ambient/storage sensors).
  This is the most common hardware configuration.
  """
  def setup_cpu_only_thermal(cpu_temp \\ 45) do
    temp_dir = create_temp_dir("cpu_only")
    thermal_dir = Path.join([temp_dir, "sys/class/thermal/thermal_zone0"])
    File.mkdir_p!(thermal_dir)

    # CPU at specified temperature (in millidegrees)
    millidegrees = trunc(cpu_temp * 1000)
    File.write!(Path.join(thermal_dir, "temp"), "#{millidegrees}")

    %{temp_dir: temp_dir, thermal_dir: thermal_dir, cpu_temp: cpu_temp}
  end

  @doc """
  Creates environment with high CPU temperature.
  """
  def setup_high_cpu_temp(temp \\ 70) do
    temp_dir = create_temp_dir("high_temp")
    thermal_dir = Path.join([temp_dir, "sys/class/thermal/thermal_zone0"])
    File.mkdir_p!(thermal_dir)

    millidegrees = trunc(temp * 1000)
    File.write!(Path.join(thermal_dir, "temp"), "#{millidegrees}")

    %{temp_dir: temp_dir, thermal_dir: thermal_dir, cpu_temp: temp}
  end

  @doc """
  Creates environment with critical CPU temperature.
  """
  def setup_critical_cpu_temp(temp \\ 80) do
    temp_dir = create_temp_dir("critical_temp")
    thermal_dir = Path.join([temp_dir, "sys/class/thermal/thermal_zone0"])
    File.mkdir_p!(thermal_dir)

    millidegrees = trunc(temp * 1000)
    File.write!(Path.join(thermal_dir, "temp"), "#{millidegrees}")

    %{temp_dir: temp_dir, thermal_dir: thermal_dir, cpu_temp: temp}
  end

  @doc """
  Creates environment with NO UPS hardware.
  Most deployments don't have UPS monitoring.
  """
  def setup_no_ups do
    temp_dir = create_temp_dir("no_ups")

    # Empty power_supply directory
    power_dir = Path.join([temp_dir, "sys/class/power_supply"])
    File.mkdir_p!(power_dir)
    # No BAT0 or AC directories

    # Ensure NUT is not available
    Application.put_env(:data_diode, :nut_available, false)

    %{temp_dir: temp_dir, power_dir: power_dir}
  end

  @doc """
  Creates minimal /proc with missing meminfo.
  Some containers have minimal procfs.
  """
  def setup_no_meminfo do
    temp_dir = create_temp_dir("no_meminfo")
    proc_dir = Path.join(temp_dir, "proc")
    File.mkdir_p!(proc_dir)

    # Don't create meminfo file

    %{temp_dir: temp_dir, proc_dir: proc_dir}
  end

  @doc """
  Creates /proc/meminfo with specified memory values.
  """
  def setup_meminfo(total_mb, used_mb) do
    temp_dir = create_temp_dir("meminfo")
    proc_dir = Path.join(temp_dir, "proc")
    File.mkdir_p!(proc_dir)

    available_mb = total_mb - used_mb

    meminfo = """
    MemTotal:       #{total_mb * 1024} kB
    MemFree:        #{available_mb * 1024} kB
    MemAvailable:   #{available_mb * 1024} kB
    Buffers:        #{div(total_mb * 1024, 10)} kB
    Cached:         #{div(total_mb * 1024, 5)} kB
    """

    File.write!(Path.join(proc_dir, "meminfo"), meminfo)

    %{temp_dir: temp_dir, proc_dir: proc_dir, total_mb: total_mb, used_mb: used_mb}
  end

  @doc """
  Creates network interface config with ONE interface only.
  Common on single-NIC devices.
  """
  def setup_single_interface do
    %{interfaces: ["eth0"], s1_interface: "eth0", s2_interface: nil}
  end

  @doc """
  Creates config where S1 and S2 share same interface.
  Common on devices with limited network hardware.
  """
  def setup_shared_interface do
    %{interfaces: ["eth0"], s1_interface: "eth0", s2_interface: "eth0"}
  end
end
