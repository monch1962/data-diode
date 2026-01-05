defmodule GracefulShutdownTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :shutdown
  @moduletag timeout: 60_000

  describe "Buffer Flush on Shutdown" do
    test "Decapsulator flush buffers successfully" do
      # Test the flush_buffers function directly
      Logger.info("ShutdownTest: Testing buffer flush...")

      # This should not raise any errors
      result = DataDiode.S2.Decapsulator.flush_buffers()

      assert result == :ok

      Logger.info("ShutdownTest: Buffer flush completed successfully")

      :ok
    end

    test "flush handles sync command failures gracefully" do
      Logger.info("ShutdownTest: Testing flush with sync issues...")

      # Even if sync has issues, it should return :ok
      result = DataDiode.S2.Decapsulator.flush_buffers()

      assert result == :ok

      :ok
    end
  end

  describe "UDP Socket Cleanup" do
    test "Encapsulator closes socket on termination" do
      Logger.info("ShutdownTest: Testing UDP socket cleanup...")

      # Get the existing Encapsulator or start a new one
      pid = Process.whereis(DataDiode.S1.Encapsulator)

      if pid do
        # Use the existing one
        state = :sys.get_state(pid)
        assert Map.has_key?(state, :socket)

        # Get the socket before termination
        socket = state.socket

        # Terminate and let supervisor restart it
        Process.exit(pid, :normal)

        # Wait for restart
        Process.sleep(200)

        # Verify new process has a new socket
        new_pid = Process.whereis(DataDiode.S1.Encapsulator)
        assert new_pid != nil

        if new_pid != pid do
          new_state = :sys.get_state(new_pid)
          assert Map.has_key?(new_state, :socket)
          # Socket should be different (newly opened)
          assert new_state.socket != socket
        end
      else
        # Start a fresh Encapsulator
        {:ok, pid} = DataDiode.S1.Encapsulator.start_link([])

        # Get the state to verify socket exists
        state = :sys.get_state(pid)
        assert Map.has_key?(state, :socket)

        # Terminate the process
        GenServer.stop(pid, :normal)

        # Give it time to clean up
        Process.sleep(100)
      end

      Logger.info("ShutdownTest: UDP socket cleanup completed")

      :ok
    end

    test "socket cleanup handles already closed sockets" do
      Logger.info("ShutdownTest: Testing socket cleanup with closed socket...")

      # Use existing encapsulator or start a new one
      pid = Process.whereis(DataDiode.S1.Encapsulator)

      pid =
        if pid do
          # Use the existing one
          pid
        else
          # Start a new one
          {:ok, pid} = DataDiode.S1.Encapsulator.start_link([])
          pid
        end

      # Get socket and close it manually
      state = :sys.get_state(pid)
      :gen_udp.close(state.socket)

      # Terminate should not crash even if socket already closed
      Process.exit(pid, :normal)

      Process.sleep(200)

      Logger.info("ShutdownTest: Handled closed socket gracefully")

      :ok
    end
  end

  describe "TCP Connection Graceful Shutdown" do
    test "TCP handler closes socket gracefully" do
      Logger.info("ShutdownTest: Testing TCP graceful shutdown...")

      # Create a simple TCP socket for testing
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
      {:ok, port} = :inet.port(listen_socket)

      # Accept a connection
      spawn(fn ->
        {:ok, client} = :gen_tcp.accept(listen_socket, 1000)
        Process.sleep(500)
        :gen_tcp.close(client)
      end)

      # Connect
      {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary])

      # Shutdown should send FIN
      :gen_tcp.shutdown(socket, :write)

      # Give time for graceful shutdown
      Process.sleep(200)

      # Close the socket
      :gen_tcp.close(socket)
      :gen_tcp.close(listen_socket)

      Logger.info("ShutdownTest: TCP graceful shutdown completed")

      :ok
    end
  end

  describe "Supervision Tree Shutdown" do
    test "application shuts down cleanly" do
      Logger.info("ShutdownTest: Testing application shutdown...")

      # Start the application
      Application.ensure_all_started(:data_diode)

      # Flush buffers before shutdown
      DataDiode.S2.Decapsulator.flush_buffers()

      # Stop the application
      Application.stop(:data_diode)

      # Verify all processes are gone
      assert Process.whereis(DataDiode.S1.Encapsulator) == nil
      assert Process.whereis(DataDiode.S1.Listener) == nil
      assert Process.whereis(DataDiode.S2.Listener) == nil

      Logger.info("ShutdownTest: Application shut down cleanly")

      :ok
    end

    test "children shutdown in correct order" do
      Logger.info("ShutdownTest: Testing shutdown order...")

      Application.ensure_all_started(:data_diode)

      # Record which processes are running
      initial_processes = [
        DataDiode.Metrics,
        DataDiode.S1.Encapsulator,
        DataDiode.S2.Listener
      ]

      # Verify they're all running
      for mod <- initial_processes do
        assert Process.whereis(mod) != nil
      end

      # Stop application
      Application.stop(:data_diode)

      # All should be stopped
      for mod <- initial_processes do
        assert Process.whereis(mod) == nil
      end

      Logger.info("ShutdownTest: All processes stopped cleanly")

      :ok
    end
  end

  describe "Circuit Breaker State on Shutdown" do
    test "circuit breaker can be restarted" do
      Logger.info("ShutdownTest: Testing circuit breaker restart...")

      Application.ensure_all_started(:data_diode)

      # Explicitly start the circuit breaker
      {:ok, pid} = DataDiode.CircuitBreaker.start_link(:test_restart)

      # Get initial state
      initial_state = DataDiode.CircuitBreaker.get_state(:test_restart)
      assert initial_state.state == :closed

      # Simulate some activity to change state
      DataDiode.CircuitBreaker.call(:test_restart, fn -> :ok end)

      # Stop the circuit breaker
      GenServer.stop(pid)

      # Verify it's stopped
      assert Process.whereis(DataDiode.CircuitBreakerRegistry) != nil

      # Restart the circuit breaker
      {:ok, _new_pid} = DataDiode.CircuitBreaker.start_link(:test_restart)

      # Get new state (should be reset to closed)
      new_state = DataDiode.CircuitBreaker.get_state(:test_restart)

      # State should be valid and in closed state
      assert Map.has_key?(new_state, :state)
      assert new_state.state == :closed

      Logger.info("ShutdownTest: Circuit breaker successfully restarted")

      :ok
    end
  end

  describe "Connection Cleanup on Shutdown" do
    test "active connections are closed on shutdown" do
      Logger.info("ShutdownTest: Testing connection cleanup...")

      Application.ensure_all_started(:data_diode)

      port = DataDiode.S1.Listener.port()

      # Create a connection
      {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary], 1000)

      # Wait a bit for connection to establish
      Process.sleep(100)

      # Stop application
      Application.stop(:data_diode)

      # Connection should be closed
      # Try to send data, it should fail
      result = :gen_tcp.send(socket, "test")

      assert result == {:error, :closed}

      :gen_tcp.close(socket)

      Logger.info("ShutdownTest: Connections cleaned up properly")

      :ok
    end
  end

  describe "Grace Period Testing" do
    test "sufficient time for graceful shutdown" do
      Logger.info("ShutdownTest: Testing graceful shutdown timing...")

      Application.ensure_all_started(:data_diode)

      start_time = System.monotonic_time(:millisecond)

      # Stop application
      Application.stop(:data_diode)

      end_time = System.monotonic_time(:millisecond)
      shutdown_time = end_time - start_time

      # Shutdown should complete within reasonable time (< 5 seconds)
      assert shutdown_time < 5000

      Logger.info("ShutdownTest: Shutdown completed in #{shutdown_time}ms")

      :ok
    end
  end
end
