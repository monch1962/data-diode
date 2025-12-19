defmodule DataDiode.SystemMonitor do
  @moduledoc """
  Periodically emits structured JSON health pulses for remote monitoring.
  """
  use GenServer
  require Logger

  @interval_ms 60_000 # 60 seconds

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
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
    
    # Emit JSON pulse via Logger
    Logger.info("HEALTH_PULSE: #{inspect(%{
      uptime_seconds: stats.uptime_seconds,
      packets_forwarded: stats.packets_forwarded,
      error_count: stats.error_count,
      cpu_temp: get_cpu_temp(),
      memory_usage_mb: get_memory_usage(),
      disk_free_percent: get_disk_free("/")
    })}")

    schedule_pulse()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SystemMonitor: Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def schedule_pulse do
    Process.send_after(self(), :pulse, @interval_ms)
  end

  def get_cpu_temp do
    path = Application.get_env(:data_diode, :thermal_path, "/sys/class/thermal/thermal_zone0/temp")
    case File.read(path) do
      {:ok, body} -> 
        case Integer.parse(String.trim(body)) do
          {temp, _} -> temp / 1000.0
          _ -> "unknown"
        end
      _ -> "unknown"
    end
  end

  def get_memory_usage do
     :erlang.memory(:total) / 1024 / 1024
  end

  def get_disk_free(path) when is_binary(path) do
    case System.cmd("df", ["-h", path]) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.at(1)
        |> String.split()
        |> Enum.at(4)
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  def get_disk_free(_), do: "unknown"
end
