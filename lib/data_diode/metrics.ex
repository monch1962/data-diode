defmodule DataDiode.Metrics do
  @moduledoc """
  A simple Agent to track operational metrics for field engineers.
  """
  use Agent

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        %{
          start_time: System.monotonic_time(),
          packets_forwarded: 0,
          error_count: 0
        }
      end,
      name: __MODULE__
    )
  end

  @doc "Incr packet count."
  def inc_packets do
    Agent.update(__MODULE__, &Map.update!(&1, :packets_forwarded, fn count -> count + 1 end))
  end

  @doc "Incr error count."
  def inc_errors do
    Agent.update(__MODULE__, &Map.update!(&1, :error_count, fn count -> count + 1 end))
  end

  @doc "Get all metrics formatted for display."
  def get_stats do
    Agent.get(__MODULE__, fn state ->
      uptime_sec =
        (System.monotonic_time() - state.start_time)
        |> System.convert_time_unit(:native, :second)

      Map.put(state, :uptime_seconds, uptime_sec)
    end)
  end

  @doc "Reset stats for testing."
  def reset_stats do
    Agent.update(__MODULE__, fn state ->
      %{state | packets_forwarded: 0, error_count: 0}
    end)
  end
end
