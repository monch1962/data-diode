defmodule DataDiode.ConfigHelpers do
  @moduledoc """
  Centralized configuration access helpers for the Data Diode application.
  This module provides a single source of truth for accessing application configuration.
  """

  @doc """
  Returns the configured data directory path.
  Defaults to "." if not configured or set to nil.
  """
  @spec data_dir() :: Path.t()
  def data_dir do
    case Application.fetch_env(:data_diode, :data_dir) do
      {:ok, nil} -> "."
      {:ok, dir} when is_binary(dir) -> dir
      :error -> "."
    end
  end

  @doc """
  Returns the S1 (Service 1) TCP listen port.
  """
  @spec s1_port() :: 0..65535
  def s1_port do
    Application.get_env(:data_diode, :s1_port, 8080)
  end

  @doc """
  Returns the S1 (Service 1) UDP listen port.
  Returns nil if UDP ingress is disabled.
  """
  @spec s1_udp_port() :: 0..65535 | nil
  def s1_udp_port do
    Application.get_env(:data_diode, :s1_udp_port, nil)
  end

  @doc """
  Returns the S1 (Service 1) bind IP address.
  """
  @spec s1_ip() :: binary() | nil
  def s1_ip do
    Application.get_env(:data_diode, :s1_ip, nil)
  end

  @doc """
  Returns the S2 (Service 2) UDP listen port.
  """
  @spec s2_port() :: 0..65535
  def s2_port do
    Application.get_env(:data_diode, :s2_port, 42001)
  end

  @doc """
  Returns the S2 (Service 2) bind IP address.
  """
  @spec s2_ip() :: binary()
  def s2_ip do
    Application.get_env(:data_diode, :s2_ip, "0.0.0.0")
  end

  @doc """
  Returns the maximum packets per second rate limit.
  """
  @spec max_packets_per_second() :: pos_integer()
  def max_packets_per_second do
    Application.get_env(:data_diode, :max_packets_per_sec, 1000)
  end

  @doc """
  Returns the allowed protocols whitelist.
  """
  @spec allowed_protocols() :: [atom()]
  def allowed_protocols do
    Application.get_env(:data_diode, :allowed_protocols, [:any])
  end

  @doc """
  Returns the disk cleaner interval in milliseconds.
  """
  @spec disk_cleaner_interval() :: pos_integer()
  def disk_cleaner_interval do
    Application.get_env(:data_diode, :disk_cleaner_interval, 3_600_000)
  end

  @doc """
  Returns the disk cleanup batch size (number of files to delete at once).
  """
  @spec disk_cleanup_batch_size() :: pos_integer()
  def disk_cleanup_batch_size do
    Application.get_env(:data_diode, :disk_cleanup_batch_size, 100)
  end
end
