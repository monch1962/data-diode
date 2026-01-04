defmodule DataDiode.S2.HeartbeatMonitor do
  @moduledoc """
  Monitors incoming heartbeats from S1 to verify the end-to-end channel.
  """
  use GenServer
  require Logger

  # Expect a heartbeat every 5 minutes + 1 minute grace period
  @default_timeout_ms 360_000

  @type state :: %{last_seen: integer()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec heartbeat_received(GenServer.server()) :: :ok
  def heartbeat_received(server \\ __MODULE__) do
    GenServer.cast(server, :heartbeat)
  end

  @impl true
  @spec init(:ok) :: {:ok, state(), timeout() | :infinity}
  def init(:ok) do
    timeout = get_timeout()
    {:ok, %{last_seen: System.monotonic_time()}, timeout}
  end

  @impl true
  @spec handle_cast(:heartbeat, state()) :: {:noreply, state(), timeout() | :infinity}
  def handle_cast(:heartbeat, state) do
    timeout = get_timeout()
    {:noreply, %{state | last_seen: System.monotonic_time()}, timeout}
  end

  @impl true
  @spec handle_info(:timeout | term(), state()) :: {:noreply, state(), timeout() | :infinity}
  def handle_info(:timeout, state) do
    timeout = get_timeout()

    Logger.error(
      "S2: Critical Failure! Channel heartbeat missing for > 6 minutes. The diode path may be obstructed."
    )

    # We continue monitoring and will log again if it remains timed out
    {:noreply, state, timeout}
  end

  @impl true
  @spec handle_info(term(), state()) :: {:noreply, state(), timeout() | :infinity}
  def handle_info(msg, state) do
    timeout = get_timeout()
    Logger.warning("S2 HeartbeatMonitor: Received unexpected message: #{inspect(msg)}")
    {:noreply, state, timeout}
  end

  @spec get_timeout() :: pos_integer()
  defp get_timeout do
    Application.get_env(:data_diode, :heartbeat_timeout_ms, @default_timeout_ms)
  end
end
