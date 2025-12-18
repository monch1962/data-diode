defmodule DataDiode.S2.HeartbeatMonitor do
  @moduledoc """
  Monitors incoming heartbeats from S1 to verify the end-to-end channel.
  """
  use GenServer
  require Logger

  # Expect a heartbeat every 5 minutes + 1 minute grace period
  @timeout_ms 360_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def heartbeat_received do
    GenServer.cast(__MODULE__, :heartbeat)
  end

  @impl true
  def init(:ok) do
    {:ok, %{last_seen: System.monotonic_time()}, @timeout_ms}
  end

  @impl true
  def handle_cast(:heartbeat, state) do
    {:noreply, %{state | last_seen: System.monotonic_time()}, @timeout_ms}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.error("S2: Critical Failure! Channel heartbeat missing for > 6 minutes. The diode path may be obstructed.")
    # We continue monitoring and will log again if it remains timed out
    {:noreply, state, @timeout_ms}
  end
end
