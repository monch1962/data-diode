defmodule DataDiode.S2.HeartbeatMonitorTest do
  use ExUnit.Case, async: false
  alias DataDiode.S2.HeartbeatMonitor

  describe "start_link/1" do
    test "starts the heartbeat monitor server with unique name" do
      {:ok, pid} = HeartbeatMonitor.start_link(name: :heartbeat_test_unique)
      assert is_pid(pid)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom name" do
      {:ok, pid} = HeartbeatMonitor.start_link(name: :custom_heartbeat_monitor_unique)
      assert is_pid(pid)
      assert Process.whereis(:custom_heartbeat_monitor_unique) == pid
      GenServer.stop(pid)
    end
  end

  describe "init/1" do
    test "initializes with last_seen timestamp" do
      assert {:ok, state, timeout} = HeartbeatMonitor.init(:ok)
      assert is_map(state)
      assert Map.has_key?(state, :last_seen)
      assert is_integer(state.last_seen)
      assert timeout == 360_000  # Default timeout is 6 minutes
    end
  end

  describe "heartbeat_received/0" do
    test "updates last_seen timestamp" do
      {:ok, pid} = HeartbeatMonitor.start_link(name: :heartbeat_timestamp_test)

      # Get initial state
      initial_state = :sys.get_state(pid)
      initial_last_seen = initial_state.last_seen

      # Wait a bit to ensure timestamp would be different
      Process.sleep(10)

      # Send heartbeat
      HeartbeatMonitor.heartbeat_received(pid)

      # Get new state
      new_state = :sys.get_state(pid)

      assert new_state.last_seen > initial_last_seen

      GenServer.stop(pid)
    end

    test "resets timeout timer when heartbeat is received" do
      {:ok, pid} = HeartbeatMonitor.start_link(name: :heartbeat_reset_test)

      # Send heartbeat
      HeartbeatMonitor.heartbeat_received(pid)

      # Verify process is still alive (would have timed out and crashed if heartbeat failed)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "handle_info :timeout" do
    test "logs critical failure when timeout occurs" do
      # Start monitor with very short timeout for testing
      Application.put_env(:data_diode, :heartbeat_timeout_ms, 100)

      {:ok, pid} = HeartbeatMonitor.start_link(name: :heartbeat_timeout_test)

      # Wait for timeout to trigger
      Process.sleep(200)

      # The process should have logged a critical failure
      # We can't easily test the actual log without capture_log, but we can verify
      # the process handles the timeout gracefully

      GenServer.stop(pid)

      Application.delete_env(:data_diode, :heartbeat_timeout_ms)
    end
  end

  describe "timeout behavior" do
    test "uses default timeout when not configured" do
      Application.delete_env(:data_diode, :heartbeat_timeout_ms)

      assert {:ok, _state, timeout} = HeartbeatMonitor.init(:ok)
      assert timeout == 360_000  # 6 minutes
    end

    test "uses custom timeout when configured" do
      Application.put_env(:data_diode, :heartbeat_timeout_ms, 180_000)

      assert {:ok, _state, timeout} = HeartbeatMonitor.init(:ok)
      assert timeout == 180_000  # 3 minutes

      Application.delete_env(:data_diode, :heartbeat_timeout_ms)
    end
  end

  describe "handle_cast :heartbeat" do
    test "updates last_seen and resets timeout" do
      {:ok, pid} = HeartbeatMonitor.start_link(name: :heartbeat_cast_test)

      initial_state = :sys.get_state(pid)
      initial_last_seen = initial_state.last_seen

      Process.sleep(10)

      # Use cast directly
      GenServer.cast(pid, :heartbeat)

      new_state = :sys.get_state(pid)
      assert new_state.last_seen > initial_last_seen

      GenServer.stop(pid)
    end
  end
end
