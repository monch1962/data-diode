defmodule DataDiode.CircuitBreaker do
  @moduledoc """
  Circuit Breaker to prevent cascading failures.

  Implements a state machine with three states:
  - **:closed** - Normal operation, requests pass through
  - **:open** - Failing, requests are rejected immediately
  - **:half_open** - Testing if service has recovered

  Transitions:
  - closed → open: After failure_threshold failures
  - open → half_open: After timeout_ms has elapsed
  - half_open → closed: After success_threshold successful calls
  - half_open → open: On any failure

  ## Example

      # Execute a call with circuit breaker protection
      case DataDiode.CircuitBreaker.call(:udp_send, fn ->
        :gen_udp.send(socket, host, port, packet)
      end) do
        {:ok, result} ->
          # Success, handle result
          :ok

        {:error, :circuit_open} ->
          # Circuit is open, request rejected
          Logger.warning("Circuit breaker is open, backing off")
          {:error, :circuit_open}

        {:error, reason} ->
          # Call failed
          {:error, reason}
      end

      # Get current state
      state = DataDiode.CircuitBreaker.get_state(:udp_send)
  """

  use GenServer
  require Logger

  @default_failure_threshold 5
  @default_success_threshold 2
  @default_timeout_ms 30_000
  @default_half_open_max_calls 3

  defstruct [
    :name,
    :state,
    :failure_count,
    :success_count,
    :failure_threshold,
    :success_threshold,
    :timeout_ms,
    :opened_at,
    :half_open_calls,
    :half_open_max_calls
  ]

  @type t :: %__MODULE__{
          name: atom(),
          state: :closed | :open | :half_open,
          failure_count: non_neg_integer(),
          success_count: non_neg_integer(),
          failure_threshold: pos_integer(),
          success_threshold: pos_integer(),
          timeout_ms: pos_integer(),
          opened_at: integer() | nil,
          half_open_calls: non_neg_integer(),
          half_open_max_calls: pos_integer()
        }

  # Client API

  @doc "Starts a circuit breaker for the given name."
  @spec start_link(atom(), keyword()) :: GenServer.on_start()
  def start_link(name, opts \\ []) do
    GenServer.start_link(__MODULE__, {name, opts}, name: via_tuple(name))
  end

  @doc "Ensures a circuit breaker is started (for lazy initialization)."
  @spec ensure_started(atom(), keyword()) :: :ok
  def ensure_started(name, opts \\ []) do
    case Registry.whereis_name({DataDiode.CircuitBreakerRegistry, name}) do
      nil ->
        case start_link(name, opts) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  @doc """
  Executes a function with circuit breaker protection.
  Returns {:ok, result} on success, {:error, reason} on failure.
  """
  @spec call(atom(), function(), keyword()) :: {:ok, any()} | {:error, term()}
  def call(name, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)

    # Ensure circuit breaker is started
    :ok = ensure_started(name)

    try do
      case GenServer.call(via_tuple(name), :execute, timeout) do
        :proceed ->
          # Execute the function
          result = fun.()
          GenServer.cast(via_tuple(name), {:success, result})
          {:ok, result}

        {:error, :circuit_open} ->
          # Circuit is open, reject immediately
          {:error, :circuit_open}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        # Function threw exception
        GenServer.cast(via_tuple(name), {:failure, Exception.message(e)})
        {:error, e}
    end
  end

  @doc "Gets the current state of the circuit breaker."
  @spec get_state(atom()) :: map()
  def get_state(name) do
    case Registry.whereis_name({DataDiode.CircuitBreakerRegistry, name}) do
      nil ->
        %{state: :not_started, error: "Circuit breaker not initialized"}

      pid ->
        GenServer.call(pid, :get_state)
    end
  end

  @doc "Resets the circuit breaker to closed state."
  @spec reset(atom()) :: :ok
  def reset(name) do
    case Registry.whereis_name({DataDiode.CircuitBreakerRegistry, name}) do
      nil -> :ok
      pid -> GenServer.cast(pid, :reset)
    end
  end

  # Server Callbacks

  @impl true
  def init({name, opts}) do
    state = %__MODULE__{
      name: name,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      success_threshold: Keyword.get(opts, :success_threshold, @default_success_threshold),
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms),
      opened_at: nil,
      half_open_calls: 0,
      half_open_max_calls: Keyword.get(opts, :half_open_max_calls, @default_half_open_max_calls)
    }

    Logger.info("CircuitBreaker[#{name}]: Started in closed state")
    {:ok, state}
  end

  @impl true
  def handle_call(:execute, _from, %{state: :open} = state) do
    # Check if we should transition to half_open
    now = System.monotonic_time(:millisecond)

    if now - state.opened_at >= state.timeout_ms do
      Logger.info("CircuitBreaker[#{state.name}]: Transitioning open → half_open")
      {:reply, :proceed, %{state | state: :half_open, half_open_calls: 0, success_count: 0}}
    else
      _remaining_ms = state.timeout_ms - (now - state.opened_at)
      {:reply, {:error, :circuit_open}, state}
    end
  end

  def handle_call(:execute, _from, %{state: :half_open, half_open_calls: max} = state)
      when max >= state.half_open_max_calls do
    # Too many calls in half_open state, prevent overload
    {:reply, {:error, :too_many_half_open_calls}, state}
  end

  def handle_call(:execute, _from, %{state: :half_open} = state) do
    # Allow the call to test if service has recovered
    {:reply, :proceed, %{state | half_open_calls: state.half_open_calls + 1}}
  end

  def handle_call(:execute, _from, %{state: :closed} = state) do
    # Normal operation, allow the call
    {:reply, :proceed, state}
  end

  def handle_call(:get_state, _from, state) do
    state_map = %{
      name: state.name,
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      opened_at: state.opened_at
    }

    {:reply, state_map, state}
  end

  @impl true
  def handle_cast({:success, _result}, %{state: :half_open} = state) do
    new_success_count = state.success_count + 1

    if new_success_count >= state.success_threshold do
      Logger.info("CircuitBreaker[#{state.name}]: Transitioning half_open → closed")
      {:noreply, reset_counts(state)}
    else
      {:noreply, %{state | success_count: new_success_count}}
    end
  end

  def handle_cast({:success, _result}, %{state: :closed} = state) do
    # Reset failure count on success in closed state
    {:noreply, %{state | failure_count: 0}}
  end

  def handle_cast({:failure, _reason}, %{state: :half_open} = state) do
    Logger.warning("CircuitBreaker[#{state.name}]: Failure in half_open, reopening")
    {:noreply, open_circuit(state)}
  end

  def handle_cast({:failure, _reason}, %{state: :closed} = state) do
    new_failure_count = state.failure_count + 1

    if new_failure_count >= state.failure_threshold do
      Logger.error(
        "CircuitBreaker[#{state.name}]: Failure threshold reached (#{state.failure_threshold}), opening circuit"
      )

      {:noreply, open_circuit(state)}
    else
      Logger.warning(
        "CircuitBreaker[#{state.name}]: Failure recorded (#{new_failure_count}/#{state.failure_threshold})"
      )

      {:noreply, %{state | failure_count: new_failure_count}}
    end
  end

  def handle_cast(:reset, state) do
    Logger.info("CircuitBreaker[#{state.name}]: Manual reset")
    {:noreply, reset_counts(state)}
  end

  # Private helpers

  defp open_circuit(state) do
    %{
      state
      | state: :open,
        failure_count: 0,
        success_count: 0,
        opened_at: System.monotonic_time(:millisecond)
    }
  end

  defp reset_counts(state) do
    %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        opened_at: nil,
        half_open_calls: 0
    }
  end

  defp via_tuple(name) do
    {:via, Registry, {DataDiode.CircuitBreakerRegistry, name}}
  end
end
