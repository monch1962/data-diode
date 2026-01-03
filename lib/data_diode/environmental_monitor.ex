defmodule DataDiode.EnvironmentalMonitor do
  @moduledoc """
  Multi-zone environmental monitoring for harsh environments.
  Monitors CPU, GPU, storage, ambient temperature, and humidity.
  Implements thermal hysteresis to prevent rapid cycling.

  Critical thresholds for different components:
  - CPU: 85°C critical, 75°C warning, -20°C critical cold
  - Storage: 60°C critical (SD cards/SSDs)
  - Ambient: 70°C critical, 60°C warning, 5°C critical cold
  - Humidity: 90% critical (condensation risk)

  Uses thermal hysteresis (5°C delta) to prevent rapid on/off cycling.
  """

  use GenServer
  require Logger

  # Critical thresholds (Celsius)
  @cpu_temp_critical 85
  @cpu_temp_warning 75
  @cpu_temp_critical_cold -20
  @storage_temp_critical 60
  @storage_temp_warning 50
  @ambient_temp_critical 70
  @ambient_temp_warning 60
  @ambient_temp_critical_cold 5
  @ambient_temp_warning_cold 10

  # Humidity thresholds (percentage)
  @humidity_critical 90
  @humidity_warning 80

  # Thermal hysteresis - prevent rapid cycling (5°C)
  @hysteresis_delta 5

  # Temperature states for hysteresis
  @cooling_state :cooling
  @heating_state :heating
  @normal_state :normal

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    Logger.info("EnvironmentalMonitor: Starting multi-zone monitoring")

    state = %{
      thermal_state: @normal_state,
      history: [],
      last_action: nil
    }

    {:ok, state}
  end

  @doc """
  Reads all environmental sensors and evaluates conditions.
  Returns a map with current readings and status.
  """
  def monitor_all_zones do
    %{
      cpu: read_cpu_temp(),
      storage: read_storage_temp(),
      ambient: read_ambient_temp(),
      humidity: read_humidity(),
      timestamp: System.system_time(:millisecond)
    }
    |> evaluate_conditions()
  end

  @doc """
  Gets the current environmental state.
  """
  def get_current_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    current = monitor_all_zones()
    {:reply, current, state}
  end

  # Reading functions

  defp read_cpu_temp do
    # Read from /sys/class/thermal/thermal_zone0/temp
    thermal_path =
      Application.get_env(
        :data_diode,
        :thermal_zone_path,
        "/sys/class/thermal/thermal_zone0/temp"
      )

    case File.read(thermal_path) do
      {:ok, contents} ->
        temp_millidegrees = String.trim(contents) |> String.to_integer()
        # Convert to Celsius
        temp_millidegrees / 1000.0

      {:error, _reason} ->
        Logger.warning("EnvironmentalMonitor: Cannot read CPU temperature from #{thermal_path}")
        :unknown
    end
  end

  defp read_storage_temp do
    # Try to read from HDD/SSD SMART data via smartctl or hddtemp
    # For now, approximate with CPU temp (storage typically cooler)
    case read_cpu_temp() do
      :unknown -> :unknown
      # Storage usually ~10°C cooler
      cpu_temp when is_number(cpu_temp) -> max(cpu_temp - 10, 0)
      _ -> :unknown
    end
  end

  defp read_ambient_temp do
    # Try to read from external sensor (DHT22, DS18B20, etc.)
    sensor_type = Application.get_env(:data_diode, :ambient_temp_sensor)

    case sensor_type do
      nil ->
        # No sensor configured, estimate from CPU
        estimate_ambient_from_cpu()

      %{type: :dht22, pin: _pin} ->
        read_dht22_sensor(:temp)

      %{type: :ds18b20, id: _id} ->
        read_ds18b20_sensor()

      %{type: :file, path: path} ->
        read_from_file(path)

      _ ->
        Logger.warning("EnvironmentalMonitor: Unknown ambient sensor type")
        estimate_ambient_from_cpu()
    end
  end

  defp read_humidity do
    # Try to read from DHT22 or similar sensor
    sensor_type = Application.get_env(:data_diode, :humidity_sensor)

    case sensor_type do
      nil ->
        # No sensor configured
        :unknown

      %{type: :dht22, pin: _pin} ->
        read_dht22_sensor(:humidity)

      %{type: :file, path: path} ->
        read_from_file(path)

      _ ->
        :unknown
    end
  end

  defp estimate_ambient_from_cpu do
    case read_cpu_temp() do
      :unknown -> :unknown
      cpu_temp when is_number(cpu_temp) -> max(cpu_temp - 15, 0)
      _ -> :unknown
    end
  end

  defp read_dht22_sensor(_reading) do
    # Would need GPIO library (circuits, elixir_gpio)
    # For now, return :unknown
    # In production, this would use:
    # {:ok, temp, humidity} = Circuits.DHT22.read(pin)
    :unknown
  end

  defp read_ds18b20_sensor do
    # Read from /sys/bus/w1/devices/
    # For now, return :unknown
    :unknown
  end

  defp read_from_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        trimmed = String.trim(contents)

        case Float.parse(trimmed) do
          {val, _} -> val
          :error -> :unknown
        end

      {:error, _reason} ->
        :unknown
    end
  end

  # Condition evaluation with hysteresis

  defp evaluate_conditions(readings) do
    state = get_internal_state()

    evaluate_conditions_in_priority_order(readings, state)
  end

  defp evaluate_conditions_in_priority_order(readings, state) do
    cond do
      handle_critical_hot?(readings) -> handle_critical_hot(readings)
      handle_warning_hot?(readings, state) -> handle_warning_hot(readings)
      handle_critical_cold?(readings) -> handle_critical_cold(readings)
      handle_warning_cold?(readings, state) -> handle_warning_cold(readings)
      handle_critical_humidity?(readings) -> handle_critical_humidity(readings)
      handle_warning_humidity?(readings) -> handle_warning_humidity(readings)
      true -> handle_normal_conditions(readings, state)
    end
  end

  defp handle_critical_hot?(readings), do: any_critical_hot?(readings)

  defp handle_critical_hot(readings) do
    Logger.error("EnvironmentalMonitor: Critical temperature exceeded!")
    trigger_emergency_shutdown(readings)
    Map.put(readings, :status, :critical_hot)
  end

  defp handle_warning_hot?(readings, state), do: any_warning_hot?(readings, state)

  defp handle_warning_hot(readings) do
    activate_cooling_mode()
    Map.put(readings, :status, :warning_hot)
  end

  defp handle_critical_cold?(readings), do: any_critical_cold?(readings)

  defp handle_critical_cold(readings) do
    activate_heating_mode()
    Map.put(readings, :status, :critical_cold)
  end

  defp handle_warning_cold?(readings, state), do: any_warning_cold?(readings, state)

  defp handle_warning_cold(readings) do
    activate_heating_mode()
    Map.put(readings, :status, :warning_cold)
  end

  defp handle_critical_humidity?(readings) do
    readings.humidity != :unknown and readings.humidity > @humidity_critical
  end

  defp handle_critical_humidity(readings) do
    activate_dehumidifier()
    Map.put(readings, :status, :critical_humidity)
  end

  defp handle_warning_humidity?(readings) do
    readings.humidity != :unknown and readings.humidity > @humidity_warning
  end

  defp handle_warning_humidity(readings) do
    Logger.warning("EnvironmentalMonitor: High humidity (#{readings.humidity}%)")
    Map.put(readings, :status, :warning_humidity)
  end

  defp handle_normal_conditions(readings, state) do
    if state != @normal_state do
      Logger.info("EnvironmentalMonitor: Conditions normalized, returning to normal mode")
      set_internal_state(@normal_state)
    end

    Map.put(readings, :status, :normal)
  end

  defp any_critical_hot?(readings) do
    (is_number(readings.cpu) and readings.cpu >= @cpu_temp_critical) or
      (is_number(readings.storage) and readings.storage >= @storage_temp_critical) or
      (is_number(readings.ambient) and readings.ambient >= @ambient_temp_critical)
  end

  defp any_warning_hot?(readings, state) do
    # Apply hysteresis - only trigger warning if we're not already cooling
    # or if temperature exceeds warning + hysteresis
    cooling_active = state == @cooling_state

    cpu_hot =
      is_number(readings.cpu) and
        cpu_above_warning?(readings.cpu, cooling_active)

    storage_hot =
      is_number(readings.storage) and
        storage_above_warning?(readings.storage, cooling_active)

    ambient_hot =
      is_number(readings.ambient) and
        ambient_above_warning?(readings.ambient, cooling_active)

    cpu_hot or storage_hot or ambient_hot
  end

  defp cpu_above_warning?(cpu_temp, cooling_active) do
    warning_threshold =
      if cooling_active, do: @cpu_temp_warning + @hysteresis_delta, else: @cpu_temp_warning

    cpu_temp >= warning_threshold
  end

  defp storage_above_warning?(storage_temp, cooling_active) do
    warning_threshold =
      if cooling_active,
        do: @storage_temp_warning + @hysteresis_delta,
        else: @storage_temp_warning

    storage_temp >= warning_threshold
  end

  defp ambient_above_warning?(ambient_temp, cooling_active) do
    warning_threshold =
      if cooling_active,
        do: @ambient_temp_warning + @hysteresis_delta,
        else: @ambient_temp_warning

    ambient_temp >= warning_threshold
  end

  defp any_critical_cold?(readings) do
    (is_number(readings.cpu) and readings.cpu <= @cpu_temp_critical_cold) or
      (is_number(readings.ambient) and readings.ambient <= @ambient_temp_critical_cold)
  end

  defp any_warning_cold?(readings, state) do
    # Apply hysteresis for cold as well
    heating_active = state == @heating_state

    ambient_cold =
      is_number(readings.ambient) and
        ambient_below_warning?(readings.ambient, heating_active)

    cpu_cold =
      is_number(readings.cpu) and
        cpu_below_critical?(readings.cpu, heating_active)

    ambient_cold or cpu_cold
  end

  defp ambient_below_warning?(ambient_temp, heating_active) do
    threshold = @ambient_temp_warning_cold
    adjusted = if heating_active, do: threshold - @hysteresis_delta, else: threshold
    ambient_temp <= adjusted
  end

  defp cpu_below_critical?(cpu_temp, heating_active) do
    critical_threshold =
      if heating_active, do: @cpu_temp_critical_cold + 10, else: @cpu_temp_critical_cold + 5

    cpu_temp <= critical_threshold
  end

  # Mitigation actions

  defp activate_cooling_mode do
    state = get_internal_state()

    if state != @cooling_state do
      Logger.warning("EnvironmentalMonitor: Activating cooling mode")
      set_internal_state(@cooling_state)

      # In production, this would:
      # - Increase fan speed
      # - Throttle CPU frequency
      # - Reduce packet processing rate
      # - Alert monitoring system

      # For now, reduce processing rate
      Application.put_env(:data_diode, :max_packets_per_sec, 500)
    end
  end

  defp activate_heating_mode do
    state = get_internal_state()

    if state != @heating_state do
      Logger.warning("EnvironmentalMonitor: Activating heating mode")
      set_internal_state(@heating_state)

      # In production, this would:
      # - Enable heating elements
      # - Increase CPU frequency (self-heating)
      # - Alert monitoring system
    end
  end

  defp activate_dehumidifier do
    Logger.error("EnvironmentalMonitor: Critical humidity - activating dehumidification")
    # In production, this would activate dehumidifier or alert
  end

  defp trigger_emergency_shutdown(readings) do
    Logger.error(
      "EnvironmentalMonitor: EMERGENCY SHUTDOWN - Critical temperatures: #{inspect(readings)}"
    )

    # Flush all buffers (if Decapsulator is running)
    case Process.whereis(DataDiode.S2.Decapsulator) do
      nil ->
        Logger.warning("EnvironmentalMonitor: S2.Decapsulator not running, skipping buffer flush")

      _pid ->
        try do
          GenServer.call(DataDiode.S2.Decapsulator, :flush_buffers, 5000)
        rescue
          error ->
            Logger.error("EnvironmentalMonitor: Failed to flush buffers: #{inspect(error)}")
        end
    end

    # Sync filesystem
    System.cmd("sync", [])

    # Shutdown in 1 minute (disabled in test environment)
    if Application.get_env(:data_diode, :enable_emergency_shutdown, false) do
      spawn(fn ->
        Process.sleep(1000)
        System.cmd("shutdown", ["-h", "+1"])
      end)
    else
      Logger.warning("EnvironmentalMonitor: Emergency shutdown disabled by configuration")
    end
  end

  # State management for hysteresis
  defp get_internal_state do
    case Process.get(:env_monitor_state) do
      nil -> @normal_state
      state -> state
    end
  end

  defp set_internal_state(state) do
    Process.put(:env_monitor_state, state)
  end
end
