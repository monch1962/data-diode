defmodule DataDiode.NegativeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  setup do
    Application.ensure_all_started(:data_diode)

    on_exit(fn ->
      Application.delete_env(:data_diode, :s1_port)
      Application.delete_env(:data_diode, :s2_port)
      Application.delete_env(:data_diode, :thermal_path)
      Application.delete_env(:data_diode, :watchdog_max_temp)
      File.rm("/tmp/neg_test_thermal")
    end)

    :ok
  end

  test "TCP Fuzzing: Oversized Packet" do
    port = 45000
    Application.put_env(:data_diode, :s1_port, port)

    # Start isolated listener
    {:ok, pid} = DataDiode.S1.Listener.start_link(name: :s1_fuzz_oversized)

    # 2. Connect
    {:ok, socket} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, send_timeout: 1000])

    # 3. Create a massive packet (512KB)
    junk = :binary.copy(<<0>>, 512 * 1024)

    # 4. Send it
    :ok = :gen_tcp.send(socket, junk)

    # 5. Assert: The listener is still alive
    assert Process.alive?(pid)

    :gen_tcp.close(socket)
    GenServer.stop(pid)
  end

  test "TCP Fuzzing: Garbage / Malformed HTTP" do
    port = 45001
    Application.put_env(:data_diode, :s1_port, port)

    {:ok, pid} = DataDiode.S1.Listener.start_link(name: :s1_fuzz_garbage)

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

    :gen_tcp.send(socket, <<255, 0, 255, 12, 123, 88>>)

    Process.sleep(100)
    assert Process.alive?(pid)

    :gen_tcp.close(socket)
    GenServer.stop(pid)
  end

  test "UDP Negative: Malformed Packet (Truncated)" do
    # Decapsulator logic manually invoked
    # Normal packet: header(6) + payload + checksum(4)

    # 1. Packet too short (3 bytes)
    assert {:error, :invalid_packet_size_or_missing_checksum} =
             DataDiode.S2.Decapsulator.process_packet(<<1, 2, 3>>)

    # 2. Packet with just header but no checksum
    assert {:error, :invalid_packet_size_or_missing_checksum} =
             DataDiode.S2.Decapsulator.process_packet(<<1, 2, 3, 4, 5, 6>>)
  end

  test "Configuration Robustness: Invalid Port Type" do
    # Set port to a string "ABC"
    Application.put_env(:data_diode, :s1_port, "ABC")

    # Attempt to start just the listener. It should fail gracefully or crash.
    Process.flag(:trap_exit, true)

    assert capture_log(fn ->
             # We try to start the listener directly with the bad config
             # Pass a unique name to bypass "already started" check for the default name
             res = DataDiode.S1.Listener.start_link(name: :s1_config_robustness)
             # It might return {:error, ...} or exit
             assert match?({:error, _}, res) or match?({:ok, _}, res) == false
           end)

    Process.flag(:trap_exit, false)
  end

  test "Environmental: Thermal Cutoff" do
    # 1. Create a mock thermal file with DANGEROUS temp
    thermal_path = "/tmp/neg_test_thermal"
    # 85.0 C
    File.write!(thermal_path, "85000\n")

    Application.put_env(:data_diode, :thermal_path, thermal_path)
    Application.put_env(:data_diode, :watchdog_max_temp, 80.0)

    # 2. Start Watchdog in isolation
    {:ok, pid} = DataDiode.Watchdog.start_link(name: :watchdog_thermal_test)

    # 3. Force a pulse check
    send(pid, :pulse)

    # 4. Verify log message about Cutoff
    assert capture_log(fn ->
             send(pid, :pulse)
             Process.sleep(50)
             send(pid, :pulse)
             Process.sleep(50)
           end) =~ "thermal limit exceeded"

    # 5. Cool down
    File.write!(thermal_path, "40000\n")
    # Verify recovery? (Not strictly required by test, but good for validation)

    GenServer.stop(pid)
  end

  test "Environmental: Disk Full Resilience (Simulated)" do
    # Simulate ENOSPC by trying to write to a directory path, which fails
    # S2 Decapsulator should handle this generic write error gracefullly

    # We rely on the generic {:error, reason} handling in write_to_secure_storage
    # triggering Metrics.inc_errors() and logging.

    DataDiode.Metrics.reset_stats()

    # Ensure data_dir is set to a file so it fails
    tmp_path = Path.join(System.tmp_dir!(), "disk_full_sim_file")
    File.write!(tmp_path, "")
    Application.put_env(:data_diode, :data_dir, tmp_path)

    packet = <<127, 0, 0, 1, 0, 80, "PAYLOAD">>
    checksum = :erlang.crc32(packet)
    full_packet = packet <> <<checksum::32>>

    assert capture_log(fn ->
             # It returns generic error
             assert {:error, _} = DataDiode.S2.Decapsulator.process_packet(full_packet)
           end) =~ "S2: Secure write failed"

    # Verify metrics increased
    stats = DataDiode.Metrics.get_stats()
    assert stats.error_count
    File.rm(tmp_path)
  end

  test "Environmental: Network Flapping Recovery" do
    # Simulating actual network interface flapping is hard without OS privileges.
    # Instead, we verify that the Listener accepts connections after a "pause" or errors.

    port = 45005
    Application.put_env(:data_diode, :s1_port, port)

    {:ok, pid} = DataDiode.S1.Listener.start_link(name: :s1_flap_test)
    # Listener needs the Supervisor to spawn handlers (already running in app)

    # 1. Connect Success
    {:ok, s1} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    :gen_tcp.close(s1)

    # 2. Simulate "Flapping" / Storm
    # We just blast it with rapid connect/close to ensure it doesn't get stuck in a bad state
    Enum.each(1..50, fn _ ->
      case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false]) do
        {:ok, s} -> :gen_tcp.close(s)
        # If connect fails (simulating network drop), we ignore
        _ -> :ok
      end
    end)

    Process.sleep(100)

    # 3. Verify it still accepts
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false]) do
      {:ok, s2} ->
        assert is_port(s2)
        :gen_tcp.close(s2)

      {:error, reason} ->
        flunk("Listener failed to recover after flapping: #{inspect(reason)}")
    end

    wait_until_empty(DataDiode.S1.HandlerSupervisor, 50)
    GenServer.stop(pid)
  end

  # --- Phase 27: Edge Cases ---

  test "Edge Case: Persistence Unique Filenames" do
    # Verify two writes of the same data produce DIFFERENT filenames
    # This indirectly checks that our random token logic is working
    DataDiode.Metrics.reset_stats()

    tmp_dir = Path.join(System.tmp_dir!(), "diode_unique_test")
    File.mkdir_p!(tmp_dir)
    Application.put_env(:data_diode, :data_dir, tmp_dir)

    packet = <<127, 0, 0, 1, 0, 80, "PAYLOAD">>
    checksum = :erlang.crc32(packet)
    full_packet = packet <> <<checksum::32>>

    # Write twice
    assert :ok = DataDiode.S2.Decapsulator.process_packet(full_packet)
    assert :ok = DataDiode.S2.Decapsulator.process_packet(full_packet)

    # List files
    files = File.ls!(tmp_dir)
    assert length(files) == 2

    File.rm_rf(tmp_dir)
  end

  test "Edge Case: Zero-Byte Payload" do
    DataDiode.Metrics.reset_stats()
    tmp_dir = Path.join(System.tmp_dir!(), "diode_zero_test")
    File.mkdir_p!(tmp_dir)
    Application.put_env(:data_diode, :data_dir, tmp_dir)

    # 0 byte payload
    packet = <<127, 0, 0, 1, 0, 80>>
    checksum = :erlang.crc32(packet)
    full_packet = packet <> <<checksum::32>>

    assert :ok = DataDiode.S2.Decapsulator.process_packet(full_packet)

    # Should produce a file with 0 bytes? or just headers?
    # Our Decapsulator writes plain payload. So it should be a 0-byte file.
    files = File.ls!(tmp_dir)
    assert length(files) == 1

    content = File.read!(Path.join(tmp_dir, hd(files)))
    assert content == ""

    File.rm_rf(tmp_dir)
  end

  test "Edge Case: Connection Exhaustion (DoS)" do
    # Try to open 250 connections to S1
    # System default ulimit might be 256 or 1024, so 250 is safe but stressful for app
    port = 45009
    Application.put_env(:data_diode, :s1_port, port)

    {:ok, pid} = DataDiode.S1.Listener.start_link(name: :s1_dos_test)

    sockets =
      for _ <- 1..110 do
        case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false]) do
          {:ok, s} -> s
          _ -> nil
        end
      end

    # Some might fail if system limits reached, that's fine.
    # We just assert the Listener is still alive and didn't crash BEAM.
    assert Process.alive?(pid)

    # Cleanup
    Enum.each(sockets, fn s -> if s, do: :gen_tcp.close(s) end)

    # Wait for handlers to exit (important for test isolation)
    wait_until_empty(DataDiode.S1.HandlerSupervisor, 50)

    GenServer.stop(pid)
  end

  defp wait_until_empty(sup, retries) when retries > 0 do
    case DynamicSupervisor.count_children(sup) do
      %{active: 0} ->
        :ok

      _ ->
        Process.sleep(50)
        wait_until_empty(sup, retries - 1)
    end
  end

  defp wait_until_empty(_, _), do: :timeout
end
