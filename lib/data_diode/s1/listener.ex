defmodule DataDiode.S1.Listener do
  @moduledoc """
  TCP Listener for S1. Accepts connections and spawns handlers.
  """
  use GenServer
  require Logger

  alias DataDiode.NetworkHelpers
  alias DataDiode.ConfigHelpers

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
    {:reply,
     case :inet.port(socket) do
       {:ok, p} -> p
       _ -> nil
     end, socket}
  end

  @impl true
  def handle_info(:accept_loop, listen_socket) do
    case :gen_tcp.accept(listen_socket, 500) do
      {:ok, client_socket} ->
        Logger.info("S1: New connection accepted.")

        case DataDiode.S1.HandlerSupervisor.start_handler(client_socket) do
          {:ok, pid} -> :gen_tcp.controlling_process(client_socket, pid)
          _ -> :gen_tcp.close(client_socket)
        end

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
  @doc """
  Returns TCP listen options for the configured or provided IP address.
  """
  @spec listen_options(binary() | nil) :: [:gen_tcp.listen_option()]
  def listen_options(ip \\ nil) do
    NetworkHelpers.tcp_listen_options(ip || ConfigHelpers.s1_ip())
  end

  @doc """
  Resolves and validates the configured listen port.
  """
  @spec resolve_listen_port() :: {:ok, 0..65535} | {:error, {:invalid_port, any()}}
  def resolve_listen_port do
    NetworkHelpers.validate_port(ConfigHelpers.s1_port())
  end
end
