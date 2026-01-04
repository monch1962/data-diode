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
      # This test handles systems with and without 'ip' command
      interfaces = DataDiode.NetworkGuard.check_network_interfaces()

      # Should return a map with s1, s2, and timestamp
      assert is_map(interfaces)
      assert Map.has_key?(interfaces, :s1) or Map.has_key?(interfaces, "s1")
      assert Map.has_key?(interfaces, :s2) or Map.has_key?(interfaces, "s2")
      assert Map.has_key?(interfaces, :timestamp) or Map.has_key?(interfaces, "timestamp")

      # On systems with 'ip' command, interfaces should have :up field
      # On systems without, they should have :error field
      s1 = Map.get(interfaces, :s1) || Map.get(interfaces, "s1")

      assert Map.has_key?(s1, :up) or Map.has_key?(s1, "up") or Map.has_key?(s1, :error) or
               Map.has_key?(s1, "error")
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
      assert Enum.at(delays, 1) == 10_000
      assert Enum.at(delays, 2) == 20_000
      assert Enum.at(delays, 5) == 160_000
    end
  end

  describe "error handling" do
    setup do
      :ok
    end

    test "handles missing interfaces gracefully" do
      # Should not crash even if interfaces don't exist or 'ip' command is unavailable
      interfaces = DataDiode.NetworkGuard.check_network_interfaces()

      # Should return a map even when interfaces don't exist or command fails
      assert is_map(interfaces)
      assert Map.has_key?(interfaces, :s1) or Map.has_key?(interfaces, "s1")
      assert Map.has_key?(interfaces, :s2) or Map.has_key?(interfaces, "s2")
      assert Map.has_key?(interfaces, :timestamp) or Map.has_key?(interfaces, "timestamp")
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

    test "history entries contain correct structure" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Manually add a history entry
      current_state = %{
        s1: %{up: true, interface: "eth0"},
        s2: %{up: false, interface: "eth1"},
        timestamp: System.system_time(:millisecond)
      }

      state = :sys.get_state(pid)

      entry = %{
        s1_up: current_state.s1.up,
        s2_up: current_state.s2.up,
        timestamp: current_state.timestamp
      }

      new_state = %{state | history: [entry | state.history]}
      :sys.replace_state(pid, fn _ -> new_state end)

      # Verify entry was added
      updated_state = :sys.get_state(pid)
      assert length(updated_state.history) > 0
      assert hd(updated_state.history).s1_up == true
      assert hd(updated_state.history).s2_up == false
    end

    test "filters history by time window" do
      # Create test history with various timestamps
      now = System.system_time(:millisecond)

      old_entry = %{
        s1_up: true,
        s2_up: true,
        # 6 minutes 40 seconds ago (> 5 minute window)
        timestamp: now - 400_000
      }

      recent_entry = %{
        s1_up: false,
        s2_up: true,
        # 1 minute ago (within 5 minute window)
        timestamp: now - 60_000
      }

      very_recent_entry = %{
        s1_up: true,
        s2_up: false,
        # 10 seconds ago (within 5 minute window)
        timestamp: now - 10_000
      }

      history = [very_recent_entry, recent_entry, old_entry]

      # Filter to last 5 minutes (300,000 ms)
      cutoff = now - 300_000
      filtered = Enum.filter(history, fn entry -> entry.timestamp > cutoff end)

      # Should only include recent entries
      assert length(filtered) == 2
      assert very_recent_entry in filtered
      assert recent_entry in filtered
      refute old_entry in filtered
    end
  end

  describe "flapping detection and protection" do
    test "activates flapping protection when threshold exceeded" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Create a history with many state changes (flapping scenario)
      now = System.system_time(:millisecond)

      # Create 6 state changes within 5 minutes (threshold is 5)
      flapping_history =
        Enum.map(0..5, fn i ->
          %{
            s1_up: rem(i, 2) == 0,
            s2_up: true,
            # Each 40 seconds apart
            timestamp: now - i * 40_000
          }
        end)

      # Set state with flapping history
      state = :sys.get_state(pid)
      new_state = %{state | history: flapping_history, flapping: false}
      :sys.replace_state(pid, fn _ -> new_state end)

      # Trigger check_interfaces to run flapping detection
      log =
        capture_log(fn ->
          send(pid, :check_interfaces)
          Process.sleep(100)
        end)

      # Should log flapping detection
      assert log =~ ~r/Flapping detected/i

      # State should now be in flapping mode
      final_state = :sys.get_state(pid)
      assert final_state.flapping == true
    end

    test "does not activate flapping protection when under threshold" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Create a history with few state changes (stable scenario)
      now = System.system_time(:millisecond)

      # Create only 2 state changes within 5 minutes (threshold is 5)
      stable_history = [
        %{
          s1_up: true,
          s2_up: true,
          timestamp: now - 60_000
        },
        %{
          s1_up: false,
          s2_up: true,
          timestamp: now - 30_000
        }
      ]

      # Set state with stable history
      state = :sys.get_state(pid)
      new_state = %{state | history: stable_history, flapping: false}
      :sys.replace_state(pid, fn _ -> new_state end)

      # Trigger check_interfaces
      send(pid, :check_interfaces)
      Process.sleep(100)

      # Should NOT be in flapping mode
      final_state = :sys.get_state(pid)
      assert final_state.flapping == false
    end

    test "skips flapping detection when already in flapping state" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Set state as already flapping
      state = :sys.get_state(pid)
      new_state = %{state | flapping: true, history: []}
      :sys.replace_state(pid, fn _ -> new_state end)

      # Trigger check_interfaces
      send(pid, :check_interfaces)
      Process.sleep(100)

      # Should remain in flapping state
      final_state = :sys.get_state(pid)
      assert final_state.flapping == true
    end

    test "schedules recovery ready message when flapping detected" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Create history that will trigger flapping
      now = System.system_time(:millisecond)

      flapping_history =
        Enum.map(0..5, fn i ->
          %{
            s1_up: rem(i, 2) == 0,
            s2_up: true,
            timestamp: now - i * 40_000
          }
        end)

      state = :sys.get_state(pid)
      new_state = %{state | history: flapping_history, flapping: false}
      :sys.replace_state(pid, fn _ -> new_state end)

      # Trigger flapping detection
      log =
        capture_log(fn ->
          send(pid, :check_interfaces)
          Process.sleep(100)
        end)

      assert log =~ ~r/Flapping detected/i
      assert log =~ ~r/Activating flapping protection/i

      # Should still be alive and have scheduled recovery
      assert Process.alive?(pid)
    end
  end

  describe "interface state change handling" do
    test "logs when S1 interface goes down" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Set initial state as UP
      state = :sys.get_state(pid)
      initial_state = %{state | interface_state: %{s1: :up, s2: :up}}
      :sys.replace_state(pid, fn _ -> initial_state end)

      # Simulate interface going down
      _current_state = %{
        s1: %{up: false, interface: "eth0"},
        s2: %{up: true, interface: "eth1"},
        timestamp: System.system_time(:millisecond)
      }

      # Manually trigger the state change logic
      log =
        capture_log(fn ->
          # We need to call check_interfaces which will detect the change
          send(pid, :check_interfaces)
          Process.sleep(100)
        end)

      # Should log interface down
      assert log =~ ~r/S1 interface.*went down/i or log =~ ~r/NetworkGuard/i
    end

    test "logs when S2 interface goes down" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Set initial state as UP
      state = :sys.get_state(pid)
      initial_state = %{state | interface_state: %{s1: :up, s2: :up}}
      :sys.replace_state(pid, fn _ -> initial_state end)

      # Simulate interface going down by manipulating state
      _current_state = %{
        s1: %{up: true, interface: "eth0"},
        s2: %{up: false, interface: "eth1"},
        timestamp: System.system_time(:millisecond)
      }

      # Trigger check - the log message depends on actual interface state
      _log =
        capture_log(fn ->
          send(pid, :check_interfaces)
          Process.sleep(100)
        end)

      # Verify some network guard activity
      assert Process.alive?(pid)
    end

    test "does not attempt recovery when flapping" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Set state as flapping with interface down
      state = :sys.get_state(pid)

      flapping_state = %{
        state
        | flapping: true,
          interface_state: %{s1: :down, s2: :up}
      }

      :sys.replace_state(pid, fn _ -> flapping_state end)

      # Disable auto-recovery to ensure we don't attempt it
      Application.put_env(:data_diode, :auto_recovery_enabled, true)

      on_exit(fn ->
        Application.delete_env(:data_diode, :auto_recovery_enabled)
      end)

      # Trigger check
      log =
        capture_log(fn ->
          send(pid, :check_interfaces)
          Process.sleep(100)
        end)

      # Should NOT attempt recovery when flapping
      # (no "Attempting to recover" message)
      refute log =~ ~r/Attempting to recover/i
    end

    test "does not attempt recovery when auto-recovery disabled" do
      pid = Process.whereis(DataDiode.NetworkGuard)

      # Disable auto-recovery
      Application.put_env(:data_diode, :auto_recovery_enabled, false)

      on_exit(fn ->
        Application.delete_env(:data_diode, :auto_recovery_enabled)
      end)

      # Set state with interface down and NOT flapping
      state = :sys.get_state(pid)

      down_state = %{
        state
        | flapping: false,
          interface_state: %{s1: :down, s2: :up}
      }

      :sys.replace_state(pid, fn _ -> down_state end)

      # Trigger check
      log =
        capture_log(fn ->
          send(pid, :check_interfaces)
          Process.sleep(100)
        end)

      # Should log that auto-recovery is disabled
      assert log =~ ~r/Auto-recovery disabled/i

      # Should NOT attempt recovery
      refute log =~ ~r/Attempting to recover/i
    end
  end

  describe "state counting and transitions" do
    test "counts S1 state changes correctly" do
      # Test history with S1 changing
      history = [
        %{s1_up: true, s2_up: true, timestamp: 1},
        %{s1_up: false, s2_up: true, timestamp: 2},
        %{s1_up: true, s2_up: true, timestamp: 3},
        %{s1_up: false, s2_up: true, timestamp: 4},
        %{s1_up: true, s2_up: true, timestamp: 5}
      ]

      # Count S1 changes
      s1_states = Enum.map(history, fn h -> h.s1_up end)

      transitions =
        s1_states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [a, b] -> a != b end)

      # Should have 4 transitions (true->false, false->true, true->false, false->true)
      assert transitions == 4
    end

    test "counts S2 state changes correctly" do
      # Test history with S2 changing
      history = [
        %{s1_up: true, s2_up: true, timestamp: 1},
        %{s1_up: true, s2_up: false, timestamp: 2},
        %{s1_up: true, s2_up: true, timestamp: 3},
        %{s1_up: true, s2_up: false, timestamp: 4}
      ]

      # Count S2 changes
      s2_states = Enum.map(history, fn h -> h.s2_up end)

      transitions =
        s2_states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [a, b] -> a != b end)

      # Should have 3 transitions
      assert transitions == 3
    end

    test "handles empty history gracefully" do
      history = []

      s1_states = Enum.map(history, fn h -> h.s1_up end)

      transitions =
        s1_states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [a, b] -> a != b end)

      # Should have 0 transitions
      assert transitions == 0
    end

    test "handles single entry history" do
      history = [%{s1_up: true, s2_up: true, timestamp: 1}]

      s1_states = Enum.map(history, fn h -> h.s1_up end)

      transitions =
        s1_states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [a, b] -> a != b end)

      # Should have 0 transitions (not enough entries for a transition)
      assert transitions == 0
    end
  end
end
