defmodule DataDiode.S2.Listener do
  use GenServer
  require Logger

  # Default port for receiving UDP packets from S1
  @default_listen_port 42001

  @doc "Starts the UDP Listener GenServer for Service 2."
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    # Use 'with' to pipeline startup steps (port resolution and socket listening).
    with {:ok, listen_port} <- resolve_listen_port(),
         {:ok, listen_socket} <- :gen_udp.open(listen_port, listen_options()) do
      Logger.info("S2: Starting UDP Listener on port #{listen_port}...")

      # SUCCESS: Must return {:ok, state}
      {:ok, listen_socket}
    else
      {:error, {:invalid_port, port_str}} ->
        Logger.error(
          "S2: Invalid value for LISTEN_PORT_S2: \"#{port_str}\". Must be a valid port number. Exiting."
        )

        {:stop, :invalid_port_value}

      {:error, reason} ->
        # Handles failure from :gen_udp.open/2
        Logger.error("S2: Failed to listen: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:udp, socket, _sender_ip, _sender_port, raw_data}, socket) do
    # Data received! Delegate processing to the Decapsulator.
    DataDiode.S2.Decapsulator.process_packet(raw_data)

    # Note: We do not need to re-arm the UDP socket as it is set to :active, true by default.
    {:noreply, socket}
  end

  # Handle socket errors
  @impl true
  def handle_info({:udp_error, socket, reason}, socket) do
    Logger.error("S2: UDP error: #{inspect(reason)}")
    # Log the error but keep the GenServer running unless the error is fatal.
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    :gen_udp.close(socket)
    Logger.info("S2: Stopped UDP Listener.")
    :ok
  end

  # --------------------------------------------------------------------------
  # Internal Helper Functions
  # --------------------------------------------------------------------------

  @doc false
  # Helper to resolve and validate the listen port from environment variables.
  defp resolve_listen_port() do
    # Use a different ENV variable name to avoid conflict with S1
    case System.get_env("LISTEN_PORT_S2") do
      nil ->
        {:ok, @default_listen_port}

      port_str ->
        case Integer.parse(port_str) do
          {port, ""} when is_integer(port) and port > 0 ->
            {:ok, port}

          _ ->
            {:error, {:invalid_port, port_str}}
        end
    end
  end

  @doc false
  # Helper to define UDP socket options
  defp listen_options() do
    [
      :binary,
      # Active mode: data packets are sent as messages to the GenServer
      {:active, true},
      # Listen on all interfaces
      {:ip, {0, 0, 0, 0}},
      {:reuseaddr, true}
    ]
  end
end
