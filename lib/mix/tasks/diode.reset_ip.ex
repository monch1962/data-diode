defmodule Mix.Tasks.Diode.ResetIp do
  @moduledoc """
  Reset rate limiting for a specific IP address.

  ## Examples

      mix diode.reset_ip 192.168.1.100
      mix diode.reset_ip 10.0.0.50

  """

  use Mix.Task

  @shortdoc "Reset rate limiting for an IP address"

  @impl true
  def run([ip_address]) do
    Application.ensure_all_started(:data_diode)

    DataDiode.RateLimiter.reset_ip(ip_address)

    IO.puts("✓ Rate limit reset for IP: #{ip_address}")
  end

  def run([]) do
    Mix.raise("Missing IP address. Usage: mix diode.reset_ip <ip_address>")
  end
end
