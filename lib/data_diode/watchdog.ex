defmodule DataDiode.Watchdog do
  @moduledoc """
  Hardware Watchdog integration for mission-critical OT environments.
  Pulses a watchdog device only when all critical services are healthy.
  """
  use GenServer
  require Logger

  @default_path "/tmp/watchdog_pulse"
  @default_interval 10_000
  @default_max_temp 80.0

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    Logger.info("Watchdog: Initialized monitoring (Target: #{resolve_path()}).")
    schedule_pulse()
    {:ok, %{path: resolve_path()}}
  end

  @impl true
  def handle_info(:pulse, state) do
    if healthy?() and thermal_safe?() do
      pulse(state.path)
    else
      Logger.warning("Watchdog: System unhealthy or thermal limit exceeded, withholding pulse.")
    end

    schedule_pulse()
    {:noreply, state}
  end

  defp healthy? do
    # Check critical processes are registered and alive
    processes = [
      DataDiode.SystemMonitor,
      DataDiode.S1.Listener,
      DataDiode.S2.Listener,
      DataDiode.Metrics
    ]

    Enum.all?(processes, fn name ->
      case Process.whereis(name) do
        nil -> false
        pid -> Process.alive?(pid)
      end
    end)
  end

  @doc false
  def pulse(path) do
    # In production OT, this usually writes to /dev/watchdog.
    # For this simulation, we touch a file to confirm the pulse.
    case File.write(path, "PULSE") do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Watchdog: Failed to pulse #{path}: #{inspect(reason)}")
    end
  end

  defp schedule_pulse do
    interval = Application.get_env(:data_diode, :watchdog_interval, @default_interval)
    Process.send_after(self(), :pulse, interval)
  end

  defp thermal_safe? do
    temp = DataDiode.SystemMonitor.get_cpu_temp()

    # If temp is "unknown", fail safe? Or assume safe?
    # In OT, we generally fail safe (stop pulse) if we can't read sensors.
    # But for now, let's treat "unknown" as safe to avoid accidental reboots on systems without sensors.
    case temp do
      "unknown" ->
        true

      t when is_number(t) ->
        max = Application.get_env(:data_diode, :watchdog_max_temp, @default_max_temp)

        if t > max do
          Logger.warning("Watchdog: Thermal Cutoff! Current: #{t}, Max: #{max}")
          false
        else
          true
        end

      _ ->
        true
    end
  end

  defp resolve_path do
    Application.get_env(:data_diode, :watchdog_path, @default_path)
  end
end
