defmodule DataDiode.S1.Encapsulator do
  # Target is always localhost within the same Pod/Pi
  @s2_udp_target {127, 0, 0, 1}
  @s2_udp_port 42001 # Default, but will be overridden by env var
  require Logger

    @doc "Encapsulates data with source info and sends the binary over UDP to Service 2."
  def encapsulate_and_send(src_ip, src_port, payload) do
    # Resolve the target port from environment variables, with a default.
    s2_port = resolve_s2_port()

    # 1. Convert the source IP string to a 4-byte binary format.
    with {:ok, ip_binary} <- ip_to_binary(src_ip),
         # 2. Open a temporary UDP socket.
         {:ok, socket} <- :gen_udp.open(0) do
      # 3. Construct the custom packet: 4-byte IP, 2-byte Port, then payload.
      # The port is an unsigned, big-endian 16-bit integer.
      udp_packet = <<ip_binary::binary-4, src_port::integer-unsigned-big-16, payload::binary>>
      Logger.debug("S1 Encapsulator: UDP packet to send: #{inspect(udp_packet)} (is_binary: #{is_binary(udp_packet)})")

      # 4. Send the UDP packet to the configured S2 target.
      send_result = :gen_udp.send(socket, @s2_udp_target, s2_port, udp_packet)

      # 5. Close the socket immediately after sending.
      :gen_udp.close(socket)

      # 6. Return :ok or an error tuple based on the send result.
      case send_result do
        :ok ->
          :ok
        {:error, reason} ->
          Logger.error("S1 Encapsulator: Failed to send UDP packet: #{inspect(reason)}")
          {:error, reason}
      end
    else
      # Handle failure to open the socket.
      {:error, :econnrefused} ->
        Logger.error("S1 Encapsulator: UDP connection refused. Is Service 2 running?")
        {:error, :econnrefused}

      # Handle failure to convert the IP address.
      {:error, :invalid_ip} ->
        Logger.error("S1 Encapsulator: Could not convert IP address string: #{src_ip}")
        {:error, :invalid_ip}
        
      # Catch-all for other errors during setup.
      {:error, reason} ->
        Logger.error("S1 Encapsulator: Failed to open UDP socket: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper to convert an IP address string (e.g., "127.0.0.1") to a 4-byte binary.
  defp ip_to_binary(ip_charlist) do
    case :inet.parse_address(ip_charlist) do
      {:ok, {a, b, c, d}} -> {:ok, <<a, b, c, d>>}
      _ -> {:error, :invalid_ip}
    end
  end
  
  # Helper to resolve the S2 port from environment variables.
  defp resolve_s2_port() do
    case System.get_env("LISTEN_PORT_S2") do
      nil -> @s2_udp_port
      port_str ->
        case Integer.parse(port_str) do
          {port, ""} when port > 0 -> port
          _ -> @s2_udp_port
        end
    end
  end
end
