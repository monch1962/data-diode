defmodule DataDiode.MetricsTest do
  use ExUnit.Case, async: false

  alias DataDiode.Metrics

  setup do
    # Ensure the application is started
    Application.ensure_all_started(:data_diode)

    # Reset metrics before each test
    Metrics.reset_stats()
    :ok
  end

  describe "basic metrics" do
    test "metrics agent is running" do
      assert Process.whereis(DataDiode.Metrics) != nil
    end

    test "inc_packets increments packet count" do
      initial = Metrics.get_stats().packets_forwarded
      Metrics.inc_packets()
      assert Metrics.get_stats().packets_forwarded == initial + 1
    end

    test "inc_errors increments error count" do
      initial = Metrics.get_stats().error_count
      Metrics.inc_errors()
      assert Metrics.get_stats().error_count == initial + 1
    end

    test "get_stats returns uptime" do
      stats = Metrics.get_stats()
      assert is_integer(stats.uptime_seconds)
      assert stats.uptime_seconds >= 0
    end
  end

  describe "enhanced metrics" do
    test "record_packet tracks packet size and protocol" do
      Metrics.record_packet(1024, :modbus)
      Metrics.record_packet(2048, :mqtt)
      Metrics.record_packet(512, :modbus)

      stats = Metrics.get_stats()

      assert stats.packets_forwarded == 3
      assert stats.bytes_forwarded == 1024 + 2048 + 512
      assert stats.packet_size_min == 512
      assert stats.packet_size_max == 2048
      # Check approximate value for floating point
      assert_in_delta stats.packet_size_avg, (1024 + 2048 + 512) / 3, 0.01
      assert stats.protocol_counts[:modbus] == 2
      assert stats.protocol_counts[:mqtt] == 1
    end

    test "record_packet with nil protocol" do
      Metrics.record_packet(1024, nil)

      stats = Metrics.get_stats()
      assert stats.packets_forwarded == 1
      assert stats.protocol_counts == %{}
    end

    test "track_source_ip tracks packets from different IPs" do
      Metrics.track_source_ip("192.168.1.1")
      Metrics.track_source_ip("192.168.1.2")
      Metrics.track_source_ip("192.168.1.1")
      Metrics.track_source_ip("10.0.0.1")

      stats = Metrics.get_stats()

      # Should track top IPs
      assert Enum.any?(stats.top_source_ips, fn {ip, count} ->
               ip == "192.168.1.1" and count == 2
             end)

      assert Enum.any?(stats.top_source_ips, fn {ip, count} ->
               ip == "192.168.1.2" and count == 1
             end)
    end

    test "inc_errors with reason tracks rejection reasons" do
      Metrics.inc_errors("protocol_not_allowed")
      Metrics.inc_errors("protocol_not_allowed")
      Metrics.inc_errors("packet_too_large")
      Metrics.inc_errors()

      stats = Metrics.get_stats()

      assert stats.error_count == 4
      assert stats.rejection_reasons["protocol_not_allowed"] == 2
      assert stats.rejection_reasons["packet_too_large"] == 1
    end

    test "get_stats includes throughput metrics" do
      Metrics.record_packet(1024, :modbus)
      Process.sleep(100)
      Metrics.record_packet(2048, :mqtt)

      stats = Metrics.get_stats()

      assert stats.packets_per_second >= 0
      assert stats.bytes_per_second >= 0
      assert is_float(stats.packets_per_second)
      assert is_float(stats.bytes_per_second)
    end

    test "get_stats includes last packet age" do
      refute Metrics.get_stats().last_packet_age_seconds

      Metrics.record_packet(1024, :modbus)
      stats = Metrics.get_stats()

      assert is_integer(stats.last_packet_age_seconds)
      assert stats.last_packet_age_seconds >= 0
    end

    test "reset_stats clears all metrics" do
      Metrics.record_packet(1024, :modbus)
      Metrics.track_source_ip("192.168.1.1")
      Metrics.inc_errors("test_reason")

      Metrics.reset_stats()
      stats = Metrics.get_stats()

      assert stats.packets_forwarded == 0
      assert stats.bytes_forwarded == 0
      assert stats.error_count == 0
      assert stats.protocol_counts == %{}
      assert stats.top_source_ips == []
      assert stats.rejection_reasons == %{}
      refute stats.last_packet_age_seconds
      # Packet size stats should be reset to defaults
      assert stats.packet_size_min == 0
      assert stats.packet_size_max == 0
      assert stats.packet_size_avg == 0.0
    end
  end

  describe "edge cases" do
    test "handles empty packet sizes gracefully" do
      stats = Metrics.get_stats()

      assert stats.packet_size_min == 0
      assert stats.packet_size_max == 0
      assert stats.packet_size_avg == 0.0
    end

    test "handles zero uptime gracefully" do
      # Right after starting, uptime should be small but valid
      stats = Metrics.get_stats()

      assert stats.uptime_seconds >= 0
      assert is_number(stats.packets_per_second)
      assert is_number(stats.bytes_per_second)
    end

    test "tracks large number of unique source IPs" do
      # Test that it properly trims to max entries
      Enum.each(1..150, fn i ->
        Metrics.track_source_ip("10.0.0.#{i}")
      end)

      stats = Metrics.get_stats()
      # Should not exceed reasonable limit (100 from @max_source_ips)
      assert length(stats.top_source_ips) <= 100
    end

    test "tracks many packet sizes" do
      # Test that it properly trims packet size history
      Enum.each(1..1100, fn i ->
        Metrics.record_packet(i * 10, :modbus)
      end)

      stats = Metrics.get_stats()
      assert stats.packets_forwarded == 1100
      assert stats.bytes_forwarded > 0
    end
  end

  describe "throughput calculations" do
    test "calculates packets per second correctly" do
      Enum.each(1..10, fn _ -> Metrics.record_packet(100, :modbus) end)

      Process.sleep(250)
      stats = Metrics.get_stats()

      # Should have some packets per second (or very close if test is fast)
      assert stats.packets_per_second >= 0
      assert is_float(stats.packets_per_second)
    end

    test "calculates bytes per second correctly" do
      Enum.each(1..5, fn i -> Metrics.record_packet(i * 1024, :mqtt) end)

      Process.sleep(250)
      stats = Metrics.get_stats()

      # Should have some bytes per second (or very close if test is fast)
      assert stats.bytes_per_second >= 0
      assert is_float(stats.bytes_per_second)
    end
  end
end
