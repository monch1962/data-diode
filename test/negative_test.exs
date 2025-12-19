defmodule DataDiode.NegativeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  setup do
    Application.ensure_all_started(:data_diode)
    on_exit(fn ->
      Application.delete_env(:data_diode, :s1_port)
      Application.delete_env(:data_diode, :s2_port)
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
end
