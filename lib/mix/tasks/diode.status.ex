defmodule Mix.Tasks.Diode.Status do
  @moduledoc """
  Show the current status of the Data Diode system.

  ## Examples

      mix diode.status
  """

  use Mix.Task

  @shortdoc "Show Data Diode system status"

  @impl true
  def run(_args) do
    Application.ensure_all_started(:data_diode)

    IO.puts("\n=== Data Diode System Status ===\n")

    # Get critical processes
    processes = [
      {"S1 Listener", DataDiode.S1.Listener},
      {"S2 Listener", DataDiode.S2.Listener},
      {"Encapsulator", DataDiode.S1.Encapsulator},
      {"Decapsulator", DataDiode.S2.Decapsulator},
      {"Rate Limiter", DataDiode.RateLimiter},
      {"Memory Guard", DataDiode.MemoryGuard},
      {"Network Guard", DataDiode.NetworkGuard},
      {"Power Monitor", DataDiode.PowerMonitor},
      {"Metrics", DataDiode.Metrics}
    ]

    IO.puts("Critical Processes:")

    Enum.each(processes, fn {name, module} ->
      pid = Process.whereis(module)
      status = if pid && Process.alive?(pid), do: "✓ Running", else: "✗ Stopped"
      IO.puts("  #{name}: #{status}")
    end)

    IO.puts("\nMemory Usage:")
    memory = DataDiode.MemoryGuard.get_memory_usage()
    IO.puts("  Total: #{Float.round(memory.total / 1_048_576, 2)} MB")
    IO.puts("  Used: #{Float.round(memory.used / 1_048_576, 2)} MB")
    IO.puts("  Available: #{Float.round(memory.available / 1_048_576, 2)} MB")
    IO.puts("  Percent: #{Float.round(memory.percent, 2)}%")

    IO.puts("\nNetwork Interfaces:")
    network = DataDiode.NetworkGuard.check_network_interfaces()
    s1_status = if network.s1.up, do: "UP", else: "DOWN"
    s2_status = if network.s2.up, do: "UP", else: "DOWN"
    IO.puts("  S1 (#{network.s1.interface}): #{s1_status}")
    IO.puts("  S2 (#{network.s2.interface}): #{s2_status}")

    IO.puts("\nOperational Metrics:")
    stats = DataDiode.Metrics.get_stats()
    IO.puts("  Packets Received: #{stats.packets_received}")
    IO.puts("  Packets Sent: #{stats.packets_sent}")
    IO.puts("  Bytes Received: #{stats.bytes_received}")
    IO.puts("  Bytes Written: #{stats.bytes_written}")
    IO.puts("  Errors: #{stats.errors}")

    IO.puts("\n")
  end
end
