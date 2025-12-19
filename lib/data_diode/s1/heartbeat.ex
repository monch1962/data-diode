defmodule DataDiode.S1.Heartbeat do
  @moduledoc """
  Generates a virtual heartbeat packet every 5 minutes to test the end-to-end path.
  """
  use GenServer
  require Logger

  @interval_ms 300_000 # 5 minutes
  @heartbeat_payload "HEARTBEAT"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    schedule_heartbeat()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:send_heartbeat, state) do
    Logger.debug("S1: Generating end-to-end heartbeat.")
    # We send it via the Encapsulator as if it were a local packet
    DataDiode.S1.Encapsulator.encapsulate_and_send("127.0.0.1", 0, @heartbeat_payload)
    
    schedule_heartbeat()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("S1 Heartbeat: Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :send_heartbeat, @interval_ms)
  end
end
