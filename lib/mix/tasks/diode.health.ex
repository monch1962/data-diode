defmodule Mix.Tasks.Diode.Health do
  @moduledoc """
  Perform a comprehensive health check of the Data Diode system.

  ## Examples

      mix diode.health

  """

  use Mix.Task

  @shortdoc "Perform comprehensive health check"

  @impl true
  def run(_args) do
    Application.ensure_all_started(:data_diode)

    IO.puts("\n=== Data Diode Health Check ===\n")

    # Check critical processes
    processes_ok = check_critical_processes()

    # Check memory
    memory_ok = check_memory()

    # Check network interfaces
    network_ok = check_network()

    # Check disk space
    disk_ok = check_disk()

    # Overall status
    all_ok = processes_ok and memory_ok and network_ok and disk_ok

    IO.puts("\nOverall Status: #{if all_ok, do: "✓ HEALTHY", else: "✗ UNHEALTHY"}\n")

    unless all_ok do
      System.at_exit(fn _ ->
        System.put_env("MIX_EXIT_CODE", "1")
      end)
    end
  end

  defp check_critical_processes do
    IO.puts("Critical Processes:")

    processes = [
      DataDiode.S1.Listener,
      DataDiode.S2.Listener,
      DataDiode.S1.Encapsulator,
      DataDiode.S2.Decapsulator,
      DataDiode.Metrics
    ]

    results =
      Enum.map(processes, fn module ->
        pid = Process.whereis(module)
        alive = pid != nil and Process.alive?(pid)
        name = module |> Module.split() |> Enum.join(".")
        status = if alive, do: "✓", else: "✗"
        IO.puts("  #{status} #{name}")
        alive
      end)

    Enum.all?(results)
  end

  defp check_memory do
    IO.puts("\nMemory:")

    memory = DataDiode.MemoryGuard.get_memory_usage()

    status =
      cond do
        memory.percent >= 90 -> "✗ CRITICAL"
        memory.percent >= 80 -> "⚠ WARNING"
        true -> "✓ OK"
      end

    IO.puts("  #{status} #{Float.round(memory.percent, 2)}% used")
    IO.puts("     Total: #{Float.round(memory.total / 1_048_576, 2)} MB")
    IO.puts("     Available: #{Float.round(memory.available / 1_048_576, 2)} MB")

    memory.percent < 90
  end

  defp check_network do
    IO.puts("\nNetwork:")

    network = DataDiode.NetworkGuard.check_network_interfaces()

    s1_status = if network.s1.up, do: "✓ UP", else: "✗ DOWN"
    s2_status = if network.s2.up, do: "✓ UP", else: "✗ DOWN"

    IO.puts("  #{s1_status} S1 (#{network.s1.interface})")
    IO.puts("  #{s2_status} S2 (#{network.s2.interface})")

    network.s1.up or network.s2.up
  end

  defp check_disk do
    IO.puts("\nDisk:")

    data_dir = Application.get_env(:data_diode, :data_dir, ".")

    try do
      {output, 0} = System.cmd("df", ["-h", data_dir])

      lines = String.split(output, "\n")

      if length(lines) > 1 do
        [_header, usage_line | _] = lines
        parts = String.split(usage_line) |> Enum.filter(&(&1 != ""))

        if length(parts) >= 5 do
          [_device, _size, _used, _avail, use_pct | _] = parts
          pct = String.trim_trailing(use_pct, "%") |> String.to_integer()

          status =
            cond do
              pct >= 95 -> "✗ CRITICAL"
              pct >= 90 -> "⚠ WARNING"
              true -> "✓ OK"
            end

          IO.puts("  #{status} #{use_pct} used")
          IO.puts("     Directory: #{data_dir}")

          pct < 95
        else
          IO.puts("  ⚠ Unable to parse disk usage")
          true
        end
      else
        IO.puts("  ⚠ Unable to check disk usage")
        true
      end
    rescue
      _ ->
        IO.puts("  ⚠ Unable to check disk usage")
        true
    end
  end
end
