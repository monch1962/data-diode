defmodule DataDiode.S1.Encapsulator do
  use GenServer
  require Logger

  @name __MODULE__
  # Target is always localhost within the same Pod/Pi
  @s2_udp_target {127, 0, 0, 1}
  # Default, but will be overridden by env var
  @s2_udp_port 42001

  # --------------------------------------------------------------------------
  # API
  # --------------------------------------------------------------------------

  @doc "Starts the Encapsulator GenServer."
  @spec start_link(Keyword.t()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, @name))

  @doc """
  Encapsulates data with source info and sends the binary over UDP to Service 2.
  This is now a fire-and-forget cast for performance.
  """
  @callback encapsulate_and_send(String.t(), :inet.port_number(), binary()) :: :ok
  @spec encapsulate_and_send(String.t(), :inet.port_number(), binary()) :: :ok
  def encapsulate_and_send(src_ip, src_port, payload) do
    # Try to find the process by name, defaulting to @name
    target = case Process.whereis(@name) do
      nil -> @name
      pid -> pid
    end
    GenServer.cast(target, {:send, src_ip, src_port, payload})
  end

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    # 1. Open a single UDP socket for the lifetime of this process.
    #    We bind to port 0 (ephemeral).
    case :gen_udp.open(0) do
      {:ok, socket} ->
        s2_port = resolve_s2_port()
        {:ok, %{socket: socket, dest_port: s2_port}}

      {:error, reason} ->
        Logger.error("S1 Encapsulator: Failed to open UDP socket: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("S1 Encapsulator: Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send, src_ip, src_port, payload}, state) do
    # 2. Convert IP
    case ip_to_binary(src_ip) do
      {:ok, ip_binary} ->
        # 3. Construct packet
        udp_packet = <<ip_binary::binary-4, src_port::integer-unsigned-big-16, payload::binary>>

        # 4. Send using existing socket
        case :gen_udp.send(state.socket, @s2_udp_target, state.dest_port, udp_packet) do
          :ok ->
            DataDiode.Metrics.inc_packets()
            :ok # Success
          {:error, reason} ->
            DataDiode.Metrics.inc_errors()
            Logger.warning("S1 Encapsulator: Failed to send packet: #{inspect(reason)}")
        end

      {:error, :invalid_ip} ->
        DataDiode.Metrics.inc_errors()
        Logger.warning("S1 Encapsulator: Invalid IP #{src_ip}, dropping packet.")
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------

  defp ip_to_binary(ip) when is_binary(ip) do
    ip
    |> String.to_charlist()
    |> ip_to_binary()
  end

  defp ip_to_binary(ip_charlist) do
    case :inet.parse_address(ip_charlist) do
      {:ok, {a, b, c, d}} -> {:ok, <<a, b, c, d>>}
      _ -> {:error, :invalid_ip}
    end
  end

  defp resolve_s2_port() do
    port = Application.get_env(:data_diode, :s2_port, @s2_udp_port)
    if is_integer(port) and port > 0 and port <= 65535 do
      port
    else
      Logger.warning("S1 Encapsulator: Invalid S2_PORT #{inspect(port)}, using default #{@s2_udp_port}")
      @s2_udp_port
    end
  end
end
