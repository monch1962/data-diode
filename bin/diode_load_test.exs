defmodule DataDiode.LoadTest do
  @moduledoc """
  Performance testing script for DataDiode.
  Simulates multiple concurrent TCP clients sending data to S1.
  """

  def run(concurrency, payload_size, duration_ms) do
    IO.puts("🚀 Starting Load Test...")
    IO.puts("Concurrency: #{concurrency} parallel clients")
    IO.puts("Payload Size: #{payload_size} bytes")
    IO.puts("Duration: #{duration_ms} ms")

    start_time = System.monotonic_time(:millisecond)
    
    tasks = for _ <- 1..concurrency do
      Task.async(fn -> worker(payload_size, start_time + duration_ms) end)
    end

    results = Task.await_many(tasks, duration_ms + 5000)
    
    total_packets = Enum.sum(results)
    total_time_ms = System.monotonic_time(:millisecond) - start_time
    
    avg_throughput = (total_packets / (total_time_ms / 1000.0))
    
    IO.puts("\n--- Results ---")
    IO.puts("Total Packets Sent: #{total_packets}")
    IO.puts("Total Time: #{total_time_ms} ms")
    IO.puts("Average Throughput: #{Float.round(avg_throughput, 2)} packets/sec")
    IO.puts("Average Bandwidth: #{Float.round(avg_throughput * payload_size / 1024 / 1024 * 8, 2)} Mbps")
  end

  defp worker(size, end_at) do
    host = System.get_env("LISTEN_IP") || "127.0.0.1"
    port = String.to_integer(System.get_env("LISTEN_PORT") || "8080")
    payload = :crypto.strong_rand_bytes(size)

    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false]) do
      {:ok, socket} ->
        count = loop(socket, payload, end_at, 0)
        :gen_tcp.close(socket)
        count
      {:error, reason} ->
        IO.puts("Worker failed to connect: #{inspect(reason)}")
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

# CLI Entry point
args = System.argv()
if length(args) == 3 do
  [c, s, d] = args
  DataDiode.LoadTest.run(String.to_integer(c), String.to_integer(s), String.to_integer(d))
else
  IO.puts("Usage: elixir bin/diode_load_test.exs <concurrency> <payload_size_bytes> <duration_ms>")
  IO.puts("Example: elixir bin/diode_load_test.exs 10 1024 10000")
end
