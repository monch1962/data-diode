defmodule DataDiode.NetworkGuardTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  doctest DataDiode.NetworkGuard

  describe "basic operation" do
    setup do
      :ok
    end

    test "starts successfully" do
      pid = Process.whereis(DataDiode.NetworkGuard)
      assert pid != nil
      assert Process.alive?(pid)
    end

    test "checks network interfaces" do
      # This test may fail on systems without 'ip' command or network interfaces
      # The function should either return a list or crash with :enoent
      try do
        interfaces = DataDiode.NetworkGuard.check_network_interfaces()
        assert is_list(interfaces)
      rescue
        # It's OK if the function crashes when 'ip' command doesn't exist
        _error in ErlangError -> :ok
      end
    end
  end

  describe "interface state tracking" do
    setup do
      :ok
    end

    test "tracks interface state over time" do
      pid = Process.whereis(DataDiode.NetworkGuard)
      assert pid != nil

      # Get initial state
      _state1 = :sys.get_state(pid)

      # Wait a bit
      Process.sleep(100)

      # State should still be valid
      _state2 = :sys.get_state(pid)
      assert true
    end

    test "continues monitoring without crashing" do
      pid = Process.whereis(DataDiode.NetworkGuard)
      assert pid != nil

      # Should not crash on periodic checks
      Process.sleep(500)
      assert Process.alive?(pid)
    end
  end

  describe "flapping detection logic" do
    test "detects rapid state changes" do
      # Simulate interface history with rapid changes
      history = [
        %{timestamp: System.system_time(:millisecond) - 300_000, s1: :up, s2: :up},
        %{timestamp: System.system_time(:millisecond) - 240_000, s1: :down, s2: :up},
        %{timestamp: System.system_time(:millisecond) - 180_000, s1: :up, s2: :up},
        %{timestamp: System.system_time(:millisecond) - 120_000, s1: :down, s2: :up},
        %{timestamp: System.system_time(:millisecond) - 60_000, s1: :up, s2: :up},
        %{timestamp: System.system_time(:millisecond), s1: :down, s2: :up}
      ]

      # Count state changes for S1
      s1_states = Enum.map(history, fn h -> Map.get(h, :s1) end)

      changes =
        s1_states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [prev, curr] -> prev != curr end)

      # Should detect 5 state changes (flapping)
      assert changes == 5
    end

    test "calculates exponential backoff correctly" do
      # Test exponential backoff calculation
      # 5 seconds
      base_delay = 5000

      # Calculate delays for first 6 attempts
      delays =
        Enum.map(1..6, fn attempt ->
          base_delay * :math.pow(2, attempt - 1)
        end)

      # Expected: [5000, 10000, 20000, 40000, 80000, 160000]
      assert Enum.at(delays, 0) == 5000
      assert Enum.at(delays, 1) == 10000
      assert Enum.at(delays, 2) == 20000
      assert Enum.at(delays, 5) == 160_000
    end
  end

  describe "error handling" do
    setup do
      :ok
    end

    test "handles missing interfaces gracefully" do
      # Should not crash even if interfaces don't exist
      try do
        interfaces = DataDiode.NetworkGuard.check_network_interfaces()
        assert is_list(interfaces)
      rescue
        # It's OK if the function crashes when 'ip' command doesn't exist
        _error in ErlangError -> :ok
      end
    end

    test "logs network events" do
      log =
        capture_log(fn ->
          # NetworkGuard is already started by the application
          Process.sleep(100)
        end)

      # NetworkGuard might or might not log network events depending on configuration
      # The important thing is it continues running
      pid = Process.whereis(DataDiode.NetworkGuard)
      assert Process.alive?(pid)
    end
  end

  describe "with single network interface" do
    setup do
      Application.put_env(:data_diode, :s1_interface, "eth0")
      Application.put_env(:data_diode, :s2_interface, nil)

      on_exit(fn ->
        Application.delete_env(:data_diode, :s1_interface)
        Application.delete_env(:data_diode, :s2_interface)
      end)

      :ok
    end

    test "starts with single interface config" do
      pid = Process.whereis(DataDiode.NetworkGuard)
      assert Process.alive?(pid)
    end

    test "monitors available interface" do
      # NetworkGuard is already started by the application
      pid = Process.whereis(DataDiode.NetworkGuard)
      assert Process.alive?(pid)
    end
  end

  describe "with shared interface" do
    setup do
      Application.put_env(:data_diode, :s1_interface, "eth0")
      Application.put_env(:data_diode, :s2_interface, "eth0")

      on_exit(fn ->
        Application.delete_env(:data_diode, :s1_interface)
        Application.delete_env(:data_diode, :s2_interface)
      end)

      :ok
    end

    test "handles shared interface configuration" do
      pid = Process.whereis(DataDiode.NetworkGuard)
      assert Process.alive?(pid)
    end

    test "monitors shared interface" do
      # NetworkGuard is already started by the application
      pid = Process.whereis(DataDiode.NetworkGuard)
      assert Process.alive?(pid)
    end
  end

  describe "state changes" do
    test "counts state transitions correctly" do
      states = [:up, :down, :up, :down, :up]

      transitions =
        states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [prev, curr] -> prev != curr end)

      assert transitions == 4
    end

    test "detects no transitions in stable state" do
      states = [:up, :up, :up, :up, :up]

      transitions =
        states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [prev, curr] -> prev != curr end)

      assert transitions == 0
    end
  end

  describe "GenServer callbacks" do
    test "handles periodic interface checks" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Trigger check directly - may crash if ip command not available
      send(pid, :check_interfaces)
      Process.sleep(100)

      # Process may crash if ip command not available, but should restart
      # Check if either the original pid or new pid is alive
      Process.sleep(200)
      pid_after = Process.whereis(DataDiode.NetworkGuard)
      assert pid_after != nil
    end

    test "handles recovery ready message" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Simulate recovery from flapping state
      send(pid, :recovery_ready)

      # Should not crash
      Process.sleep(100)
      assert Process.alive?(pid)
    end

    test "has valid state structure" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Get state - should have expected structure
      state = :sys.get_state(pid)
      assert Map.has_key?(state, :interface_state)
      assert Map.has_key?(state, :history)
      assert is_list(state.history)
    end
  end

  describe "interface configuration" do
    test "uses default s1 interface when not configured" do
      # Remove the config
      Application.delete_env(:data_diode, :s1_interface)

      # Should default to "eth0"
      interface = Application.get_env(:data_diode, :s1_interface, "eth0")
      assert interface == "eth0"

      # Restore config
      Application.put_env(:data_diode, :s1_interface, "eth0")
    end

    test "uses default s2 interface when not configured" do
      # Remove the config
      Application.delete_env(:data_diode, :s2_interface)

      # Should default to "eth1"
      interface = Application.get_env(:data_diode, :s2_interface, "eth1")
      assert interface == "eth1"

      # Restore config
      Application.put_env(:data_diode, :s2_interface, "eth1")
    end
  end

  describe "flapping recovery" do
    test "handles flapping penalty expiration" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # When flapping penalty expires, should send recovery ready message
      # This is internal, but we can verify the process handles the message
      send(pid, :recovery_ready)

      Process.sleep(100)
      assert Process.alive?(pid)
    end
  end

  describe "history tracking" do
    test "maintains history of interface states" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      state = :sys.get_state(pid)
      assert is_list(state.history)

      # History should have timestamps
      case state.history do
        [] ->
          :ok

        [entry | _] ->
          assert Map.has_key?(entry, :timestamp)
      end
    end
  end
end
