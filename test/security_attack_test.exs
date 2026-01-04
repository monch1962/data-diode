defmodule DataDiode.SecurityAttackTest do
  @moduledoc """
  Security Attack Simulation Suite mapped to MITRE ATT&CK Techniques.
  Verifies robustness against malicious scenarios.
  """
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  setup do
    Application.ensure_all_started(:data_diode)
    DataDiode.S1.Encapsulator.set_rate_limit(1000)

    # Reset RateLimiter state for common test IPs to avoid test pollution
    ["1.2.3.4", "10.0.0.1", "1.1.1.1"]
    |> Enum.each(fn ip -> DataDiode.RateLimiter.reset_ip(ip) end)

    on_exit(fn ->
      # Clean up environment to avoid polluting other tests
      Application.delete_env(:data_diode, :protocol_allow_list)
      Application.delete_env(:data_diode, :s1_port)
      Application.delete_env(:data_diode, :s2_port)
      Application.delete_env(:data_diode, :max_packets_per_sec)

      # Reset metrics to clean state
      if Process.whereis(DataDiode.Metrics) do
        DataDiode.Metrics.reset_stats()
      end
    end)

    :ok
  end

  # -------------------------------------------------------------------------
  # T1071: Standard Application Layer Protocol
  # Attack: Adversary attempts to use unauthorized protocol (e.g., HTTP) to command system.
  # Defense: Protocol Guarding (DPI)
  # -------------------------------------------------------------------------
  test "MITRE T1071: Protocol Impersonation (Blocked)" do
    # 1. Defense Configuration: Allow ONLY :modbus
    Application.put_env(:data_diode, :protocol_allow_list, [:modbus])

    DataDiode.Metrics.reset_stats()

    # 2. Attack: Send "HTTP" payload (Should be BLOCKED)
    # HTTP "GET /" does not match Modbus signature (bytes 2,3 = 0x0000)
    http_payload = "GET /admin HTTP/1.1\r\n\r\n"
    DataDiode.S1.Encapsulator.encapsulate_and_send("1.2.3.4", 1234, http_payload)

    Process.sleep(50)

    # Verify Blocked (Error Count 1)
    stats1 = DataDiode.Metrics.get_stats()
    assert stats1.error_count == 1

    # 3. Legitimate Traffic: Send Modbus Payload (Should be ALLOWED)
    # Modbus TCP: TransID(2), ProtoID=0x0000, Len(2), Unit(1), Func(1)
    modbus_payload = <<0x01, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01, 0x03, 0x00, 0x00, 0x00, 0x01>>
    DataDiode.S1.Encapsulator.encapsulate_and_send("1.2.3.4", 1234, modbus_payload)

    Process.sleep(50)

    # Verify Allowed (Packet count 1, Error count still 1)
    stats2 = DataDiode.Metrics.get_stats()
    assert stats2.packets_forwarded == 1
    assert stats2.error_count == 1
  end

  # -------------------------------------------------------------------------
  # T1499: Endpoint Denial of Service
  # Attack: Adversary floods the service to exhaust resources or network bandwidth.
  # Defense: Token Bucket Rate Limiting
  # -------------------------------------------------------------------------
  test "MITRE T1499: DoS Flooding (Rate Limited)" do
    # 1. Defense Configuration: Low Rate Limit
    DataDiode.S1.Encapsulator.set_rate_limit(5)

    # Start metrics to capture the drop API call
    DataDiode.Metrics.reset_stats()

    # 2. Attack: Send 100 packets rapidly (Limit is 5, so MUST drop)
    logs =
      capture_log(fn ->
        Enum.each(1..100, fn i ->
          DataDiode.S1.Encapsulator.encapsulate_and_send("1.2.3.4", 1234, "FLOOD_#{i}")
        end)

        # Allow processing
        Process.sleep(100)
      end)

    # Wait a bit more for metrics to update asynchronously
    Process.sleep(50)

    # 3. Verification: Check METRICS instead of logs
    # Because logs are probabilistic (1% chance), we can't assert log presence reliably.
    # But Metrics.inc_errors() is called every time.

    stats = DataDiode.Metrics.get_stats()
    assert stats.error_count > 0
  end

  # -------------------------------------------------------------------------
  # T1565: Data Manipulation
  # Attack: Adversary modifies data in transit (integrity violation).
  # Defense: CRC32 Checksum Verification
  # -------------------------------------------------------------------------
  test "MITRE T1565: Data Manipulation (Integrity Check)" do
    # Ensure clean Metrics start
    DataDiode.Metrics.reset_stats()

    # 1. Prepare Valid Packet
    payload = "Important Command"
    ip = <<10, 0, 0, 1>>
    port = <<100::16>>
    header_payload = ip <> port <> payload

    # 2. Attack: Generate INVALID Checksum (Corrupted)
    fake_checksum = <<0xDEADBEEF::32>>
    malicious_packet = header_payload <> fake_checksum

    # 3. Injection: Feed to Decapsulator
    # 4. Verification: Logic rejects it
    assert {:error, :integrity_check_failed} =
             DataDiode.S2.Decapsulator.process_packet(malicious_packet)
  end
end
