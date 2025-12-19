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
          else
            write_to_secure_storage(src_ip, src_port, payload)
          end
          :ok

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

  # Parses the 6-byte header (4-byte IP, 2-byte port) from the payload.
  defp parse_header(<<ip_binary::binary-4, port::integer-unsigned-big-16, payload::binary>>) do
    case binary_to_ip(ip_binary) do
      {:ok, ip_string} ->
        {:ok, ip_string, port, payload}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fallback for packets that are too short to contain the header.
  defp parse_header(_packet) do
    {:error, :invalid_packet_size}
  end

  # Converts a 4-byte binary into an IP address string.
  defp binary_to_ip(<<a, b, c, d>>) do
    {:ok, "#{a}.#{b}.#{c}.#{d}"}
  end

  defp binary_to_ip(_) do
    {:error, :invalid_ip_binary}
  end

  # --------------------------------------------------------------------------
  # Secure Storage Simulation
  # --------------------------------------------------------------------------

  # Helper to simulate writing the data out to the secure environment.
  defp write_to_secure_storage(_src_ip, src_port, payload) do
    # Create a nested span to measure the latency of the "secure write" step
    with_span "diode_s2_secure_write", [] do
      # Simulate writing data to a file on the secure side
      file_name = generate_filename(src_port)

      # Add relevant attributes to the span
      set_attributes(%{
        "diode.write.filename" => file_name,
        "diode.write.bytes" => byte_size(payload)
      })

      # We log the action to show it succeeded
      Logger.debug(
        "S2: Successfully wrote #{byte_size(payload)} bytes to #{file_name}. (Simulated secure write)"
      )
    end
    # The span ends here.

    :ok
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
