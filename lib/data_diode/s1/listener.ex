defmodule DataDiode.S1.Listener do
  @moduledoc """
  TCP Listener for S1. Accepts connections and spawns handlers.
  """
  use GenServer
  require Logger

  @default_port 8080

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  def port do
    case Process.whereis(__MODULE__) do
      nil -> nil
      pid -> GenServer.call(pid, :port)
    end
  end

  @impl true
  def init(:ok) do
    with {:ok, port} <- resolve_listen_port(),
         {:ok, socket} <- :gen_tcp.listen(port, listen_options()) do
      Logger.info("S1: Starting TCP Listener on port #{port}...")
      send(self(), :accept_loop)
      {:ok, socket}
    else
      {:error, {:invalid_port, v}} ->
        Logger.error("S1: Invalid LISTEN_PORT: #{inspect(v)}")
        {:stop, :invalid_port_value}
      {:error, reason} ->
        Logger.error("S1: Failed to listen: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:port, _from, socket) do
    {:reply, case :inet.port(socket) do {:ok, p} -> p; _ -> nil end, socket}
  end

  @impl true
  def handle_info(:accept_loop, listen_socket) do
    case :gen_tcp.accept(listen_socket, 500) do
      {:ok, client_socket} ->
        Logger.info("S1: New connection accepted.")
        DataDiode.S1.HandlerSupervisor.start_handler(client_socket)
        send(self(), :accept_loop)
        {:noreply, listen_socket}

      {:error, :timeout} ->
        send(self(), :accept_loop)
        {:noreply, listen_socket}

      {:error, reason} ->
        Logger.error("S1: Listener socket fatal error: #{inspect(reason)}. Terminating.")
        {:stop, reason, listen_socket}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("S1: Listener received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Helpers
  def listen_options(ip \\ nil) do
    base = [:binary, :inet, {:reuseaddr, true}, {:active, false}]
    case ip || Application.get_env(:data_diode, :s1_ip) do
      nil -> base
      :any -> base
      ip_str -> 
        case parse_ip(ip_str) do
          :any -> base
          addr -> [{:ip, addr} | base]
        end
    end
  end

  def parse_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, addr} -> addr
      _ -> Logger.warning("S1: Invalid LISTEN_IP #{ip}, using all interfaces."); :any
    end
  end
  def parse_ip(_), do: :any

  def resolve_listen_port do
    case Application.get_env(:data_diode, :s1_port, @default_port) do
      p when is_integer(p) and p >= 0 and p <= 65535 -> {:ok, p}
      p -> {:error, {:invalid_port, p}}
    end
  end
end
