defmodule DataDiode.ConfigValidator do
  @moduledoc """
  Validates application configuration at startup to ensure all required settings are present and valid.
  Raises an exception if validation fails, preventing the application from starting with invalid configuration.
  """

  require Logger

  @doc """
  Validates all application configuration.
  Raises RuntimeError if any configuration is invalid.
  """
  @spec validate!() :: :ok | no_return()
  def validate! do
    Logger.info("ConfigValidator: Starting configuration validation...")

    validate_ports!()
    validate_ips!()
    validate_data_dir!()
    validate_protocols!()
    validate_rate_limits!()

    Logger.info("ConfigValidator: All configuration validated successfully.")
    :ok
  end

  # Private validation functions

  defp validate_ports! do
    s1_port = DataDiode.ConfigHelpers.s1_port()
    s2_port = DataDiode.ConfigHelpers.s2_port()
    s1_udp_port = DataDiode.ConfigHelpers.s1_udp_port()

    validate_port!(s1_port, :s1_port)
    validate_port!(s2_port, :s2_port)

    if s1_udp_port do
      validate_port!(s1_udp_port, :s1_udp_port)
    end
  end

  defp validate_port!(port, _config_key) when is_integer(port) and port >= 0 and port <= 65_535 do
    :ok
  end

  defp validate_port!(port, config_key) do
    raise ArgumentError,
          "Invalid port #{inspect(port)} for #{inspect(config_key)}. Must be between 0 and 65535."
  end

  defp validate_ips! do
    s1_ip = DataDiode.ConfigHelpers.s1_ip()
    s2_ip = DataDiode.ConfigHelpers.s2_ip()

    if s1_ip != nil do
      validate_ip!(s1_ip, :s1_ip)
    end

    validate_ip!(s2_ip, :s2_ip)
  end

  defp validate_ip!(ip_str, config_key) when is_binary(ip_str) do
    case :inet.parse_address(String.to_charlist(ip_str)) do
      {:ok, _addr} ->
        :ok

      {:error, :einval} ->
        raise ArgumentError,
              "Invalid IP address #{inspect(ip_str)} for #{config_key}. Must be a valid IPv4 or IPv6 address."
    end
  end

  defp validate_data_dir! do
    data_dir = DataDiode.ConfigHelpers.data_dir()

    unless File.dir?(data_dir) do
      Logger.warning(
        "ConfigValidator: Data directory #{inspect(data_dir)} does not exist. Attempting to create it."
      )

      case File.mkdir_p(data_dir) do
        :ok ->
          Logger.info("ConfigValidator: Created data directory: #{data_dir}")

        {:error, reason} ->
          raise ArgumentError,
                "Cannot create data directory #{inspect(data_dir)}: #{inspect(reason)}"
      end
    end

    # Test write permissions
    test_file = Path.join(data_dir, ".write_test_#{System.unique_integer()}")

    case File.write(test_file, "test") do
      :ok ->
        File.rm(test_file)

      {:error, reason} ->
        raise ArgumentError,
              "Data directory #{inspect(data_dir)} is not writable: #{inspect(reason)}"
    end
  end

  defp validate_protocols! do
    protocols = DataDiode.ConfigHelpers.allowed_protocols()

    unless is_list(protocols) do
      raise ArgumentError,
            "Invalid allowed_protocols configuration: must be a list, got #{inspect(protocols)}"
    end

    # Validate all protocol values are atoms
    invalid_protocols =
      Enum.reject(protocols, fn
        proto when is_atom(proto) -> true
        _ -> false
      end)

    case invalid_protocols do
      [] ->
        :ok

      _ ->
        raise ArgumentError,
              "Invalid protocol values in allow_list: #{inspect(invalid_protocols)}. All protocols must be atoms."
    end
  end

  defp validate_rate_limits! do
    rate_limit = DataDiode.ConfigHelpers.max_packets_per_second()

    unless is_integer(rate_limit) and rate_limit > 0 do
      raise ArgumentError,
            "Invalid max_packets_per_sec: must be a positive integer, got #{inspect(rate_limit)}"
    end

    disk_interval = DataDiode.ConfigHelpers.disk_cleaner_interval()

    unless is_integer(disk_interval) and disk_interval > 0 do
      raise ArgumentError,
            "Invalid disk_cleaner_interval: must be a positive integer, got #{inspect(disk_interval)}"
    end

    disk_batch_size = DataDiode.ConfigHelpers.disk_cleanup_batch_size()

    unless is_integer(disk_batch_size) and disk_batch_size > 0 do
      raise ArgumentError,
            "Invalid disk_cleanup_batch_size: must be a positive integer, got #{inspect(disk_batch_size)}"
    end
  end
end
