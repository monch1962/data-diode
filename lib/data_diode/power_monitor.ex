defmodule DataDiode.PowerMonitor do
  @moduledoc """
  Power monitoring and graceful shutdown for harsh environments.
  Integrates with UPS systems via NUT (Network UPS Tools) or direct USB communication.

  Features:
  - UPS battery level monitoring every 10 seconds
  - Graceful shutdown at 10% battery
  - Low power mode activation at 30% battery
  - Power failure detection and alerting
  - Automatic shutdown when battery is critical
  - Integration with hardware watchdog for power loss detection
  """

  use GenServer
  require Logger

  @ups_check_interval 10_000  # 10 seconds
  @battery_critical 10  # Shutdown at 10%
  @battery_warning 30  # Low power mode at 30%
  @battery_low 50  # Warning at 50%

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    Logger.info("PowerMonitor: Starting power monitoring")
    schedule_ups_check()
    {:ok, %{battery_level: :unknown, on_battery: false, power_status: :unknown}}
  end

  @impl true
  def handle_info(:check_ups, state) do
    ups_status = check_ups_status()
    new_state = process_ups_status(ups_status, state)
    schedule_ups_check()
    {:noreply, new_state}
  end

  @doc """
  Manually check UPS status.
  """
  def check_ups_status do
    # Try NUT (Network UPS Tools) first
    case Application.get_env(:data_diode, :ups_monitoring, :nut) do
      :nut -> check_nut_ups()
      :sysfs -> check_sysfs_power()
      :mock -> get_mock_ups_status()
      _ -> check_nut_ups()
    end
  end

  # UPS checking methods

  defp check_nut_ups do
    # Try to query upsc (UPS client from NUT)
    ups_name = Application.get_env(:data_diode, :nut_ups_name, "ups@localhost")

    try do
      case System.cmd("upsc", [ups_name]) do
        {output, 0} ->
          parse_ups_output(output)

        {_output, _exit_code} ->
          # NUT not available, try sysfs
          Logger.warning("PowerMonitor: NUT not available, falling back to sysfs")
          check_sysfs_power()
      end
    rescue
      # If upsc command doesn't exist, fall back to sysfs
      _e in ErlangError ->
        Logger.warning("PowerMonitor: upsc command not available, falling back to sysfs")
        check_sysfs_power()
    end
  end

  defp check_sysfs_power do
    # Try to read from sysfs power supply class
    # Typically /sys/class/power_supply/
    power_supply_path = Application.get_env(:data_diode, :power_supply_path, "/sys/class/power_supply/")

    case File.ls(power_supply_path) do
      {:ok, supplies} ->
        Enum.find_value(supplies, :unknown, fn supply ->
          check_power_supply(Path.join(power_supply_path, supply))
        end)

      {:error, _reason} ->
        Logger.warning("PowerMonitor: Cannot access power supply information")
        :unknown
    end
  end

  defp check_power_supply(path) do
    # Check if this is a battery
    type_path = Path.join(path, "type")
    capacity_path = Path.join(path, "capacity")
    status_path = Path.join(path, "status")

    with {:ok, type} <- File.read(type_path),
         true <- String.contains?(type, "Battery"),
         {:ok, capacity_str} <- File.read(capacity_path),
         {capacity, _} <- Integer.parse(capacity_str),
         {:ok, status} <- File.read(status_path) do
      %{
        battery_level: capacity,
        on_battery: String.contains?(String.downcase(status), "discharging"),
        source: :sysfs
      }
    else
      _ -> :unknown
    end
  end

  defp get_mock_ups_status do
    # For testing only
    %{
      battery_level: 100,
      on_battery: false,
      source: :mock
    }
  end

  defp parse_ups_output(output) do
    # Parse upsc output format:
    # battery.charge: 100
    # battery.runtime: 3450
    # ups.status: OL
    # ...

    lines = String.split(output, "\n")

    battery_charge = parse_ups_field(lines, "battery.charge")
    ups_status = parse_ups_field(lines, "ups.status")
    battery_runtime = parse_ups_field(lines, "battery.runtime")

    battery_level =
      case battery_charge do
        nil -> :unknown
        val when is_binary(val) ->
          case Float.parse(val) do
            {num, _} -> trunc(num)
            :error -> :unknown
          end
        val when is_number(val) -> trunc(val)
        _ -> :unknown
      end

    on_battery =
      case ups_status do
        nil -> false
        status -> String.contains?(status, "OB")  # OB = On Battery
      end

    %{
      battery_level: battery_level,
      on_battery: on_battery,
      runtime: battery_runtime,
      status: ups_status,
      source: :nut
    }
  end

  defp parse_ups_field(lines, field_name) do
    Enum.find_value(lines, fn line ->
      case String.split(line, ":", parts: 2) do
        [^field_name, value] -> String.trim(value)
        _ -> nil
      end
    end)
  end

  # Status processing

  defp process_ups_status(ups_status, state) do
    cond do
      # Critical battery - immediate graceful shutdown
      is_number(ups_status.battery_level) and
        ups_status.battery_level < @battery_critical and
        ups_status.on_battery ->
        Logger.error("PowerMonitor: Critical battery level (#{ups_status.battery_level}%)")
        trigger_graceful_shutdown("Critical battery: #{ups_status.battery_level}%")

      # Low battery warning
      is_number(ups_status.battery_level) and
        ups_status.battery_level < @battery_warning and
        ups_status.on_battery ->
        Logger.warning("PowerMonitor: Low battery (#{ups_status.battery_level}%)")
        activate_low_power_mode()
        notify_low_battery(ups_status.battery_level)

      # Battery depleting
      is_number(ups_status.battery_level) and
        ups_status.battery_level < @battery_low and
        ups_status.on_battery ->
        Logger.warning("PowerMonitor: Battery level low (#{ups_status.battery_level}%)")
        notify_low_battery(ups_status.battery_level)

      # Switched to battery (power failure)
      ups_status.on_battery and not state.on_battery ->
        Logger.error("PowerMonitor: Power failure detected, now on battery")
        notify_power_failure()

      # Power restored
      not ups_status.on_battery and state.on_battery ->
        Logger.info("PowerMonitor: Power restored")
        notify_power_restored()
        deactivate_low_power_mode()

      # Unknown status
      ups_status == :unknown ->
        Logger.debug("PowerMonitor: Unable to read UPS status")

      true ->
        :ok
    end

    %{
      state
      | battery_level: ups_status[:battery_level] || state.battery_level,
        on_battery: ups_status[:on_battery] || false,
        power_status: if(ups_status.on_battery, do: :on_battery, else: :on_line)
    }
  end

  # Actions

  defp trigger_graceful_shutdown(reason) do
    Logger.error("PowerMonitor: Initiating graceful shutdown: #{reason}")

    # Notify all processes of impending shutdown
    broadcast_shutdown_imminent()

    # Flush all buffers
    try do
      GenServer.call(DataDiode.S2.Decapsulator, :flush_buffers, 5000)
    catch
      :exit, _ -> Logger.warning("PowerMonitor: Decapsulator flush timeout")
    end

    # Sync filesystem
    System.cmd("sync", [])

    # Give processes time to cleanup
    spawn(fn ->
      Process.sleep(2000)

      # Halt system (power off)
      System.cmd("shutdown", ["-h", "now"])
    end)
  end

  defp activate_low_power_mode do
    Logger.info("PowerMonitor: Activating low power mode")

    # Reduce CPU frequency (if supported)
    # This is OS-specific, would need platform-specific scripts

    # Stop non-essential services
    # Could stop Metrics temporarily to save power
    # GenServer.stop(DataDiode.Metrics)

    # Reduce cleanup interval to save disk writes
    current_interval = Application.get_env(:data_diode, :disk_cleaner_interval, 3_600_000)
    if current_interval < 10_800_000 do
      Application.put_env(:data_diode, :disk_cleaner_interval, 10_800_000)  # 3 hours
      Logger.info("PowerMonitor: Reduced disk cleanup frequency")
    end

    # Reduce packet processing rate
    Application.put_env(:data_diode, :max_packets_per_sec, 250)
    Logger.info("PowerMonitor: Reduced packet processing rate")
  end

  defp deactivate_low_power_mode do
    Logger.info("PowerMonitor: Deactivating low power mode")

    # Restore normal cleanup interval
    Application.put_env(:data_diode, :disk_cleaner_interval, 3_600_000)  # 1 hour

    # Restore normal packet processing rate
    Application.put_env(:data_diode, :max_packets_per_sec, 1000)
  end

  defp notify_power_failure do
    Logger.error("PowerMonitor: === POWER FAILURE DETECTED ===")

    # Could send alert via various mechanisms:
    # - Email
    # - SMS
    # - Webhook
    # - SNMP trap
    # - Write to alert file

    alert_file = Application.get_env(:data_diode, :alert_file, "/var/log/data-diode/alerts.log")
    alert_message = "[#{DateTime.utc_now()}] POWER_FAILURE: System running on battery\n"

    File.write(alert_file, alert_message, [:append])
  end

  defp notify_power_restored do
    Logger.info("PowerMonitor: === POWER RESTORED ===")

    alert_file = Application.get_env(:data_diode, :alert_file, "/var/log/data-diode/alerts.log")
    alert_message = "[#{DateTime.utc_now()}] POWER_RESTORED: AC power available\n"

    File.write(alert_file, alert_message, [:append])
  end

  defp notify_low_battery(level) do
    Logger.warning("PowerMonitor: Low battery alert: #{level}%")

    alert_file = Application.get_env(:data_diode, :alert_file, "/var/log/data-diode/alerts.log")
    alert_message = "[#{DateTime.utc_now()}] LOW_BATTERY: #{level}%\n"

    File.write(alert_file, alert_message, [:append])
  end

  defp broadcast_shutdown_imminent do
    # Send message to all registered processes
    Registry.dispatch(:data_diode_events, :shutdown_imminent, fn entries ->
      for {pid, _} <- entries do
        send(pid, :shutdown_imminent)
      end
    end)
  end

  # Scheduling

  defp schedule_ups_check do
    interval = Application.get_env(:data_diode, :ups_check_interval, @ups_check_interval)
    Process.send_after(self(), :check_ups, interval)
  end
end
