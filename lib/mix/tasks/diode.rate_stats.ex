defmodule Mix.Tasks.Diode.RateStats do
  @moduledoc """
  Show rate limiting statistics for all tracked IP addresses.

  ## Examples

      mix diode.rate_stats

  """

  use Mix.Task

  @shortdoc "Show rate limiting statistics"

  @impl true
  def run(_args) do
    Application.ensure_all_started(:data_diode)

    stats = DataDiode.RateLimiter.get_stats()

    if map_size(stats) == 0 do
      IO.puts("\nNo IP addresses currently being rate limited.\n")
    else
      IO.puts("\n=== Rate Limiting Statistics ===\n")

      Enum.each(stats, fn {ip, {count, limit}} ->
        percent = Float.round(count / limit * 100, 1)
        bar = String.duplicate("█", min(trunc(percent / 5), 20))
        IO.puts("#{ip}:")
        IO.puts("  #{count}/#{limit} packets (#{percent}%)")
        IO.puts("  [#{bar}#{String.duplicate(" ", 20 - String.length(bar))}]")
        IO.puts("")
      end)
    end
  end
end
