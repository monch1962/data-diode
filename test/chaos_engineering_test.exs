defmodule ChaosEngineeringTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :chaos
  @moduletag timeout: 120_000

  setup do
    # Ensure application is started
    Application.ensure_all_started(:data_diode)
    :ok
  end

  describe "Process Failure Chaos" do
    test "system continues when Encapsulator crashes" do
      encapsulator_pid = Process.whereis(DataDiode.S1.Encapsulator)
      assert encapsulator_pid != nil

      initial_metrics = DataDiode.Metrics.get_stats()

      Logger.info("ChaosTest: Crashing Encapsulator...")
      Process.exit(encapsulator_pid, :kill)

      Process.sleep(500)

      restarted_pid = Process.whereis(DataDiode.S1.Encapsulator)
      assert restarted_pid != nil
      refute restarted_pid == encapsulator_pid

      Logger.info("ChaosTest: Encapsulator restarted successfully")
      assert Process.whereis(DataDiode.S1.Listener) != nil

      :ok
    end

    test "system continues when S2 Listener crashes" do
      listener_pid = Process.whereis(DataDiode.S2.Listener)
      assert listener_pid != nil

      Logger.info("ChaosTest: Crashing S2 Listener...")
      Process.exit(listener_pid, :kill)

      Process.sleep(500)

      restarted_pid = Process.whereis(DataDiode.S2.Listener)
      assert restarted_pid != nil
      refute restarted_pid == listener_pid

      Logger.info("ChaosTest: S2 Listener restarted successfully")
      :ok
    end

    test "system handles multiple simultaneous process crashes" do
      encapsulator = Process.whereis(DataDiode.S1.Encapsulator)
      s1_listener = Process.whereis(DataDiode.S1.Listener)
      s2_listener = Process.whereis(DataDiode.S2.Listener)

      Logger.info("ChaosTest: Crashing multiple processes simultaneously...")

      Process.exit(encapsulator, :kill)
      Process.exit(s1_listener, :kill)
      Process.exit(s2_listener, :kill)

      Process.sleep(1000)

      assert Process.whereis(DataDiode.S1.Encapsulator) != nil
      assert Process.whereis(DataDiode.S1.Listener) != nil
      assert Process.whereis(DataDiode.S2.Listener) != nil

      Logger.info("ChaosTest: All processes recovered successfully")
      :ok
    end
  end

  describe "Resource Exhaustion Chaos" do
    test "system handles rapid connection attempts" do
      Logger.info("ChaosTest: Testing connection rate limiting...")

      port = DataDiode.S1.Listener.port()

      tasks =
        for _i <- 1..50 do
          Task.async(fn ->
            case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary], 1000) do
              {:ok, socket} ->
                :gen_tcp.close(socket)
                :connected

              {:error, _reason} ->
                :failed
            end
          end)
        end

      results = Task.await_many(tasks, 5000)

      connected = Enum.count(results, &(&1 == :connected))
      failed = Enum.count(results, &(&1 == :failed))

      Logger.info("ChaosTest: #{connected} connected, #{failed} failed")

      assert Process.whereis(DataDiode.S1.Listener) != nil

      stats = DataDiode.ConnectionRateLimiter.get_stats()
      Logger.info("ChaosTest: Rate limiter stats: #{inspect(stats)}")

      :ok
    end

    test "system handles memory pressure" do
      Logger.info("ChaosTest: Simulating memory pressure...")

      initial_memory = :erlang.memory(:total)

      large_binary = :binary.copy(<<1>>, 10_000_000)

      Process.sleep(100)

      assert Process.whereis(DataDiode.S1.Encapsulator) != nil
      assert Process.whereis(DataDiode.S2.Listener) != nil

      :binary.part(large_binary, 0, 0)

      Logger.info("ChaosTest: System responsive under memory pressure")
      :ok
    end
  end

  describe "Circuit Breaker Chaos" do
    test "circuit breaker state is accessible" do
      Logger.info("ChaosTest: Testing circuit breaker...")

      # Explicitly start the circuit breaker
      {:ok, _pid} = DataDiode.CircuitBreaker.start_link(:udp_send)

      DataDiode.CircuitBreaker.reset(:udp_send)

      initial_state = DataDiode.CircuitBreaker.get_state(:udp_send)
      Logger.info("ChaosTest: Initial state: #{inspect(initial_state)}")

      assert Map.has_key?(initial_state, :state)

      :ok
    end

    test "circuit breaker state persists across calls" do
      # Explicitly start the circuit breaker
      {:ok, _pid} = DataDiode.CircuitBreaker.start_link(:udp_send)

      DataDiode.CircuitBreaker.reset(:udp_send)

      state1 = DataDiode.CircuitBreaker.get_state(:udp_send)
      Process.sleep(100)
      state2 = DataDiode.CircuitBreaker.get_state(:udp_send)

      assert state1.state == state2.state

      :ok
    end
  end

  describe "Supervision Tree Recovery" do
    test "supervision tree restarts crashed processes" do
      metrics_pid = Process.whereis(DataDiode.Metrics)
      Process.exit(metrics_pid, :kill)

      Process.sleep(500)

      new_metrics_pid = Process.whereis(DataDiode.Metrics)
      assert new_metrics_pid != nil

      Logger.info("ChaosTest: Supervision tree working correctly")
      :ok
    end

    test "restart intensity not exceeded under normal crashes" do
      for _i <- 1..3 do
        pid = Process.whereis(DataDiode.S1.Encapsulator)
        if pid, do: Process.exit(pid, :kill)
        Process.sleep(100)
      end

      Process.sleep(500)

      supervisor_pid = Process.whereis(DataDiode.Supervisor)
      assert supervisor_pid != nil

      assert Process.whereis(DataDiode.S1.Encapsulator) != nil

      Logger.info("ChaosTest: Supervision tree handled restarts correctly")
      :ok
    end
  end
end
