defmodule DataDiode.S1.HandlerSupervisor do
  @moduledoc """
  Dynamic supervisor for TCP connection handlers on Service 1.

  Manages a pool of temporary TCPHandler processes, one per active connection.
  Implements OT hardening by limiting concurrent connections to prevent memory
  exhaustion on resource-constrained hardware (e.g., Raspberry Pi).
  """

  use DynamicSupervisor

  @name __MODULE__

  @spec start_link(term()) :: {:ok, pid()} | {:error, term()}
  def start_link(_init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, [], name: @name)
  end

  @spec start_handler(:gen_tcp.socket()) :: DynamicSupervisor.on_start_child()
  def start_handler(client_socket) do
    # Specify the child spec for the worker (TCPHandler)
    spec = {DataDiode.S1.TCPHandler, client_socket}
    DynamicSupervisor.start_child(@name, spec)
  end

  @impl true
  def init(_init_arg) do
    # OT Hardening: Limit concurrent connections to avoid memory exhaustion on Pi.
    # Also set Intensity/Period to be more resilient to load spikes.
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: 100,
      intensity: 10,
      period: 5
    )
  end
end
