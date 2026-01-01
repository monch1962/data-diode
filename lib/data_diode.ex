defmodule DataDiode do
  @moduledoc """
  Data Diode - A unidirectional gateway for secure one-way data transfer.

  This application simulates a physical data diode, ensuring data can flow
  from an unsecured network (Service 1) to a secure network (Service 2)
  with absolute guarantee of no reverse connectivity.

  ## Architecture

  The system is split into two logical services:

  * **Service 1 (S1)**: Accepts connections from untrusted clients,
    encapsulates packets with source metadata, and forwards via UDP.

  * **Service 2 (S2)**: Receives encapsulated packets, validates integrity,
    and writes data to secure storage. Never initiates outbound connections.

  ## Security Features

  * Protocol whitelisting with Deep Packet Inspection (DPI)
  * Rate limiting using continuous token bucket algorithm
  * CRC32 integrity checks on all packets
  * Startup configuration validation
  * Autonomous disk cleanup
  * Systemd security hardening
  * Docker health monitoring

  ## Use Cases

  * Critical Infrastructure (SCADA/ICS)
  * Military and Government networks
  * Nuclear Facilities
  * Industrial Control Systems

  For more information, see the README.md file.
  """

  @doc """
  Example function (can be removed in production).
  """
  def hello do
    :world
  end
end
