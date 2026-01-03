defmodule DataDiode.S2.Listener do
  @moduledoc """
  Listener for Service 2, waiting for encapsulated UDP packets from Service 1.
  """
  use GenServer
  require Logger

  alias DataDiode.ConfigHelpers
  alias DataDiode.NetworkHelpers

  @spec start_link(keyword()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Resolves the UDP listen port for Service 2.
  """
  @spec resolve_listen_port() :: {:ok, non_neg_integer()} | {:error, {:invalid_port, any()}}
  def resolve_listen_port do
    NetworkHelpers.validate_port(ConfigHelpers.s2_port())
  end

  @impl true
  def init(:ok) do
    with {:ok, listen_port} <- resolve_listen_port(),
         {:ok, socket} <- :gen_udp.open(listen_port, udp_options()) do
      Logger.info("S2: Starting UDP Listener on port #{listen_port}...")
      {:ok, socket}
    else
      {:error, {:invalid_port, port_str}} ->
        Logger.error("S2: Invalid value for LISTEN_PORT: \"#{port_str}\". Exiting.")
        {:stop, :invalid_port_value}

      {:error, reason} ->
        Logger.error("S2: Failed to open UDP socket: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:udp, _socket, _ip, _port, data}, socket) do
    # Heavy processing offloaded to Task to keep listener responsive
    case Task.Supervisor.start_child(DataDiode.S2.TaskSupervisor, fn ->
           decapsulator().process_packet(data)
         end) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        DataDiode.Metrics.inc_errors()
        Logger.error("S2: Failed to spawn processing task: #{inspect(reason)}. Packet dropped.")
    end

    # Re-arm socket for next packet
    :inet.setopts(socket, active: :once)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:udp_closed, socket}, _state) do
    Logger.error("S2: UDP Listener socket closed unexpectedly. Terminating.")
    {:stop, :udp_closed, socket}
  end

  @impl true
  def handle_info({:udp_passive, socket}, socket) do
    # Explicitly re-arm if we hit passive limit
    :inet.setopts(socket, active: :once)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:udp_error, socket, reason}, socket) do
    Logger.error("S2: UDP socket error: #{inspect(reason)}")
    {:stop, reason, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.warning("S2: Received unexpected message: #{inspect(msg)}")
    {:noreply, socket}
  end

  @doc false
  # Helper to define UDP socket options
  @spec udp_options() :: [:gen_udp.option()]
  def udp_options do
    NetworkHelpers.udp_listen_options(ConfigHelpers.s2_ip())
  end

  defp decapsulator do
    Application.get_env(:data_diode, :decapsulator, DataDiode.S2.Decapsulator)
  end
end
