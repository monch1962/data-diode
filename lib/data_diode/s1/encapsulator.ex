defmodule DataDiode.S1.Encapsulator do
  @moduledoc """
  Encapsulates TCP packets with source metadata and forwards to Service 2.

  Implements:
  * Protocol whitelisting via Deep Packet Inspection (DPI)
  * Continuous token bucket rate limiting
  * Packet encapsulation with source IP/port
  * CRC32 integrity checksums

  All packets are sent via UDP to Service 2 (127.0.0.1:42001 by default).
  """

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
    target =
      case Process.whereis(@name) do
        nil -> @name
        pid -> pid
      end

    GenServer.cast(target, {:send, src_ip, src_port, payload})
  end

  @doc "Updates the destination port (S2) dynamically."
  def set_dest_port(port) do
    GenServer.cast(@name, {:set_dest_port, port})
  end

  @doc "Updates the rate limit (packets per second) dynamically."
  def set_rate_limit(limit) do
    GenServer.cast(@name, {:set_limit, limit})
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
        limit = resolve_rate_limit()

        {:ok,
         %{
           socket: socket,
           dest_port: s2_port,
           tokens: limit,
           limit: limit,
           last_refill: System.monotonic_time(:millisecond)
         }}

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
    state = refill_tokens(state)

    cond do
      state.tokens <= 0 ->
        DataDiode.Metrics.inc_errors()

        if rem(System.unique_integer([:positive]), 100) == 0 do
          Logger.warning("S1 Encapsulator: Rate limit exceeded, dropping packets.")
        end

        {:noreply, state}

      not protocol_allowed?(payload) ->
        DataDiode.Metrics.inc_errors()
        Logger.warning("S1 Encapsulator: Protocol guard blocked packet from #{src_ip}.")
        {:noreply, %{state | tokens: state.tokens - 1}}

      true ->
        # 2. Convert IP
        case ip_to_binary(src_ip) do
          {:ok, ip_binary} ->
            # 3. Construct packet with CRC32 checksum
            header_payload =
              <<ip_binary::binary-4, src_port::integer-unsigned-big-16, payload::binary>>

            checksum = :erlang.crc32(header_payload)
            final_packet = <<header_payload::binary, checksum::integer-unsigned-big-32>>

            # 4. Send using existing socket
            case :gen_udp.send(state.socket, @s2_udp_target, state.dest_port, final_packet) do
              :ok ->
                DataDiode.Metrics.inc_packets()
                # Success
                :ok

              {:error, reason} ->
                DataDiode.Metrics.inc_errors()
                Logger.warning("S1 Encapsulator: Failed to send packet: #{inspect(reason)}")
            end

          {:error, :invalid_ip} ->
            DataDiode.Metrics.inc_errors()
            Logger.warning("S1 Encapsulator: Invalid IP #{src_ip}, dropping packet.")
        end

        {:noreply, %{state | tokens: state.tokens - 1}}
    end
  end

  @impl true
  def handle_cast({:set_limit, limit}, state) do
    {:noreply,
     %{state | limit: limit, tokens: limit, last_refill: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_cast({:set_dest_port, port}, state) do
    {:noreply, %{state | dest_port: port}}
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
      Logger.warning(
        "S1 Encapsulator: Invalid S2_PORT #{inspect(port)}, using default #{@s2_udp_port}"
      )

      @s2_udp_port
    end
  end

  defp resolve_rate_limit do
    Application.get_env(:data_diode, :max_packets_per_sec, 1000)
  end

  defp refill_tokens(state) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - state.last_refill

    # Calculate tokens to add based on elapsed time
    # Rate is tokens per 1000ms (1 second)
    tokens_to_add = trunc(elapsed_ms * state.limit / 1000)

    if tokens_to_add > 0 do
      new_tokens = min(state.limit, state.tokens + tokens_to_add)
      %{state | tokens: new_tokens, last_refill: now}
    else
      state
    end
  end

  defp protocol_allowed?(payload) do
    # DPI / Protocol Guarding
    # Allow-list via environment variable
    # If list is empty or nil or contains :any, we allow all.
    case Application.get_env(:data_diode, :protocol_allow_list) do
      nil ->
        true

      [] ->
        true

      list when is_list(list) ->
        if :any in list do
          true
        else
          Enum.any?(list, fn proto_atom ->
            DataDiode.ProtocolDefinitions.matches?(proto_atom, payload)
          end)
        end

      _ ->
        true
    end
  end
end
