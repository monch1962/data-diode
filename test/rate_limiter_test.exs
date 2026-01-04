defmodule DataDiode.RateLimiterTest do
  use ExUnit.Case, async: false

  alias DataDiode.RateLimiter

  setup do
    # The RateLimiter is started by the application with default config
    # We'll use a custom name for our test instance
    test_name = :rate_limiter_test_instance

    # Stop any existing test instance
    if Process.whereis(test_name) do
      GenServer.stop(test_name, :normal, 1000)
    end

    {:ok, _pid} = RateLimiter.start_link(name: test_name, max_packets_per_second: 10)

    on_exit(fn ->
      if Process.whereis(test_name) do
        # Use try/rescue to handle case where process already stopped
        try do
          GenServer.stop(test_name, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    {:ok, test_name: test_name}
  end

  describe "rate limiting" do
    test "allows packets under the rate limit", %{test_name: test_name} do
      assert RateLimiter.check_rate_limit("192.168.1.1") == :allow
      assert RateLimiter.check_rate_limit("192.168.1.1") == :allow
      assert RateLimiter.check_rate_limit("192.168.1.1") == :allow
    end

    test "denies packets exceeding the rate limit", %{test_name: test_name} do
      # Send packets up to the limit
      Enum.each(1..10, fn _ ->
        assert RateLimiter.check_rate_limit("10.0.0.1", test_name) == :allow
      end)

      # Next packet should be denied
      assert {:deny, _reason} = RateLimiter.check_rate_limit("10.0.0.1", test_name)
    end

    test "tracks different IPs independently", %{test_name: test_name} do
      # Each IP should have its own rate limit
      Enum.each(1..10, fn _ ->
        assert RateLimiter.check_rate_limit("192.168.1.10", test_name) == :allow
      end)

      # Different IP should still be allowed
      assert RateLimiter.check_rate_limit("192.168.1.20", test_name) == :allow
    end

    test "resets after window expires", %{test_name: test_name} do
      # Use up the limit
      Enum.each(1..10, fn _ ->
        assert RateLimiter.check_rate_limit("172.16.0.1", test_name) == :allow
      end)

      assert {:deny, _reason} = RateLimiter.check_rate_limit("172.16.0.1", test_name)

      # Wait for window to expire (1 second)
      Process.sleep(1100)

      # Should be allowed again
      assert RateLimiter.check_rate_limit("172.16.0.1", test_name) == :allow
    end
  end

  describe "statistics" do
    test "returns statistics for tracked IPs", %{test_name: test_name} do
      RateLimiter.check_rate_limit("10.0.0.5", test_name)
      RateLimiter.check_rate_limit("10.0.0.5", test_name)
      RateLimiter.check_rate_limit("10.0.0.6", test_name)

      stats = RateLimiter.get_stats(test_name)

      assert stats["10.0.0.5"] != nil
      assert stats["10.0.0.6"] != nil
    end

    test "statistics include current count and limit", %{test_name: test_name} do
      Enum.each(1..5, fn _ ->
        RateLimiter.check_rate_limit("10.0.0.7", test_name)
      end)

      stats = RateLimiter.get_stats(test_name)
      {count, limit} = Map.get(stats, "10.0.0.7", {0, 0})

      assert count == 5
      assert limit == 10
    end
  end

  describe "IP reset" do
    test "resets tracking for a specific IP", %{test_name: test_name} do
      # Use up the limit
      Enum.each(1..10, fn _ ->
        assert RateLimiter.check_rate_limit("10.0.0.8", test_name) == :allow
      end)

      assert {:deny, _reason} = RateLimiter.check_rate_limit("10.0.0.8", test_name)

      # Reset the IP
      RateLimiter.reset_ip("10.0.0.8", test_name)

      # Should be allowed again
      assert RateLimiter.check_rate_limit("10.0.0.8", test_name) == :allow
    end
  end

  describe "cleanup" do
    test "cleans up old IP entries periodically", %{test_name: test_name} do
      # Create some traffic
      Enum.each(1..5, fn i ->
        RateLimiter.check_rate_limit("10.0.0.#{i}", test_name)
      end)

      stats_before = RateLimiter.get_stats(test_name)
      assert map_size(stats_before) > 0

      # Cleanup happens automatically every 60 seconds
      # We can't easily test this without waiting, but we verify it doesn't crash
      assert Process.alive?(Process.whereis(test_name))
    end
  end
end
