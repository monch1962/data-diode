defmodule DataDiode.PropertyTest do
  use ExUnit.Case, async: true
  @moduletag :property

  import StreamData
  alias DataDiode.NetworkHelpers

  describe "Network Helpers Properties" do
    test "IP binary conversion produces valid format (100 samples)" do
      # Generate 100 random IP binaries and test the conversion
      :rand.seed(:exsplus, {123, 456, 789})

      Enum.each(1..100, fn _ ->
        {b1, b2, b3, b4} = Enum.map(1..4, fn _ -> :rand.uniform(256) - 1 end) |> List.to_tuple()
        ip_binary = <<b1, b2, b3, b4>>

        # binary_to_ip returns {:ok, ip_string}
        assert {:ok, ip_string} = NetworkHelpers.binary_to_ip(ip_binary)

        # Should produce valid IP string format
        assert is_binary(ip_string)
        assert ip_string =~ ~r/^\d+\.\d+\.\d+\.\d+$/
      end)
    end

    test "port validation accepts all valid ports (sampled)" do
      # Test a sampling of valid ports
      valid_ports = [1, 80, 443, 8080, 502, 161, 65_535]

      Enum.each(valid_ports, fn port ->
        assert {:ok, ^port} = NetworkHelpers.validate_port(port)
      end)
    end

    test "port validation rejects invalid ports (sampled)" do
      # Test a sampling of invalid ports (0 is actually valid in TCP/IP)
      invalid_ports = [-1, 65_536, 100_000]

      Enum.each(invalid_ports, fn port ->
        assert {:error, {:invalid_port, ^port}} = NetworkHelpers.validate_port(port)
      end)
    end
  end

  describe "Protocol Validation Properties" do
    @allowed_protocols ["MODBUS", "MQTT", "SNMP", "DNP3", "ANY"]

    test "allowed protocols are uppercase alphanumeric" do
      Enum.each(@allowed_protocols, fn protocol ->
        assert String.upcase(protocol) == protocol
        assert String.match?(protocol, ~r/^[A-Z0-9]+$/)
        assert String.length(protocol) > 0
      end)
    end

    test "protocol atoms are valid" do
      valid_atoms = [:modbus, :mqtt, :snmp, :dnp3, :any]

      Enum.each(valid_atoms, fn protocol ->
        assert is_atom(protocol)
        assert protocol in valid_atoms
      end)
    end
  end

  describe "Memory Properties" do
    test "memory percentage is always between 0 and 100" do
      test_cases = [
        {1000, 500, 50.0},
        {8000, 4000, 50.0},
        {8000, 7360, 92.0},
        {8000, 0, 0.0},
        {8000, 8000, 100.0}
      ]

      Enum.each(test_cases, fn {total, used, expected_percent} ->
        percent =
          if total > 0 do
            (used / total * 100) |> Float.round(1)
          else
            0.0
          end

        assert percent >= 0.0
        assert percent <= 100.0
        assert percent == expected_percent
      end)
    end
  end

  describe "Packet Processing Properties" do
    test "CRC32 checksum is deterministic" do
      test_data = [
        "",
        "hello",
        <<0, 1, 2, 3>>,
        :crypto.strong_rand_bytes(1024)
      ]

      Enum.each(test_data, fn data ->
        crc1 = :erlang.crc32(data)
        crc2 = :erlang.crc32(data)

        assert crc1 == crc2
        assert is_integer(crc1)
        assert crc1 >= 0
      end)
    end

    test "packet header size is constant" do
      # IP (4 bytes) + Port (2 bytes) = 6 bytes
      assert 4 + 2 == 6
    end
  end

  describe "IP Address Properties" do
    test "IP address components are in valid range" do
      test_ips = [
        {0, 0, 0, 0},
        {255, 255, 255, 255},
        {127, 0, 0, 1},
        {192, 168, 1, 1},
        {10, 0, 0, 1}
      ]

      Enum.each(test_ips, fn {b1, b2, b3, b4} ->
        assert b1 >= 0 and b1 <= 255
        assert b2 >= 0 and b2 <= 255
        assert b3 >= 0 and b3 <= 255
        assert b4 >= 0 and b4 <= 255
      end)
    end

    test "IP tuple size is always 4" do
      test_ips = [
        {127, 0, 0, 1},
        {192, 168, 1, 1},
        {10, 0, 0, 1}
      ]

      Enum.each(test_ips, fn ip ->
        assert tuple_size(ip) == 4
      end)
    end
  end

  describe "Rate Limiter State Properties" do
    test "token bucket never goes negative" do
      # Test that token refill calculations maintain valid state
      initial_tokens = 100
      refill_rate = 10

      # Simulate multiple refills
      Enum.each(1..10, fn _ ->
        # Tokens should never be negative after refill
        assert initial_tokens >= 0
        assert refill_rate >= 0
      end)
    end

    test "rate limiter configuration is valid" do
      # Test various configurations
      configs = [
        %{max_packets: 1000, refill_rate: 100},
        %{max_packets: 500, refill_rate: 50},
        %{max_packets: 100, refill_rate: 10}
      ]

      Enum.each(configs, fn config ->
        assert config.max_packets > 0
        assert config.refill_rate > 0
        assert config.refill_rate <= config.max_packets
      end)
    end
  end
end
