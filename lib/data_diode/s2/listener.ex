defmodule DataDiode.S2.Listener do
  use GenServer
  require Logger

  # OpenTelemetry Tracing
  import OpenTelemetry.Tracer

  # Default port for Service 2 UDP reception
  @default_listen_port 42001

  @doc "Starts the Service 2 UDP Listener GenServer."
  @spec start_link(Keyword.t()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    # Use 'with' to pipeline startup steps (port resolution and socket binding).
    with {:ok, listen_port} <- resolve_listen_port(),
         # The listen address is set to {0, 0, 0, 0} to listen on all interfaces.
         {:ok, listen_socket} <- :gen_udp.open(listen_port, udp_options()) do
      Logger.info("S2: Starting UDP Listener on port #{listen_port}...")

      # The state will hold the socket. UDP sockets are usually set to :active true
      # or passive (:once) to receive data. We use :active true for simplicity here.
      {:ok, listen_socket}
    else
      {:error, {:invalid_port, port_str}} ->
        Logger.error(
          "S2: Invalid value for LISTEN_PORT_S2: \"#{port_str}\". Must be a valid port number. Exiting."
        )

        {:stop, :invalid_port_value}

      {:error, reason} ->
        # Handles failure from :gen_udp.open/2 (e.g., :eaddrinuse)
        Logger.error("S2: Failed to open UDP socket: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:udp, _socket, _ip, _port, packet}, listen_socket) do
    # Create a root span for the packet's journey through S2
    with_span "diode_s2_packet_received", [] do
      Logger.debug("S2: Received #{byte_size(packet)} bytes via UDP.")

      # Add useful attributes to the current span
      set_attributes(%{
        "diode.service" => "S2",
        "diode.protocol" => "udp",
        "diode.packet_size" => byte_size(packet)
      })

      # Delegate the packet processing to a Task under the supervisor
      # This ensures the UDP listener isn't blocked by processing logic.
      # We resolve the decapsulator module dynamically to allow mocking in tests.
      Task.Supervisor.start_child(DataDiode.S2.TaskSupervisor, fn ->
        decapsulator().process_packet(packet)
      end)
    end
    # The span ends here implicitly when with_span returns.

    {:noreply, listen_socket}
  end

  @impl true
  def handle_info({:udp_error, _socket, reason}, socket) do
    Logger.error("S2: UDP socket error: #{inspect(reason)}. Terminating.")
    {:stop, reason, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.warning("S2: Received unexpected message: #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl true
  def handle_info({:udp_passive, _socket}, socket) do
    # Re-enable active mode if we were using active: N
    :inet.setopts(socket, [active: :once])
    {:noreply, socket}
  end

  @impl true
  def handle_info({:udp_closed, _socket}, state) do
    Logger.warning("S2: UDP socket closed unexpectedly. Terminating.")
    {:stop, :shutdown, state}
  end

  @impl true
  def terminate(_reason, listen_socket) do
    :gen_udp.close(listen_socket)
    Logger.info("S2: Stopped UDP Listener.")
    :ok
  end

  # --------------------------------------------------------------------------
  # Internal Helper Functions
  # --------------------------------------------------------------------------

  @doc false
  # Helper to resolve the decapsulator module (allows mocking)
  defp decapsulator do
    Application.get_env(:data_diode, :decapsulator, DataDiode.S2.Decapsulator)
  end

  @doc false
  # Helper to resolve and validate the listen port from application config.
  def resolve_listen_port() do
    port = Application.get_env(:data_diode, :s2_port, @default_listen_port)
    {:ok, port}
  end

  @doc false
  # Helper to define socket options
  def udp_options() do
    opts = [
      :binary,
      # Set socket to actively receive messages
      {:active, true},
      {:reuseaddr, true}
    ]

    case Application.get_env(:data_diode, :s2_ip) do
      nil -> [{:ip, {0, 0, 0, 0}} | opts]
      ip_str ->
        case :inet.parse_address(String.to_charlist(ip_str)) do
          {:ok, ip_tuple} -> [{:ip, ip_tuple} | opts]
          {:error, _} ->
            Logger.warning("S2: Invalid LISTEN_IP_S2 #{ip_str}, falling back to all interfaces.")
            [{:ip, {0, 0, 0, 0}} | opts]
        end
    end
  end
end
