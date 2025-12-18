defmodule DataDiode.SystemMonitor do
  @moduledoc """
  Periodically emits structured JSON health pulses for remote monitoring.
  """
  use GenServer
  require Logger

  @interval_ms 60_000 # 60 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    schedule_pulse()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:pulse, state) do
    # Collect System Info
    stats = DataDiode.Metrics.get_stats()
    
    # Simple CPU Temp (Linux/Pi specific)
    cpu_temp = read_cpu_temp()
    
    # Emit JSON pulse via Logger
    # Note: :logger_json will handle the map-to-json conversion if configured.
    Logger.info("HEALTH_PULSE: #{inspect(%{
      uptime_seconds: stats.uptime_seconds,
      packets_forwarded: stats.packets_forwarded,
      error_count: stats.error_count,
      cpu_temp: cpu_temp,
      memory_usage_mb: get_memory_usage(),
      disk_free_percent: get_disk_free("/")
    })}")

    schedule_pulse()
    {:noreply, state}
  end

  defp schedule_pulse do
    Process.send_after(self(), :pulse, @interval_ms)
  end

  defp read_cpu_temp do
    case File.read("/sys/class/thermal/thermal_zone0/temp") do
      {:ok, body} -> 
        {temp, _} = Integer.parse(String.trim(body))
        temp / 1000.0
      _ -> "unknown"
    end
  end

  defp get_memory_usage do
    :erlang.memory(:total) / 1024 / 1024
  end

  defp get_disk_free(path) do
    # Simple shell-out for disk space (Mac/Linux compatible)
    case System.cmd("df", ["-h", path]) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.at(1)
        |> String.split()
        |> Enum.at(4) # e.g. "85%"
      _ -> "unknown"
    end
  end
end
