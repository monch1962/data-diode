defmodule DataDiode.S2.Decapsulator do
  require Logger

  # OpenTelemetry Tracing
  import OpenTelemetry.Tracer

  # --------------------------------------------------------------------------
  # API Function
  # --------------------------------------------------------------------------

  @doc "Decapsulates a UDP packet to extract the original TCP payload and metadata."
  @callback process_packet(binary()) :: :ok | {:error, term()}
  @spec process_packet(binary()) :: :ok | {:error, term()}
  def process_packet(packet) do
    # Start a nested span for parsing the raw packet header
    with_span "diode_s2_parse_header", [] do
      case parse_header(packet) do
        {:ok, src_ip, src_port, payload} ->
          set_attributes(%{
            "diode.source_ip" => src_ip,
            "diode.source_port" => src_port
          })
          Logger.info("S2: Decapsulated packet from #{src_ip}:#{src_port}. Payload size: #{byte_size(payload)} bytes.")
          
          if payload == "HEARTBEAT" do
            DataDiode.S2.HeartbeatMonitor.heartbeat_received()
            :ok
          else
            write_to_secure_storage(src_ip, src_port, payload)
          end

        {:error, reason} ->
          DataDiode.Metrics.inc_errors()
          record_exception(%RuntimeError{message: to_string(reason)}) # Record exception in the span
          Logger.error("S2: Failed to parse header: #{reason}")
          {:error, reason}
      end
    end
  end

  # --------------------------------------------------------------------------
  # Internal Parsing Logic
  # --------------------------------------------------------------------------

  # Parses the 10-byte+ packet (4-byte IP, 2-byte port, payload, 4-byte CRC).
  def parse_header(packet) when byte_size(packet) >= 10 do
    # Format: <<IP(4), Port(2), Payload(N), Checksum(4)>>
    size = byte_size(packet)
    payload_size = size - 6 - 4
    <<header_payload::binary-size(payload_size + 6), checksum::integer-unsigned-big-32>> = packet

    # Verify integrity
    if :erlang.crc32(header_payload) == checksum do
      <<ip_binary::binary-4, port::integer-unsigned-big-16, payload::binary>> = header_payload
      case binary_to_ip(ip_binary) do
        {:ok, ip_string} -> {:ok, ip_string, port, payload}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :integrity_check_failed}
    end
  end

  # Fallback for packets that are too short to contain the header + checksum.
  def parse_header(_packet) do
    {:error, :invalid_packet_size_or_missing_checksum}
  end

  # Converts a 4-byte binary into an IP address string.
  defp binary_to_ip(<<a, b, c, d>>) do
    {:ok, "#{a}.#{b}.#{c}.#{d}"}
  end


  # --------------------------------------------------------------------------
  # Secure Storage Logic (Hardened)
  # --------------------------------------------------------------------------

  # Helper to simulate writing the data out to the secure environment using an atomic pattern.
  defp write_to_secure_storage(_src_ip, src_port, payload) do
    # Create a nested span to measure the latency of the "secure write" step
    with_span "diode_s2_secure_write", [] do
      file_name = generate_filename(src_port)
      temp_name = file_name <> ".tmp"

      # Add relevant attributes to the span
      set_attributes(%{
        "diode.write.filename" => file_name,
        "diode.write.bytes" => byte_size(payload)
      })

      # Hardening: Atomic Write Pattern (Write to .tmp then Rename)
      case File.write(temp_name, payload) do
        :ok ->
          case File.rename(temp_name, file_name) do
            :ok ->
              Logger.debug("S2: Atomic write successful: #{file_name}")
              :ok
            {:error, reason} ->
              Logger.error("S2: Atomic rename failed for #{file_name}: #{inspect(reason)}")
              # Cleanup partial file if possible
              File.rm(temp_name)
              {:error, reason}
          end
        {:error, reason} ->
          Logger.error("S2: Secure write failed for #{temp_name}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp generate_filename(port) do
    # OT Hardening: Add unique integer to ensure no collisions even if clock jumps back
    unique = System.unique_integer([:positive, :monotonic])
    Path.join(data_dir(), "data_#{:os.system_time(:millisecond)}_#{unique}_#{port}.dat")
  end

  def data_dir do
    case Application.fetch_env(:data_diode, :data_dir) do
      {:ok, nil} -> "."
      {:ok, dir} -> dir
      :error -> "."
    end
  end
end
