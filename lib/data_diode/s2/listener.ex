defmodule DataDiode.S2.Listener do
  use GenServer
  require Logger

  # Default port for Service 2 UDP reception
  @default_listen_port 42001

  @doc "Starts the Service 2 UDP Listener GenServer."
  # 🚨 FIX: Add the missing start_link/0 function required by the supervisor.
  def start_link(), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

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
  # Handle incoming UDP packets: {:udp, socket, address, port, data}
  def handle_info({:udp, _socket, _src_ip_tuple, _src_port, raw_data}, state) do
    # Delegate the decapsulation and processing to the Decapsulator module
    # Note: The Decapsulator expects data encapsulated with a header,
    # but for a real-world proxy, the header is added by S1.

    # We ignore the UDP source address here, as the *original* TCP source IP/Port
    # must be extracted from the raw_data header itself, added by S1.

    DataDiode.S2.Decapsulator.process_packet(raw_data)

    {:noreply, state}
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
  # Helper to resolve and validate the listen port from environment variables.
  defp resolve_listen_port() do
    case System.get_env("LISTEN_PORT_S2") do
      nil ->
        # Default port
        {:ok, @default_listen_port}

      port_str ->
        # Safely try to parse the string to an integer
        case Integer.parse(port_str) do
          # Check that it's a valid integer and greater than 0
          {port, ""} when is_integer(port) and port > 0 ->
            {:ok, port}

          _ ->
            # Return an error tuple specific to this failure for the 'with' block
            {:error, {:invalid_port, port_str}}
        end
    end
  end

  @doc false
  # Helper to define socket options
  defp udp_options() do
    [
      :binary,
      # Set socket to actively receive messages
      {:active, true},
      {:reuseaddr, true},
      # Listen on all interfaces
      {:ip, {0, 0, 0, 0}}
    ]
  end
end
