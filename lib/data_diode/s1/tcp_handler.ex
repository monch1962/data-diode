defmodule DataDiode.S1.TCPHandler do
  use GenServer
  require Logger

  @doc "Starts a new handler process for an accepted socket."
  # FIX: Options for GenServer.start_link must be in a list.
  # We remove the invalid name registration attempt and pass an empty list.
  def start_link(socket),
    do: GenServer.start_link(__MODULE__, socket, [])

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(socket) do
    # 1. Extract source IP and Port from the accepted socket
    case :inet.peername(socket) do
      {:ok, {src_ip_tuple, src_port}} ->
        # Robustly handle IP tuple conversion. We use a try/catch block to safely
        # convert the IP tuple to a string, handling :badarg (e.g., from IPv6)
        # gracefully by stopping the process instead of crashing.
        try do
          src_ip_string = :inet.ntoa(src_ip_tuple)

          Logger.info("S1: New connection from #{src_ip_string}:#{src_port}")

          # Set socket to receive data passively (:once) to manage backpressure
          :inet.setopts(socket, active: :once)

          {:ok, %{socket: socket, src_ip: src_ip_string, src_port: src_port}}
        catch
          :error, :badarg ->
            # If IP conversion fails, close the socket and stop the process.
            Logger.error(
              "S1: Fatal Address Conversion Error for #{inspect(src_ip_tuple)}. Closing socket."
            )

            :gen_tcp.close(socket)
            {:stop, :bad_address_format}
        end

      {:error, reason} ->
        # Handle failure to get peer name
        Logger.error(
          "S1: Failed to get peer name for new socket: #{inspect(reason)}. Closing socket."
        )

        :gen_tcp.close(socket)
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:tcp, _socket, raw_data}, state) do
    # Data received: Encapsulate and send via UDP to Service 2
    DataDiode.S1.Encapsulator.encapsulate_and_send(
      state.src_ip,
      state.src_port,
      raw_data
    )
    |> case do
      :ok -> Logger.debug("S1: Forwarded #{byte_size(raw_data)} bytes.")
      {:error, _} -> Logger.warning("S1: Failed to forward data.")
    end

    # Re-arm the socket to listen for the next packet
    :inet.setopts(state.socket, active: :once)
    {:noreply, state}
  end

  # IoT device closed the connection
  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("S1: Connection closed by #{state.src_ip}:#{state.src_port}")
    {:stop, :normal, state}
  end

  # Handle socket errors
  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.error("S1: TCP error for #{state.src_ip}:#{state.src_port}: #{inspect(reason)}")
    {:stop, :shutdown, state}
  end

  # --------------------------------------------------------------------------
  # Termination
  # --------------------------------------------------------------------------

  # Termination cleanup: ensure the TCP socket is closed
  @impl true
  def terminate(_reason, %{socket: socket, src_ip: src_ip}) do
    :gen_tcp.close(socket)
    Logger.info("S1: Handler terminated for #{src_ip}.")
    :ok
  end
end
