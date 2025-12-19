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
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, send_timeout: 1000])
    
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
    # Decapsulator depends on Metrics
    DataDiode.Metrics.start_link([])

    # Decapsulator logic manually invoked
    # Normal packet: header(6) + payload + checksum(4)
    
    # 1. Packet too short (3 bytes)
    assert {:error, :invalid_packet_size_or_missing_checksum} = DataDiode.S2.Decapsulator.process_packet(<<1, 2, 3>>)
    
    # 2. Packet with just header but no checksum
    assert {:error, :invalid_packet_size_or_missing_checksum} = DataDiode.S2.Decapsulator.process_packet(<<1,2,3,4,5,6>>)
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
    File.write!(thermal_path, "85000\n") # 85.0 C
    
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
    end) =~ "Thermal Cutoff"
    
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
    
    DataDiode.Metrics.start_link(name: :metrics_disk_full)
    
    # Ensure data_dir is set to a file so it fails
    tmp_path = Path.join(System.tmp_dir!(), "disk_full_sim_file")
    File.write!(tmp_path, "")
    Application.put_env(:data_diode, :data_dir, tmp_path)
    
    packet = <<127,0,0,1, 0,80, "PAYLOAD">> 
    checksum = :erlang.crc32(packet)
    full_packet = packet <> <<checksum::32>>
    
    assert capture_log(fn ->
      # It returns generic error
      assert {:error, _} = DataDiode.S2.Decapsulator.process_packet(full_packet)
    end) =~ "S2: Secure write failed"
    
    # Verify metrics increased
    stats = DataDiode.Metrics.get_stats()
    assert stats.error_count > 0
    
    File.rm(tmp_path)
    GenServer.stop(DataDiode.Metrics)
  end

  test "Environmental: Network Flapping Recovery" do
    # Simulating actual network interface flapping is hard without OS privileges.
    # Instead, we verify that the Listener accepts connections after a "pause" or errors.
    
    port = 45005
    Application.put_env(:data_diode, :s1_port, port)
    
    {:ok, pid} = DataDiode.S1.Listener.start_link(name: :s1_flap_test)
    
    # 1. Connect Success
    {:ok, s1} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    :gen_tcp.close(s1)
    
    # 2. Simulate "Flapping" / Storm
    # We just blast it with rapid connect/close to ensure it doesn't get stuck in a bad state
    Enum.each(1..50, fn _ ->
      case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false]) do
        {:ok, s} -> :gen_tcp.close(s)
        _ -> :ok # If connect fails (simulating network drop), we ignore
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
    
    GenServer.stop(pid)
  end
end
