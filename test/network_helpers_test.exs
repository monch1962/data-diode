defmodule DataDiode.NetworkHelpersTest do
  use ExUnit.Case
  alias DataDiode.NetworkHelpers

  describe "parse_ip_address/1" do
    test "parses valid IPv4 addresses" do
      assert {:ok, {127, 0, 0, 1}} = NetworkHelpers.parse_ip_address_strict("127.0.0.1")
      assert {:ok, {192, 168, 1, 1}} = NetworkHelpers.parse_ip_address_strict("192.168.1.1")
      assert {:ok, {10, 0, 0, 1}} = NetworkHelpers.parse_ip_address_strict("10.0.0.1")
    end

    test "returns :any for nil" do
      assert :any = NetworkHelpers.parse_ip_address(nil)
    end

    test "returns :any for :any atom" do
      assert :any = NetworkHelpers.parse_ip_address(:any)
    end

    test "returns :any for empty string" do
      assert :any = NetworkHelpers.parse_ip_address("")
    end

    test "returns :any for '0.0.0.0'" do
      assert :any = NetworkHelpers.parse_ip_address("0.0.0.0")
    end

    test "returns :any for invalid IP address in lenient mode" do
      assert :any = NetworkHelpers.parse_ip_address("invalid")
      assert :any = NetworkHelpers.parse_ip_address("999.999.999.999")
    end

    test "returns error for invalid IP in strict mode" do
      assert :error = NetworkHelpers.parse_ip_address_strict("invalid")
      assert :error = NetworkHelpers.parse_ip_address_strict("999.999.999.999")
      assert :error = NetworkHelpers.parse_ip_address_strict(nil)
      assert :error = NetworkHelpers.parse_ip_address_strict("")
    end

    test "returns :any for non-binary input in lenient mode" do
      assert :any = NetworkHelpers.parse_ip_address(123)
      assert :any = NetworkHelpers.parse_ip_address({:tuple})
    end
  end

  describe "ip_to_string/1" do
    test "converts IP tuple to string" do
      assert "127.0.0.1" = NetworkHelpers.ip_to_string({127, 0, 0, 1})
      assert "192.168.1.1" = NetworkHelpers.ip_to_string({192, 168, 1, 1})
      assert "10.0.0.1" = NetworkHelpers.ip_to_string({10, 0, 0, 1})
    end

    test "returns binary as-is when input is string" do
      assert "127.0.0.1" = NetworkHelpers.ip_to_string("127.0.0.1")
      assert "test" = NetworkHelpers.ip_to_string("test")
    end
  end

  describe "binary_to_ip/1" do
    test "converts 4-byte binary to IP string" do
      assert {:ok, "127.0.0.1"} = NetworkHelpers.binary_to_ip(<<127, 0, 0, 1>>)
      assert {:ok, "192.168.1.1"} = NetworkHelpers.binary_to_ip(<<192, 168, 1, 1>>)
      assert {:ok, "0.0.0.0"} = NetworkHelpers.binary_to_ip(<<0, 0, 0, 0>>)
      assert {:ok, "255.255.255.255"} = NetworkHelpers.binary_to_ip(<<255, 255, 255, 255>>)
    end

    test "converts binary with all possible values" do
      assert {:ok, "1.2.3.4"} = NetworkHelpers.binary_to_ip(<<1, 2, 3, 4>>)
      assert {:ok, "248.16.32.64"} = NetworkHelpers.binary_to_ip(<<248, 16, 32, 64>>)
    end
  end

  describe "validate_port/1" do
    test "accepts valid port numbers" do
      assert {:ok, 0} = NetworkHelpers.validate_port(0)
      assert {:ok, 1} = NetworkHelpers.validate_port(1)
      assert {:ok, 80} = NetworkHelpers.validate_port(80)
      assert {:ok, 8080} = NetworkHelpers.validate_port(8080)
      assert {:ok, 65535} = NetworkHelpers.validate_port(65535)
    end

    test "rejects negative port numbers" do
      assert {:error, {:invalid_port, -1}} = NetworkHelpers.validate_port(-1)
      assert {:error, {:invalid_port, -100}} = NetworkHelpers.validate_port(-100)
    end

    test "rejects port numbers too large" do
      assert {:error, {:invalid_port, 65536}} = NetworkHelpers.validate_port(65536)
      assert {:error, {:invalid_port, 99999}} = NetworkHelpers.validate_port(99999)
    end

    test "rejects non-integer port numbers" do
      assert {:error, {:invalid_port, "8080"}} = NetworkHelpers.validate_port("8080")
      assert {:error, {:invalid_port, nil}} = NetworkHelpers.validate_port(nil)
      assert {:error, {:invalid_port, :atom}} = NetworkHelpers.validate_port(:atom)
      assert {:error, {:invalid_port, {1, 2, 3}}} = NetworkHelpers.validate_port({1, 2, 3})
    end

    test "rejects boundary port number 65536" do
      assert {:error, {:invalid_port, 65536}} = NetworkHelpers.validate_port(65536)
    end
  end

  describe "tcp_listen_options/1" do
    test "returns base options when ip is nil" do
      options = NetworkHelpers.tcp_listen_options(nil)

      assert :binary in options
      assert :inet in options
      assert {:reuseaddr, true} in options
      assert {:active, false} in options
    end

    test "returns base options when ip is :any" do
      options = NetworkHelpers.tcp_listen_options(:any)

      assert :binary in options
      assert :inet in options
      assert {:reuseaddr, true} in options
      assert {:active, false} in options
    end

    test "returns base options when ip is '0.0.0.0'" do
      options = NetworkHelpers.tcp_listen_options("0.0.0.0")

      assert :binary in options
      assert :inet in options
      assert {:reuseaddr, true} in options
      assert {:active, false} in options
    end

    test "includes IP when valid IP provided" do
      options = NetworkHelpers.tcp_listen_options("127.0.0.1")

      assert {:ip, {127, 0, 0, 1}} in options
    end

    test "includes IP when valid IP tuple provided" do
      options = NetworkHelpers.tcp_listen_options({192, 168, 1, 1})

      assert {:ip, {192, 168, 1, 1}} in options
    end

    test "handles invalid IP gracefully by using base options" do
      options = NetworkHelpers.tcp_listen_options("invalid-ip")

      assert :binary in options
      assert :inet in options
      assert {:reuseaddr, true} in options
      assert {:active, false} in options
      # Should not include :ip option
      refute Enum.any?(options, fn
        {:ip, _} -> true
        _ -> false
      end)
    end
  end

  describe "udp_listen_options/1" do
    test "returns base options when ip is nil" do
      options = NetworkHelpers.udp_listen_options(nil)

      assert :binary in options
      assert {active, :once} = Enum.find(options, fn
        {:active, _} -> true
        _ -> false
      end)
    end

    test "returns base options when ip is :any" do
      options = NetworkHelpers.udp_listen_options(:any)

      assert :binary in options
      assert {active, :once} = Enum.find(options, fn
        {:active, _} -> true
        _ -> false
      end)
    end

    test "returns base options when ip is '0.0.0.0'" do
      options = NetworkHelpers.udp_listen_options("0.0.0.0")

      assert :binary in options
      assert {active, :once} = Enum.find(options, fn
        {:active, _} -> true
        _ -> false
      end)
    end

    test "includes IP when valid IP provided" do
      options = NetworkHelpers.udp_listen_options("127.0.0.1")

      assert {:ip, {127, 0, 0, 1}} in options
    end

    test "includes IP when valid IP tuple provided" do
      options = NetworkHelpers.udp_listen_options({192, 168, 1, 1})

      assert {:ip, {192, 168, 1, 1}} in options
    end

    test "handles invalid IP gracefully by using base options" do
      options = NetworkHelpers.udp_listen_options("invalid-ip")

      assert :binary in options
      assert {active, :once} = Enum.find(options, fn
        {:active, _} -> true
        _ -> false
      end)
      # Should not include :ip option
      refute Enum.any?(options, fn
        {:ip, _} -> true
        _ -> false
      end)
    end
  end
end
