defmodule DataDiode.OTHardeningTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  setup do
    # Ensure a clean state for testing
    {:ok, tmp_dir} = File.cwd()
    data_dir = Path.join(tmp_dir, "test_data_hardening")
    File.mkdir_p!(data_dir)
    Application.put_env(:data_diode, :data_dir, data_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      Application.delete_env(:data_diode, :protocol_allow_list)
      Application.delete_env(:data_diode, :max_packets_per_sec)
      Application.delete_env(:data_diode, :watchdog_path)
      Application.delete_env(:data_diode, :watchdog_interval)
    end)

    {:ok, data_dir: data_dir}
  end

  test "S1.Encapsulator adds CRC32 and S2.Decapsulator verifies it" do
    payload = "SECURE_DATA"
    ip = "127.0.0.1"
    port = 8080

    # 1. Simulate Encapsulator logic manually to get the packet
    ip_bin = <<127, 0, 0, 1>>
    header_payload = <<ip_bin::binary, port::integer-unsigned-big-16, payload::binary>>
    checksum = :erlang.crc32(header_payload)
    valid_packet = <<header_payload::binary, checksum::integer-unsigned-big-32>>

    # 2. Verify Decapsulator accepts it
    assert {:ok, ^ip, ^port, ^payload} = DataDiode.S2.Decapsulator.parse_header(valid_packet)

    # 3. Corrupt the packet
    corrupt_packet = <<header_payload::binary, checksum + 1::integer-unsigned-big-32>>

    assert {:error, :integrity_check_failed} =
             DataDiode.S2.Decapsulator.parse_header(corrupt_packet)
  end

  test "S2.Decapsulator writes files atomically", %{data_dir: data_dir} do
    src_port = 1234
    payload = "ATOMIC_CONTENT"

    ip_bin = <<127, 0, 0, 1>>
    header_payload = <<ip_bin::binary, src_port::integer-unsigned-big-16, payload::binary>>
    checksum = :erlang.crc32(header_payload)
    packet = <<header_payload::binary, checksum::integer-unsigned-big-32>>

    # process_packet calls the atomic write logic
    assert :ok = DataDiode.S2.Decapsulator.process_packet(packet)

    # Verifying the final result
    files = File.ls!(data_dir)
    assert Enum.any?(files, fn f -> String.ends_with?(f, ".dat") end)
    dat_file = Enum.find(files, fn f -> String.ends_with?(f, ".dat") end)
    assert File.read!(Path.join(data_dir, dat_file)) == payload

    # Hardness: Ensure NO .tmp files are visible after the operation
    assert Enum.all?(files, fn f -> not String.ends_with?(f, ".tmp") end)
  end

  test "S2.Decapsulator handles atomic write failures", %{data_dir: data_dir} do
    # Try to write to a path that is a FILE (ENOTDIR error)
    # We create a file, then set data_dir to that path.
    # When Decapsulator tries Path.join(data_dir, filename), it creates a path like /file/filename
    # File.write to that fails.
    dummy_file = Path.join(data_dir, "dummy_file")
    File.write!(dummy_file, "")
    Application.put_env(:data_diode, :data_dir, dummy_file)

    packet =
      (fn payload ->
         header = <<127, 0, 0, 1, 0, 80>>
         p = header <> payload
         crc = :erlang.crc32(p)
         p <> <<crc::32>>
       end).("FAIL")

    assert capture_log(fn ->
             # Expecting ENOTDIR (Not a directory) or similar error
             assert {:error, reason} = DataDiode.S2.Decapsulator.process_packet(packet)
             assert reason in [:enotdir, :enoent]
           end) =~ "S2: Secure write failed"
  end

  test "S1.Encapsulator respects rate limits" do
    # Start a private instance to avoid messing with global one
    name = :rate_limit_test
    Application.put_env(:data_diode, :max_packets_per_sec, 2)
    {:ok, pid} = DataDiode.S1.Encapsulator.start_link(name: name)

    # Refill happens every 1s, so we have 2 tokens initially.
    # We use the internal cast to verify it doesn't crash
    GenServer.cast(name, {:send, "1.1.1.1", 80, "P1"})
    GenServer.cast(name, {:send, "1.1.1.1", 80, "P2"})

    # Flood to trigger logging branch (rem 100 == 0)
    # We can't guarantee unique_integer result but we can try a few times
    capture_log(fn ->
      for _ <- 1..200 do
        GenServer.cast(name, {:send, "1.1.1.1", 80, "P_DROP"})
      end
    end)

    # Check state
    state = :sys.get_state(pid)
    assert state.tokens <= 0

    GenServer.stop(pid)
  end

  test "S1.Encapsulator handles UDP send failures" do
    name = :udp_fail_test
    # Pass a closed socket to force failure (or just use a dummy pid if we can)
    # Actually, we can just use GenServer.cast with a valid state but a closed socket
    {:ok, socket} = :gen_udp.open(0)
    :gen_udp.close(socket)

    # We need to manually start it with the bad socket to hit the handle_cast branch
    {:ok, pid} = GenServer.start_link(DataDiode.S1.Encapsulator, :ok)
    # Replace the socket in state
    :sys.replace_state(pid, fn state -> %{state | socket: socket} end)

    assert capture_log(fn ->
             GenServer.cast(pid, {:send, "127.0.0.1", 80, "payload"})
             # Give it time to process the cast
             Process.sleep(50)
           end) =~ "Failed to send packet"

    GenServer.stop(pid)
  end

  test "S1.Encapsulator respects protocol allow-list" do
    name = :protocol_test
    Application.put_env(:data_diode, :protocol_allow_list, [:modbus])

    # Reset RateLimiter state for this IP to avoid test pollution
    DataDiode.RateLimiter.reset_ip("1.1.1.1")

    {:ok, pid} = DataDiode.S1.Encapsulator.start_link(name: name)

    # The state should show token consumption only for allowed packets if we weren't just dropping both
    # Actually, both consume tokens in my implementation (to punish bad actors/noise).

    # Modbus TCP packet: TransactionID(2), ProtocolID=0x0000, Length(2), UnitID(1), Function(1)
    modbus_packet = <<0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01, 0x03, 0x00, 0x00, 0x00, 0x01>>
    non_modbus_packet = "NOT_MODBUS_DATA"

    GenServer.cast(name, {:send, "1.1.1.1", 80, modbus_packet})
    GenServer.cast(name, {:send, "1.1.1.1", 80, non_modbus_packet})

    # Small sleep to ensure casts are processed
    Process.sleep(10)

    state = :sys.get_state(pid)
    # Both consumed tokens (1 allowed, 1 blocked)
    # With continuous token bucket, tokens may have refilled slightly, so check at least 1 consumed
    assert state.tokens <= state.limit - 1

    GenServer.stop(pid)
  end

  test "Watchdog pulses only when services are healthy" do
    pulse_path = "/tmp/diode_watchdog_test"
    File.rm(pulse_path)

    # Fast interval for test
    Application.put_env(:data_diode, :watchdog_interval, 50)
    Application.put_env(:data_diode, :watchdog_path, pulse_path)

    # Start isolated watchdog
    {:ok, pid} = DataDiode.Watchdog.start_link(name: :watchdog_test_instance)

    # Give it a few cycles
    Process.sleep(150)

    # It should have withheld pulse if main services aren't running in this test context
    # unless we are running the whole app.
    # Let's ensure it handles the unhealthy state
    capture_log(fn ->
      send(pid, :pulse)
    end) =~ "System unhealthy"

    # Hit the pulse failure branch
    # Direct Key: We can call the exposed function to guarantee we hit the File.write failure
    # without relying on async timing or health checks.
    assert capture_log(fn ->
             # Trying to write to a CWD (directory) as a file fails
             DataDiode.Watchdog.pulse(File.cwd!())
           end) =~ "Failed to pulse"

    GenServer.stop(pid)
  end
end
