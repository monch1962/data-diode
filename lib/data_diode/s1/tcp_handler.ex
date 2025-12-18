defmodule DataDiode.S1.TCPHandler do
  use GenServer, restart: :temporary
  require Logger

  @doc "Starts a new handler process for an accepted socket."
  @spec start_link(:gen_tcp.socket()) :: {:ok, pid()} | {:error, term()}
  def start_link(socket),
    do: GenServer.start_link(__MODULE__, socket, [])

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(socket) do
    # Defer activation and metadata gathering until after the controlling_process handover.
    Logger.debug("S1: TCPHandler #{inspect(self())} init for socket #{inspect(socket)}")
    {:ok, %{socket: socket, src_ip: "unknown", src_port: 0}}
  end

  @impl true
  def handle_info(:activate, %{socket: socket} = state) do
    Logger.debug("S1: TCPHandler #{inspect(self())} activating socket #{inspect(socket)}")
    case :inet.peername(socket) do
      {:ok, {ip, port}} ->
        src_ip = :inet.ntoa(ip) |> to_string()
        # Now that we should have ownership, set active: :once
        case :inet.setopts(socket, [active: :once, mode: :binary]) do
          :ok ->
            {:noreply, %{state | src_ip: src_ip, src_port: port}}
          {:error, reason} when reason in [:einval, :enotconn, :closed] ->
            Logger.info("S1: Client disconnected before activation (setopts).")
            :gen_tcp.close(socket)
            {:stop, :normal, state}
          {:error, reason} ->
            Logger.error("S1: Failed to activate handler: #{inspect(reason)}. Closing socket.")
            :gen_tcp.close(socket)
            {:stop, reason, state}
        end

      {:error, reason} when reason in [:einval, :enotconn, :closed] ->
        Logger.info("S1: Client disconnected before activation (peername).")
        :gen_tcp.close(socket)
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error("S1: Could not get peername during activation: #{inspect(reason)}")
        :gen_tcp.close(socket)
        {:stop, reason, state}
    end
  end

  # OT Hardening: Limit max payload to 1MB to protect memory
  @max_payload_size 1_048_576

  @impl true
  def handle_info({:tcp, _socket, raw_data}, state) do
    # Data received: Encapsulate and send via UDP to Service 2
    binary_payload = IO.iodata_to_binary(raw_data)

    if byte_size(binary_payload) > @max_payload_size do
      Logger.warning("S1: Dropping oversized packet from #{state.src_ip} (#{byte_size(binary_payload)} bytes)")
      # Re-arm and continue
      :inet.setopts(state.socket, active: :once)
      {:noreply, state}
    else
      encapsulator().encapsulate_and_send(
      state.src_ip,
      state.src_port,
      binary_payload
    )

    Logger.info("S1: Forwarded #{byte_size(binary_payload)} bytes.")

      # Re-arm the socket to listen for the next packet
      :inet.setopts(state.socket, active: :once)
      {:noreply, state}
    end
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

  @impl true
  def handle_info(:accept_loop, state) do
    # This is actually handled by S1.Listener, but if it ends up here by accident (it shouldn't),
    # we just ignore it.
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("S1: TCPHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
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

  defp encapsulator do
    Application.get_env(:data_diode, :encapsulator, DataDiode.S1.Encapsulator)
  end
end
