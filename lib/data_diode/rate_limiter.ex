defmodule DataDiode.RateLimiter do
  @moduledoc """
  Rate limiter to prevent abuse and DoS attacks from individual source IPs.

  Implements a sliding window rate limiting algorithm per source IP.
  Tracks packet counts and drops packets from IPs exceeding the threshold.
  """

  use GenServer
  require Logger

  @default_max_packets_per_second 100
  @window_size_ms 1000
  @cleanup_interval_ms 60_000

  defstruct [:max_packets, :window_ms, :ip_counts, :last_cleanup]

  @type ip :: String.t()
  @type ip_count :: {non_neg_integer(), integer()}
  @type ip_counts :: %{ip() => ip_count()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    max_packets = Keyword.get(opts, :max_packets_per_second, @default_max_packets_per_second)

    state = %__MODULE__{
      max_packets: max_packets,
      window_ms: @window_size_ms,
      ip_counts: %{},
      last_cleanup: System.monotonic_time(:millisecond)
    }

    schedule_cleanup()
    Logger.info("RateLimiter: Started with max #{max_packets} packets/sec per IP")
    {:ok, state}
  end

  @doc """
  Checks if a packet from the given source IP should be allowed.
  Returns `:allow` if under the rate limit, `{:deny, reason}` if exceeded.
  """
  @spec check_rate_limit(ip(), GenServer.server()) :: :allow | {:deny, String.t()}
  def check_rate_limit(ip_address, server \\ __MODULE__) when is_binary(ip_address) do
    GenServer.call(server, {:check_rate_limit, ip_address})
  end

  @doc """
  Records a packet from the given IP (for manual tracking).
  Most callers should use `check_rate_limit/2` instead.
  """
  @spec record_packet(ip(), GenServer.server()) :: :ok
  def record_packet(ip_address, server \\ __MODULE__) when is_binary(ip_address) do
    GenServer.cast(server, {:record_packet, ip_address})
  end

  @doc """
  Gets current rate limit statistics for all tracked IPs.
  Returns a map where each IP maps to {count, limit}.
  """
  @spec get_stats(GenServer.server()) :: %{ip() => {non_neg_integer(), pos_integer()}}
  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end

  @doc """
  Resets rate limit tracking for a specific IP (e.g., after a ban period).
  """
  @spec reset_ip(ip(), GenServer.server()) :: :ok
  def reset_ip(ip_address, server \\ __MODULE__) when is_binary(ip_address) do
    GenServer.cast(server, {:reset_ip, ip_address})
  end

  @impl true
  def handle_call({:check_rate_limit, ip_address}, _from, state) do
    now = System.monotonic_time(:millisecond)
    {result, new_state} = check_and_update(ip_address, now, state)
    {:reply, result, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    stats =
      Map.new(state.ip_counts, fn {ip, {count, _start}} ->
        {ip, {count, state.max_packets}}
      end)

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:record_packet, ip_address}, state) do
    now = System.monotonic_time(:millisecond)
    {_result, new_state} = check_and_update(ip_address, now, state)
    {:noreply, new_state}
  end

  def handle_cast({:reset_ip, ip_address}, state) do
    new_state = %{state | ip_counts: Map.delete(state.ip_counts, ip_address)}
    Logger.debug("RateLimiter: Reset tracking for #{ip_address}")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup_old_entries(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  # Private functions

  defp check_and_update(ip_address, now, state) do
    case Map.get(state.ip_counts, ip_address) do
      nil ->
        # First packet from this IP in current window
        new_counts = Map.put(state.ip_counts, ip_address, {1, now})
        new_state = %{state | ip_counts: new_counts}
        {:allow, new_state}

      {count, window_start} ->
        if now - window_start >= state.window_ms do
          # Window expired, start fresh
          new_counts = Map.put(state.ip_counts, ip_address, {1, now})
          new_state = %{state | ip_counts: new_counts}
          {:allow, new_state}
        else
          # Within current window
          check_rate_limit_for_count(count, window_start, ip_address, state)
        end
    end
  end

  defp check_rate_limit_for_count(count, window_start, ip_address, state) do
    if count >= state.max_packets do
      # Rate limit exceeded
      Logger.warning(
        "RateLimiter: Dropped packet from #{ip_address} (#{count} packets exceeds limit of #{state.max_packets})"
      )

      {{:deny, "Rate limit exceeded (#{count}/#{state.max_packets} packets/sec)"}, state}
    else
      # Increment count
      new_counts = Map.put(state.ip_counts, ip_address, {count + 1, window_start})
      new_state = %{state | ip_counts: new_counts}
      {:allow, new_state}
    end
  end

  defp cleanup_old_entries(state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - state.window_ms * 10

    new_counts =
      Enum.filter(state.ip_counts, fn {_ip, {_count, window_start}} ->
        window_start > cutoff
      end)
      |> Map.new()

    cleanup_count = map_size(state.ip_counts) - map_size(new_counts)

    if cleanup_count > 0 do
      Logger.debug("RateLimiter: Cleaned up #{cleanup_count} old IP entries")
    end

    %{state | ip_counts: new_counts, last_cleanup: now}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
