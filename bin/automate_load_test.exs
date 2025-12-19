defmodule DataDiode.AutomatedLoadTest do
  @moduledoc """
  Automated Load Test for DataDiode.
  Manages the load test execution and reporting within a started application context.
  """

  def run(concurrency, payload_size, duration_ms) do
    IO.puts("--------------------------------------------------")
    IO.puts("🛡️  DataDiode Automated Load Test")
    IO.puts("--------------------------------------------------")
    
    # Verify app is running
    case Application.ensure_all_started(:data_diode) do
      {:ok, _} -> IO.puts("✅ DataDiode application started successfully.")
      {:error, reason} -> 
        IO.puts("❌ Failed to start DataDiode: #{inspect(reason)}")
        System.halt(1)
    end

    IO.puts("🚀 Load Test configuration:")
    IO.puts("   - Concurrency: #{concurrency} clients")
    IO.puts("   - Payload size: #{payload_size} bytes")
    IO.puts("   - Duration: #{duration_ms} ms")
    
    # Spawn workers
    end_at = System.monotonic_time(:millisecond) + duration_ms
    tasks = for i <- 1..concurrency do
      Task.async(fn -> worker(i, payload_size, end_at) end)
    end

    IO.puts("⏳ Running test...")
    start_time = System.monotonic_time(:millisecond)
    results = Task.await_many(tasks, :infinity)
    total_time_ms = System.monotonic_time(:millisecond) - start_time
    
    total_packets = Enum.sum(results)
    
    avg_throughput = (total_packets / (total_time_ms / 1000.0))
    mbps = (avg_throughput * payload_size * 8) / (1024 * 1024)
    
    IO.puts("\n📊  Final Results")
    IO.puts("--------------------------------------------------")
    IO.puts("Total Packets Sent: #{total_packets}")
    IO.puts("Actual Time:       #{total_time_ms} ms")
    IO.puts("Avg Throughput:    #{Float.round(avg_throughput, 2)} packets/sec")
    IO.puts("Avg Bandwidth:     #{Float.round(mbps, 2)} Mbps")
    IO.puts("--------------------------------------------------")
    
    IO.puts("🛑 Shutting down DataDiode...")
    Application.stop(:data_diode)
    IO.puts("🏁 Done.")
  end

  defp worker(id, size, end_at) do
    # Get port from environment or default
    port = String.to_integer(System.get_env("LISTEN_PORT") || "8080")
    payload = :crypto.strong_rand_bytes(size)

    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false]) do
      {:ok, socket} ->
        count = loop(socket, payload, end_at, 0)
        :gen_tcp.close(socket)
        IO.puts("   [Worker #{id}] Finished. Sent #{count} packets.")
        count
      {:error, reason} ->
        IO.puts("   [Worker #{id}] Failed to connect: #{inspect(reason)}")
        0
    end
  end

  defp loop(socket, payload, end_at, count) do
    if System.monotonic_time(:millisecond) < end_at do
      case :gen_tcp.send(socket, payload) do
        :ok -> loop(socket, payload, end_at, count + 1)
        _ -> count
      end
    else
      count
    end
  end
end

# CLI Entry
args = System.argv()
case args do
  [c, s, d] ->
    DataDiode.AutomatedLoadTest.run(
      String.to_integer(c),
      String.to_integer(s),
      String.to_integer(d)
    )
  _ ->
    IO.puts("Usage: mix run bin/automate_load_test.exs <concurrency> <payload_bytes> <duration_ms>")
    System.halt(1)
end
