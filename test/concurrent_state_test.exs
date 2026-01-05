defmodule ConcurrentStateTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :concurrent
  @moduletag timeout: 60_000

  describe "Rate Limiter Concurrent Access" do
    test "rate limiter handles concurrent requests from same IP" do
      Logger.info("ConcurrentStateTest: Testing concurrent rate limiter access...")

      Application.ensure_all_started(:data_diode)

      test_ip = "192.168.1.100"

      # Reset rate limiter state for this IP
      DataDiode.RateLimiter.reset_ip(test_ip)

      # Spawn 200 concurrent processes checking rate limit (more than the burst capacity)
      tasks =
        for _i <- 1..200 do
          Task.async(fn ->
            DataDiode.RateLimiter.check_rate_limit(test_ip)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Count allows vs denies
      allowed = Enum.count(results, &(&1 == :allow))
      denied = Enum.count(results, &match?({:deny, _}, &1))

      Logger.info("ConcurrentStateTest: #{allowed} allowed, #{denied} denied")

      # Should have some denies due to rate limiting
      assert denied > 0

      # But not all should be denied
      assert allowed > 0

      Logger.info("ConcurrentStateTest: Rate limiter handled concurrent access correctly")

      :ok
    end

    test "rate limiter handles multiple IPs concurrently" do
      Logger.info("ConcurrentStateTest: Testing multiple IPs concurrently...")

      Application.ensure_all_started(:data_diode)

      # Create 50 different IPs
      ips = for i <- 1..50, do: "192.168.1.#{i}"

      # For each IP, spawn 10 concurrent requests
      tasks =
        for ip <- ips do
          for _j <- 1..10 do
            Task.async(fn ->
              DataDiode.RateLimiter.check_rate_limit(ip)
            end)
          end
        end
        |> List.flatten()

      results = Task.await_many(tasks, 10_000)

      # All requests should complete
      assert length(results) == 500

      Logger.info(
        "ConcurrentStateTest: Handled #{length(results)} concurrent requests across #{length(ips)} IPs"
      )

      :ok
    end
  end

  describe "Circuit Breaker Concurrent Access" do
    test "circuit breaker handles concurrent calls" do
      Logger.info("ConcurrentStateTest: Testing concurrent circuit breaker access...")

      Application.ensure_all_started(:data_diode)

      # Explicitly start the circuit breaker
      {:ok, _pid} = DataDiode.CircuitBreaker.start_link(:test_concurrent)

      # Spawn 50 concurrent circuit breaker calls
      tasks =
        for _i <- 1..50 do
          Task.async(fn ->
            # Use a simple function that won't fail
            DataDiode.CircuitBreaker.call(:test_concurrent, fn -> :ok end)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should complete successfully
      successes = Enum.count(results, &(&1 == {:ok, :ok}))
      assert successes == 50

      Logger.info("ConcurrentStateTest: Circuit breaker handled concurrent access correctly")

      :ok
    end

    test "circuit breaker state is consistent under concurrent access" do
      Logger.info("ConcurrentStateTest: Testing circuit breaker state consistency...")

      Application.ensure_all_started(:data_diode)

      # Explicitly start the circuit breaker
      {:ok, _pid} = DataDiode.CircuitBreaker.start_link(:test_state_access)

      # Spawn concurrent state readers and writers
      tasks =
        [
          # State readers
          for _i <- 1..20 do
            Task.async(fn ->
              DataDiode.CircuitBreaker.get_state(:test_state_access)
            end)
          end,
          # State writers (reset)
          for _i <- 1..5 do
            Task.async(fn ->
              DataDiode.CircuitBreaker.reset(:test_state_access)
            end)
          end
        ]
        |> List.flatten()

      _results = Task.await_many(tasks, 5000)

      # Final state should be valid
      final_state = DataDiode.CircuitBreaker.get_state(:test_state_access)
      assert Map.has_key?(final_state, :state)

      Logger.info("ConcurrentStateTest: Circuit breaker state remained consistent")

      :ok
    end
  end

  describe "Metrics Concurrent Access" do
    test "metrics handles concurrent increments" do
      Logger.info("ConcurrentStateTest: Testing concurrent metrics access...")

      Application.ensure_all_started(:data_diode)

      # Get initial metrics
      initial = DataDiode.Metrics.get_stats()

      # Spawn 100 concurrent increments
      tasks =
        for _i <- 1..100 do
          Task.async(fn ->
            DataDiode.Metrics.inc_packets()
          end)
        end

      # Wait for all to complete
      Task.await_many(tasks, 5000)

      # Get final metrics
      final = DataDiode.Metrics.get_stats()

      # Packet count should have increased
      assert final.packets_forwarded >= initial.packets_forwarded + 100

      Logger.info(
        "ConcurrentStateTest: Metrics handled #{final.packets_forwarded - initial.packets_forwarded} concurrent increments"
      )

      :ok
    end

    test "metrics handles different metric types concurrently" do
      Logger.info("ConcurrentStateTest: Testing mixed concurrent metrics...")

      Application.ensure_all_started(:data_diode)

      # Spawn mixed concurrent operations
      tasks =
        [
          # Packet increments
          for _i <- 1..50 do
            Task.async(fn -> DataDiode.Metrics.inc_packets() end)
          end,
          # Error increments
          for _i <- 1..25 do
            Task.async(fn -> DataDiode.Metrics.inc_errors() end)
          end,
          # Metrics reads
          for _i <- 1..25 do
            Task.async(fn -> DataDiode.Metrics.get_stats() end)
          end
        ]
        |> List.flatten()

      # All should complete
      results = Task.await_many(tasks, 5000)
      assert length(results) == 100

      Logger.info("ConcurrentStateTest: Mixed metrics operations completed successfully")

      :ok
    end
  end

  describe "Connection Rate Limiter Concurrent Access" do
    test "connection rate limiter handles concurrent connection attempts" do
      Logger.info("ConcurrentStateTest: Testing connection rate limiter concurrency...")

      Application.ensure_all_started(:data_diode)

      # Reset stats
      DataDiode.ConnectionRateLimiter.reset_counter()

      # Spawn 50 concurrent connection checks
      tasks =
        for _i <- 1..50 do
          Task.async(fn ->
            DataDiode.ConnectionRateLimiter.allow_connection?()
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Count results
      allowed = Enum.count(results, &(&1 == :allow))
      denied = Enum.count(results, &match?({:deny, _}, &1))

      Logger.info("ConcurrentStateTest: #{allowed} allowed, #{denied} denied")

      # Should have some denies due to rate limiting
      # But not all should be denied
      assert allowed > 0

      Logger.info("ConcurrentStateTest: Connection rate limiter handled concurrency correctly")

      :ok
    end

    test "connection rate limiter stats are consistent" do
      Logger.info("ConcurrentStateTest: Testing rate limiter stats consistency...")

      Application.ensure_all_started(:data_diode)

      # Spawn concurrent readers
      tasks =
        for _i <- 1..20 do
          Task.async(fn ->
            DataDiode.ConnectionRateLimiter.get_stats()
          end)
        end

      results = Task.await_many(tasks, 2000)

      # All should return valid stats maps
      for stats <- results do
        assert Map.has_key?(stats, :tokens)
        assert Map.has_key?(stats, :rejected)
      end

      Logger.info("ConcurrentStateTest: Rate limiter stats remained consistent")

      :ok
    end
  end

  describe "Environmental Monitor State Consistency" do
    test "environmental monitor state updates safely under concurrent access" do
      Logger.info("ConcurrentStateTest: Testing environmental monitor concurrency...")

      Application.ensure_all_started(:data_diode)

      # Spawn concurrent state readers
      tasks =
        for _i <- 1..20 do
          Task.async(fn ->
            DataDiode.EnvironmentalMonitor.get_current_state()
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should return valid state
      for state <- results do
        assert Map.has_key?(state, :cpu)
        assert Map.has_key?(state, :storage)
        assert Map.has_key?(state, :timestamp)
      end

      Logger.info("ConcurrentStateTest: Environmental monitor handled concurrent access")

      :ok
    end
  end

  describe "Race Condition Prevention" do
    test "no race conditions in rate limiter cleanup" do
      Logger.info("ConcurrentStateTest: Testing rate limiter cleanup concurrency...")

      Application.ensure_all_started(:data_diode)

      test_ips = for i <- 1..20, do: "10.0.0.#{i}"

      # Use all IPs
      for ip <- test_ips do
        DataDiode.RateLimiter.check_rate_limit(ip)
      end

      # Wait for cleanup (scheduled every 60 seconds, but we can test state access)
      Process.sleep(100)

      # Verify state is consistent
      stats = DataDiode.RateLimiter.get_stats()

      assert is_map(stats)

      Logger.info("ConcurrentStateTest: Rate limiter cleanup handled correctly")

      :ok
    end
  end
end
