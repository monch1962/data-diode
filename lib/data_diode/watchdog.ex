defmodule DataDiode.Watchdog do
  @moduledoc """
  Hardware Watchdog integration for mission-critical OT environments.
  Pulses a watchdog device only when all critical services are healthy.
  """
  use GenServer
  require Logger

  @default_path "/tmp/watchdog_pulse"
  @default_interval 10_000

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
    if healthy?() do
      pulse(state.path)
    else
      Logger.warning("Watchdog: System unhealthy, withholding pulse.")
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

  defp pulse(path) do
    # In production OT, this usually writes to /dev/watchdog.
    # For this simulation, we touch a file to confirm the pulse.
    case File.write(path, "PULSE") do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("Watchdog: Failed to pulse #{path}: #{inspect(reason)}")
    end
  end

  defp schedule_pulse do
    interval = Application.get_env(:data_diode, :watchdog_interval, @default_interval)
    Process.send_after(self(), :pulse, interval)
  end

  defp resolve_path do
    Application.get_env(:data_diode, :watchdog_path, @default_path)
  end
end
