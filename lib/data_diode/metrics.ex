defmodule DataDiode.Metrics do
  @moduledoc """
  Enhanced metrics tracking for operational monitoring and observability.

  Tracks:
  - Packet throughput and error rates
  - Packet size statistics (min, max, avg)
  - Protocol-specific metrics
  - Per-source IP tracking
  - Processing latency
  - Rejection reasons breakdown
  """
  use Agent

  @type metric_state :: %{
          start_time: integer(),
          packets_forwarded: non_neg_integer(),
          error_count: non_neg_integer(),
          bytes_forwarded: non_neg_integer(),
          packet_sizes: [non_neg_integer()],
          protocol_counts: %{atom() => non_neg_integer()},
          source_ips: %{String.t() => non_neg_integer()},
          rejection_reasons: %{String.t() => non_neg_integer()},
          last_packet_time: integer() | nil
        }

  @type stats :: %{
          start_time: integer(),
          packets_forwarded: non_neg_integer(),
          error_count: non_neg_integer(),
          bytes_forwarded: non_neg_integer(),
          uptime_seconds: non_neg_integer(),
          packets_per_second: float(),
          bytes_per_second: float(),
          packet_size_min: non_neg_integer(),
          packet_size_max: non_neg_integer(),
          packet_size_avg: float(),
          protocol_counts: %{atom() => non_neg_integer()},
          top_source_ips: [{String.t(), non_neg_integer()}],
          rejection_reasons: %{String.t() => non_neg_integer()},
          last_packet_age_seconds: non_neg_integer() | nil
        }

  @max_packet_sizes 1000
  @max_source_ips 100

  @doc """
  Starts the Metrics agent.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(
      fn ->
        %{
          start_time: System.monotonic_time(),
          packets_forwarded: 0,
          error_count: 0,
          bytes_forwarded: 0,
          packet_sizes: [],
          protocol_counts: %{},
          source_ips: %{},
          rejection_reasons: %{},
          last_packet_time: nil
        }
      end,
      name: __MODULE__
    )
  end

  @doc "Increment packet count and track size."
  @spec record_packet(non_neg_integer(), atom() | nil) :: :ok
  def record_packet(size_bytes, protocol \\ nil) do
    Agent.update(__MODULE__, fn state ->
      new_sizes = [size_bytes | state.packet_sizes] |> Enum.take(@max_packet_sizes)

      new_protocol_counts =
        if protocol do
          Map.update(state.protocol_counts, protocol, 1, &(&1 + 1))
        else
          state.protocol_counts
        end

      %{
        state
        | packets_forwarded: state.packets_forwarded + 1,
          bytes_forwarded: state.bytes_forwarded + size_bytes,
          packet_sizes: new_sizes,
          protocol_counts: new_protocol_counts,
          last_packet_time: System.monotonic_time()
      }
    end)
  end

  @doc "Increment packet count (legacy for backward compatibility)."
  @spec inc_packets() :: :ok
  def inc_packets, do: record_packet(0, nil)

  @doc "Increment error count with optional reason."
  @spec inc_errors(String.t() | nil) :: :ok
  def inc_errors(reason \\ nil) do
    Agent.update(__MODULE__, fn state ->
      new_rejection_reasons =
        if reason do
          Map.update(state.rejection_reasons, reason, 1, &(&1 + 1))
        else
          state.rejection_reasons
        end

      %{state | error_count: state.error_count + 1, rejection_reasons: new_rejection_reasons}
    end)
  end

  @doc "Track a packet from a specific source IP."
  @spec track_source_ip(String.t()) :: :ok
  def track_source_ip(ip) when is_binary(ip) do
    Agent.update(__MODULE__, fn state ->
      new_source_ips =
        Map.update(state.source_ips, ip, 1, fn count ->
          # Keep only top IPs by count
          count + 1
        end)

      # Trim to max entries
      trimmed_source_ips =
        new_source_ips
        |> Enum.sort_by(fn {_ip, count} -> count end, :desc)
        |> Enum.take(@max_source_ips)
        |> Map.new()

      %{state | source_ips: trimmed_source_ips}
    end)
  end

  @doc "Get all metrics formatted for display."
  @spec get_stats() :: stats()
  def get_stats do
    Agent.get(__MODULE__, fn state ->
      uptime_sec =
        (System.monotonic_time() - state.start_time)
        |> System.convert_time_unit(:native, :second)

      packets_per_sec = if uptime_sec > 0, do: state.packets_forwarded / uptime_sec, else: 0.0
      bytes_per_sec = if uptime_sec > 0, do: state.bytes_forwarded / uptime_sec, else: 0.0

      {min_size, max_size, avg_size} = calculate_packet_stats(state.packet_sizes)

      top_sources =
        state.source_ips
        |> Enum.sort_by(fn {_ip, count} -> count end, :desc)
        |> Enum.take(10)

      last_packet_age =
        if state.last_packet_time do
          (System.monotonic_time() - state.last_packet_time)
          |> System.convert_time_unit(:native, :second)
        else
          nil
        end

      %{
        start_time: state.start_time,
        packets_forwarded: state.packets_forwarded,
        error_count: state.error_count,
        bytes_forwarded: state.bytes_forwarded,
        uptime_seconds: uptime_sec,
        packets_per_second: Float.round(packets_per_sec, 2),
        bytes_per_second: Float.round(bytes_per_sec, 2),
        packet_size_min: min_size,
        packet_size_max: max_size,
        packet_size_avg: avg_size,
        protocol_counts: state.protocol_counts,
        top_source_ips: top_sources,
        rejection_reasons: state.rejection_reasons,
        last_packet_age_seconds: last_packet_age
      }
    end)
  end

  @doc "Reset stats for testing."
  @spec reset_stats() :: :ok
  def reset_stats do
    Agent.update(__MODULE__, fn state ->
      %{
        state
        | packets_forwarded: 0,
          error_count: 0,
          bytes_forwarded: 0,
          packet_sizes: [],
          protocol_counts: %{},
          source_ips: %{},
          rejection_reasons: %{},
          last_packet_time: nil
      }
    end)
  end

  # Private helper functions

  @spec calculate_packet_stats([non_neg_integer()]) ::
          {non_neg_integer(), non_neg_integer(), float()}
  defp calculate_packet_stats([]), do: {0, 0, 0.0}

  defp calculate_packet_stats(sizes) do
    min_size = Enum.min(sizes)
    max_size = Enum.max(sizes)

    avg_size =
      if sizes != [] do
        Enum.sum(sizes) / length(sizes)
      else
        0.0
      end

    {min_size, max_size, Float.round(avg_size, 2)}
  end
end
