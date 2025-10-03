defmodule DataDiode.S2.Decapsulator do
  require Logger

  # --------------------------------------------------------------------------
  # API Function
  # --------------------------------------------------------------------------

  @doc """
  Processes a raw UDP packet buffer by decapsulating the metadata
  (IP, Port) and then writing the payload to storage.
  """
  def process_packet(raw_data) do
    # The expected header size is 4 bytes (IP) + 2 bytes (Port) = 6 bytes
    case byte_size(raw_data) do
      size when size < 6 ->
        Logger.warning("S2: Received malformed packet (size < 6). Dropping.")
        :malformed_packet

      _ ->
        # 1. Decapsulate the header using pattern matching on the binary
        # We assume the IP is IPv4: <<b1, b2, b3, b4>>
        # Port is a 16-bit unsigned integer: <<port::16>>
        case raw_data do
          <<b1, b2, b3, b4, port::16, payload::binary>> ->
            # 2. Reconstruct the IP address string
            ip_tuple = {b1, b2, b3, b4}
            # We use :inet.ntoa/1 to convert the tuple back to the display string
            src_ip_string = :inet.ntoa(ip_tuple)

            # 3. Simulate the security check and write to storage
            Logger.info(
              "S2: Decapsulated packet from #{src_ip_string}:#{port}. Payload size: #{byte_size(payload)} bytes."
            )

            # 🚨 CRITICAL DIODE LOGIC: This is the egress point.
            # In a real diode, data is passed to a high-assurance file writer
            # or a second network interface (the secure side).
            write_to_secure_storage(src_ip_string, port, payload)

          _ ->
            Logger.warning("S2: Received packet with invalid header structure. Dropping.")
            :invalid_header
        end
    end
  end

  # --------------------------------------------------------------------------
  # Secure Storage Simulation
  # --------------------------------------------------------------------------

  @doc "Simulates writing the data out to the secure environment."
  defp write_to_secure_storage(src_ip, src_port, payload) do
    # In a production environment, this would involve queuing data for
    # transmission across the physical data diode link.

    # Simulate writing data to a file on the secure side
    file_name = "data_#{System.os_time()}_#{src_port}.dat"

    # We log the action to show it succeeded
    Logger.debug(
      "S2: Successfully wrote #{byte_size(payload)} bytes to #{file_name}. (Simulated secure write)"
    )

    # For demonstration, we could write to a file, but we keep it simple here.
    # File.write(file_name, payload)

    :ok
  end
end
