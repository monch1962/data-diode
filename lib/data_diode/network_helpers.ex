defmodule DataDiode.NetworkHelpers do
  @moduledoc """
  Shared network utility functions for parsing and resolving network configuration.
  This module centralizes IP address parsing and port resolution logic.
  """

  @type ip_address :: :any | :inet.ip_address()
  @type parse_result :: {:ok, :inet.ip_address()} | :error

  @doc """
  Parses an IP address string into an Erlang IP tuple.
  Returns :any for nil, "0.0.0.0", or empty string (bind to all interfaces).
  Returns IP tuples as-is (already parsed).
  Returns ip_tuple for valid string addresses, or :any on parse failure.
  """
  @spec parse_ip_address(binary() | nil | :any | :inet.ip_address()) :: ip_address()
  def parse_ip_address(nil), do: :any
  def parse_ip_address(:any), do: :any
  def parse_ip_address(""), do: :any
  def parse_ip_address("0.0.0.0"), do: :any

  def parse_ip_address({a, b, c, d} = ip)
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d), do: ip

  def parse_ip_address(ip_str) when is_binary(ip_str) do
    case :inet.parse_address(String.to_charlist(ip_str)) do
      {:ok, addr} -> addr
      _error -> :any
    end
  end

  def parse_ip_address(_), do: :any

  @doc """
  Parses an IP address string with detailed error reporting.
  Returns {:ok, ip_tuple} or :error.
  """
  @spec parse_ip_address_strict(binary() | nil) :: parse_result()
  def parse_ip_address_strict(nil), do: :error
  def parse_ip_address_strict(""), do: :error

  def parse_ip_address_strict(ip_str) when is_binary(ip_str) do
    case :inet.parse_address(String.to_charlist(ip_str)) do
      {:ok, addr} -> {:ok, addr}
      _error -> :error
    end
  end

  @doc """
  Converts an IP tuple to a string representation.
  """
  @spec ip_to_string(:inet.ip_address() | binary()) :: binary()
  def ip_to_string(ip) when is_tuple(ip), do: List.to_string(:inet.ntoa(ip))
  def ip_to_string(ip) when is_binary(ip), do: ip

  @doc """
  Converts a 4-byte binary to an IP address string "a.b.c.d".
  """
  @spec binary_to_ip(<<_::32>>) :: {:ok, binary()}
  def binary_to_ip(<<a, b, c, d>>), do: {:ok, "#{a}.#{b}.#{c}.#{d}"}

  @doc """
  Validates that a port number is within the valid range (0-65535).
  Returns {:ok, port} or {:error, {:invalid_port, value}}.
  """
  @spec validate_port(integer() | any()) :: {:ok, 0..65_535} | {:error, {:invalid_port, any()}}
  def validate_port(port) when is_integer(port) and port >= 0 and port <= 65_535, do: {:ok, port}
  def validate_port(port), do: {:error, {:invalid_port, port}}

  @doc """
  Constructs TCP socket options with optional IP binding.
  """
  @spec tcp_listen_options(binary() | nil | :any | :inet.ip_address()) :: [
          :gen_tcp.listen_option()
        ]
  def tcp_listen_options(ip \\ nil) do
    base = [:binary, :inet, {:reuseaddr, true}, {:active, false}]

    case parse_ip_address(ip) do
      :any -> base
      addr -> [{:ip, addr} | base]
    end
  end

  @doc """
  Constructs UDP socket options with optional IP binding.
  """
  @spec udp_listen_options(binary() | nil | :any | :inet.ip_address()) :: [:gen_udp.option()]
  def udp_listen_options(ip \\ nil) do
    base = [:binary, active: :once]

    case parse_ip_address(ip) do
      :any -> base
      addr -> [{:ip, addr} | base]
    end
  end
end
