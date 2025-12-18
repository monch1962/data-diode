defmodule DataDiode.S1.Listener do
  use GenServer
  require Logger
  # OpenTelemetry Tracing
  import OpenTelemetry.Tracer

  # Default port if the environment variable is not set
  @default_listen_port 8080

  @doc "Starts the TCP Listener GenServer."
  @spec start_link(Keyword.t()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  # --------------------------------------------------------------------------
  # GenServer Callbacks
  # --------------------------------------------------------------------------

  @doc "Returns the port the listener is bound to."
  @spec port() :: :inet.port_number() | nil
  def port() do
    GenServer.call(__MODULE__, :get_port)
  end

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
  def handle_call(:get_port, _from, listen_socket) do
    case :inet.port(listen_socket) do
      {:ok, port} -> {:reply, port, listen_socket}
      _ -> {:reply, nil, listen_socket}
    end
  end

  @impl true
  def handle_info(:accept_loop, listen_socket) do
    # Use a timeout to allow the GenServer to process other messages (like sys.get_state)
    case :gen_tcp.accept(listen_socket, 200) do
      {:ok, client_socket} ->
        Logger.info("S1: New connection accepted.")
        case DataDiode.S1.HandlerSupervisor.start_handler(client_socket) do
          {:ok, pid} ->
            case :gen_tcp.controlling_process(client_socket, pid) do
              :ok ->
                send(pid, :activate)
              {:error, reason} ->
                Logger.error("S1: Failed to transfer socket ownership: #{inspect(reason)}")
                :gen_tcp.close(client_socket)
            end
          _ ->
            :gen_tcp.close(client_socket)
        end
        send(self(), :accept_loop)
        {:noreply, listen_socket}

      {:error, :timeout} ->
        send(self(), :accept_loop)
        {:noreply, listen_socket}

      {:error, reason} when reason in [:closed, :ebadf, :enotsock] ->
        Logger.error("S1: Listener socket fatal error: #{inspect(reason)}. Terminating for restart.")
        {:stop, reason, listen_socket}

      {:error, reason} ->
        Logger.warning("S1: TCP accept error: #{inspect(reason)}. Continuing loop.")
        send(self(), :accept_loop)
        {:noreply, listen_socket}
    end
  end

  # Catch-all for unexpected messages (e.g. late tcp_closed from a handed-over socket)
  @impl true
  def handle_info(msg, listen_socket) do
    Logger.debug("S1: Listener received unexpected message: #{inspect(msg)}")
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
  # Helper to resolve and validate the listen port from application config.
  def resolve_listen_port() do
    port = Application.get_env(:data_diode, :s1_port, @default_listen_port)
    {:ok, port}
  end

  @doc false
  # Helper to define socket options
  def listen_options() do
    opts = [
      :binary,
      :inet,
      # Allows quick restart on the same port
      {:reuseaddr, true},
      # Passive mode ensures we don't get flooded before handover
      {:active, false}
      # All other options are usually configured *after* the socket is accepted.
    ]

    case Application.get_env(:data_diode, :s1_ip) do
      nil -> opts
      ip_str ->
        case :inet.parse_address(String.to_charlist(ip_str)) do
          {:ok, ip_tuple} -> [{:ip, ip_tuple} | opts]
          {:error, _} -> 
            Logger.warning("S1: Invalid LISTEN_IP #{ip_str}, falling back to all interfaces.")
            opts
        end
    end
  end
end
