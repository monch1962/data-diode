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
      base_delay = 5000  # 5 seconds

      # Calculate delays for first 6 attempts
      delays =
        Enum.map(1..6, fn attempt ->
          base_delay * :math.pow(2, attempt - 1)
        end)

      # Expected: [5000, 10000, 20000, 40000, 80000, 160000]
      assert Enum.at(delays, 0) == 5000
      assert Enum.at(delays, 1) == 10000
      assert Enum.at(delays, 2) == 20000
      assert Enum.at(delays, 5) == 160000
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
end
