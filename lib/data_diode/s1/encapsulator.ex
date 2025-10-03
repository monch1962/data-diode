defmodule DataDiode.S1.Encapsulator do
  # Target is always localhost within the same Pod/Pi
  @s2_udp_target ~c'127.0.0.1'
  @s2_udp_port 8081
  require Logger

  @doc "Encapsulates data with source info and sends the binary over UDP to Service 2."
  def encapsulate_and_send(src_ip, src_port, payload) do
    # 1. Serialize the data structure using ETF
    udp_packet =
      :erlang.term_to_binary(%{
        src_ip: src_ip,
        src_port: src_port,
        payload: payload
      })

    # 2. Open a temporary socket
    case :gen_udp.open(0) do
      {:ok, socket} ->
        # 3. Send the UDP packet
        send_result = :gen_udp.send(socket, @s2_udp_target, @s2_udp_port, udp_packet)

        # 4. Close the socket
        :gen_udp.close(socket)

        # 5. Check send result and return status
        case send_result do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("S1 Encapsulator: Failed to send UDP packet: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("S1 Encapsulator: Failed to open UDP socket: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
