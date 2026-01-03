defmodule DataDiode.S1.TCPHandler do
  @moduledoc """
  Handles an individual TCP client connection on Service 1.
  Passes received data to the Encapsulator.
  """
  use GenServer, restart: :temporary
  require Logger

  # 1MB
  @max_packet_size 1_000_000

  # --------------------------------------------------------------------------
  # API
  # --------------------------------------------------------------------------

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(socket) do
    # Start in passive mode, then activate.
    send(self(), :activate)
    {:ok, %{socket: socket, src_ip: "unknown", src_port: 0}}
  end

  @impl true
  def handle_info(:activate, %{socket: socket} = state) do
    # Resolve source info once
    {src_ip, src_port} =
      case :inet.peername(socket) do
        {:ok, {ip, port}} -> {to_string(:inet.ntoa(ip)), port}
        _ -> {"unknown", 0}
      end

    case :inet.setopts(socket, active: :once) do
      :ok ->
        {:noreply, %{state | src_ip: src_ip, src_port: src_port}}

      {:error, reason} ->
        Logger.info("S1: Failed to activate handler: #{inspect(reason)}")
        :gen_tcp.close(socket)
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    if byte_size(data) > @max_packet_size do
      Logger.warning(
        "S1: Dropping oversized packet (#{byte_size(data)} bytes) from #{state.src_ip}"
      )
    else
      Logger.debug("S1: Processing #{byte_size(data)} bytes from #{state.src_ip}.")
      # Delegate to encapsulator
      target = encapsulator()

      if is_atom(target) and function_exported?(target, :encapsulate_and_send, 3) do
        target.encapsulate_and_send(state.src_ip, state.src_port, data)
      else
        GenServer.cast(target, {:send, state.src_ip, state.src_port, data})
      end
    end

    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("S1: Connection closed by #{state.src_ip}:#{state.src_port}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.error("S1: TCP error for #{state.src_ip}: #{inspect(reason)}")
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("S1: TCPHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp encapsulator do
    Application.get_env(:data_diode, :encapsulator, DataDiode.S1.Encapsulator)
  end
end
