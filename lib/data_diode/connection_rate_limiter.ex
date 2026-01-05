defmodule DataDiode.ConnectionRateLimiter do
  @moduledoc """
  Rate limiter for TCP connection acceptance to prevent DoS attacks.

  Implements a token bucket algorithm to limit the rate of new connections.
  Prevents resource exhaustion from rapid connection attempts.

  ## Example

      # Check if a new connection should be allowed
      case DataDiode.ConnectionRateLimiter.allow_connection?() do
        :allow ->
          # Accept the connection
          :ok

        {:deny, _reason} ->
          # Reject the connection
          :error
      end

      # Get current statistics
      stats = DataDiode.ConnectionRateLimiter.get_stats()
  """

  use GenServer
  require Logger

  @default_max_connections_per_second 10
  # Burst allowance
  @bucket_size 100
  @refill_interval_ms 1000

  defstruct [:max_rate, :tokens, :last_refill, :rejected_count]

  @type t :: %__MODULE__{
          max_rate: pos_integer(),
          tokens: pos_integer(),
          last_refill: integer(),
          rejected_count: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    max_rate = Keyword.get(opts, :max_connections_per_second, @default_max_connections_per_second)

    state = %__MODULE__{
      max_rate: max_rate,
      tokens: @bucket_size,
      last_refill: System.monotonic_time(:millisecond),
      rejected_count: 0
    }

    Logger.info("ConnectionRateLimiter: Started with max #{max_rate} connections/sec")
    {:ok, state}
  end

  @doc """
  Checks if a new connection should be allowed.
  Returns `:allow` if under the rate limit, `{:deny, reason}` if exceeded.
  """
  @spec allow_connection?(GenServer.server()) :: :allow | {:deny, String.t()}
  def allow_connection?(server \\ __MODULE__) do
    GenServer.call(server, :check_rate_limit)
  end

  @doc """
  Gets current rate limiter statistics.
  """
  @spec get_stats(GenServer.server()) :: %{tokens: integer(), rejected: non_neg_integer()}
  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end

  @doc """
  Resets the rejected counter (e.g., after a DoS incident).
  """
  @spec reset_counter(GenServer.server()) :: :ok
  def reset_counter(server \\ __MODULE__) do
    GenServer.cast(server, :reset_counter)
  end

  @impl true
  def handle_call(:check_rate_limit, _from, state) do
    now = System.monotonic_time(:millisecond)
    new_state = refill_tokens(state, now)

    if new_state.tokens > 0 do
      # Allow connection
      {:reply, :allow, %{new_state | tokens: new_state.tokens - 1}}
    else
      # Rate limit exceeded
      Logger.warning(
        "ConnectionRateLimiter: Rate limit exceeded (#{new_state.max_rate} connections/sec)"
      )

      {:reply, {:deny, "Rate limit exceeded"},
       %{new_state | rejected_count: new_state.rejected_count + 1}}
    end
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, %{tokens: state.tokens, rejected: state.rejected_count}, state}
  end

  @impl true
  def handle_cast(:reset_counter, state) do
    Logger.debug("ConnectionRateLimiter: Reset rejected counter")
    {:noreply, %{state | rejected_count: 0}}
  end

  # Refills tokens based on time elapsed
  defp refill_tokens(state, now) do
    elapsed = now - state.last_refill

    if elapsed >= @refill_interval_ms do
      # Refill tokens based on elapsed time
      intervals = div(elapsed, @refill_interval_ms)
      tokens_to_add = min(state.max_rate * intervals, @bucket_size)

      new_tokens = min(state.tokens + tokens_to_add, @bucket_size)

      %{
        state
        | tokens: new_tokens,
          last_refill: state.last_refill + intervals * @refill_interval_ms
      }
    else
      state
    end
  end
end
