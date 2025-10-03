defmodule DataDiode.S1.Listener do
  use GenServer
  require Logger

  # Default port if the environment variable is not set
  @default_listen_port 8080

  @doc "Starts the TCP Listener GenServer."
  # The final correct function signature for the zero-arity call
  def start_link(), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    # Use 'with' to pipeline startup steps (port resolution and socket listening).
    with {:ok, listen_port} <- resolve_listen_port(),
         {:ok, listen_socket} <- :gen_tcp.listen(listen_port, listen_options()) do
      Logger.info("S1: Starting TCP Listener on port #{listen_port}...")

      # Start the non-blocking accept loop
      send(self(), :accept_loop)

      # SUCCESS: Final guaranteed return from init/1
      {:ok, listen_socket}
    else
      {:error, {:invalid_port, port_str}} ->
        Logger.error(
          "S1: Invalid value for LISTEN_PORT: \"#{port_str}\". Must be a valid port number. Exiting."
        )

        {:stop, :invalid_port_value}

      {:error, reason} ->
        # Handles failure from :gen_tcp.listen/2 (e.g., :eaddrinuse, or the final :badarg)
        Logger.error("S1: Failed to listen: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept_loop, listen_socket) do
    # Use :gen_tcp.accept/1 for the non-blocking loop
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # Successfully accepted a connection. Start a new handler process.
        DataDiode.S1.TCPHandler.start_link(client_socket)

      # :eagain means no connection is ready; this is normal
      {:error, :eagain} ->
        :ok

      {:error, reason} ->
        Logger.error("S1: Error accepting connection: #{inspect(reason)}")
    end

    # Schedule the next check immediately
    send(self(), :accept_loop)
    {:noreply, listen_socket}
  end

  @impl true
  def terminate(_reason, listen_socket) do
    :gen_tcp.close(listen_socket)
    Logger.info("S1: Stopped TCP Listener.")
    :ok
  end

  # --------------------------------------------------------------------------
  # Internal Helper Functions
  # --------------------------------------------------------------------------

  @doc false
  # Helper to resolve and validate the listen port from environment variables.
  defp resolve_listen_port() do
    case System.get_env("LISTEN_PORT") do
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
  defp listen_options() do
    [
      # Required for IPv4 resolution (Crucial fix from earlier)
      :inet,
      # Allows quick restart on the same port
      {:reuseaddr, true}
      # All other options are usually configured *after* the socket is accepted.
    ]
  end
end
