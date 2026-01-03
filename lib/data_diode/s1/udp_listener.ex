defmodule DataDiode.S1.UDPListener do
  @moduledoc """
  UDP Listener for Service 1.
  Accepts UDP packets and forwards them to the Encapsulator.
  """
  use GenServer
  require Logger

  alias DataDiode.ConfigHelpers
  alias DataDiode.NetworkHelpers

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    encapsulator = Keyword.get(opts, :encapsulator, DataDiode.S1.Encapsulator)

    case resolve_listen_port() do
      {:ok, nil} ->
        Logger.info("S1 UDP: No port configured, UDP Ingress disabled.")
        :ignore

      {:ok, port} ->
        case :gen_udp.open(port, listen_options()) do
          {:ok, socket} ->
            Logger.info("S1 UDP: Starting UDP Listener on port #{port}...")
            {:ok, %{socket: socket, encapsulator: encapsulator}}

          {:error, reason} ->
            Logger.error("S1 UDP: Failed to listen on port #{port}: #{inspect(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        Logger.error("S1 UDP: Configuration error: #{inspect(reason)}")
        {:stop, :invalid_config}
    end
  end

  @impl true
  def handle_info({:udp, _socket, ip, port, data}, state) do
    src_ip = NetworkHelpers.ip_to_string(ip)

    # Forward to configured Encapsulator
    # Check if we should call the module function or use the pid/name
    if is_atom(state.encapsulator) and
         function_exported?(state.encapsulator, :encapsulate_and_send, 3) do
      state.encapsulator.encapsulate_and_send(src_ip, port, data)
    else
      GenServer.cast(state.encapsulator, {:send, src_ip, port, data})
    end

    # Re-arm
    :inet.setopts(state.socket, active: :once)
    {:noreply, state}
  end

  @impl true
  def handle_info({:udp_closed, _socket}, state) do
    Logger.error("S1 UDP: Listener socket closed unexpectedly.")
    {:stop, :udp_closed, state}
  end

  @impl true
  def handle_info({:udp_error, _socket, reason}, state) do
    Logger.error("S1 UDP: Socket error: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("S1 UDP: Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Helpers
  @spec listen_options() :: [:gen_udp.option()]
  defp listen_options do
    NetworkHelpers.udp_listen_options(ConfigHelpers.s1_ip())
  end

  @spec resolve_listen_port() :: {:ok, 0..65_535 | nil} | {:error, {:invalid_port, any()}}
  defp resolve_listen_port do
    case ConfigHelpers.s1_udp_port() do
      nil -> {:ok, nil}
      port -> NetworkHelpers.validate_port(port)
    end
  end
end
