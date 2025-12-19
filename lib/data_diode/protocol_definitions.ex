defmodule DataDiode.ProtocolDefinitions do
  @moduledoc """
  Defines binary signatures for identifying common OT protocols.
  Used by the Encapsulator's DPI logic to filter traffic.
  """

  @doc """
  Checks if the payload matches the given protocol atom.
  """
  @spec matches?(atom(), binary()) :: boolean()
  def matches?(:any, _payload), do: true

  # Modbus TCP
  # Header: TransactionID(2), ProtocolID(2) = 0x0000, Length(2), UnitID(1)
  # Strong check: Protocol ID must be 0 for Modbus TCP.
  def matches?(
        :modbus,
        <<_trans_id::binary-2, 0x00, 0x00, _len::binary-2, _unit_id::binary-1, _rest::binary>>
      ), do: true

  def matches?(:modbus, _), do: false

  # DNP3
  # Start bytes: 0x05, 0x64
  def matches?(:dnp3, <<0x05, 0x64, _rest::binary>>), do: true
  def matches?(:dnp3, _), do: false

  # MQTT
  # Fixed Header First Byte: Packet Type (4 bits) | Flags (4 bits)
  # CONNECT = 1 (0x10), PUBLISH = 3 (0x30), etc.
  # We allow common ones or strict subset. Let's allow CONNECT(1), CONNACK(2), PUBLISH(3), PUBACK(4), PUBREC(5), PUBREL(6), PUBCOMP(7), SUBSCRIBE(8), SUBACK(9), UNSUBSCRIBE(10), UNSUBACK(11), PINGREQ(12), PINGRESP(13), DISCONNECT(14).
  # Basically, 0x1X - 0xEX.
  # Simplest: Any valid Control Packet.
  def matches?(:mqtt, <<packet_type::size(4), _flags::size(4), _rest::binary>>)
      when packet_type >= 1 and packet_type <= 14, do: true

  def matches?(:mqtt, _), do: false

  # SNMP (v1, v2c, v3)
  # Basic ASN.1 BER check: starts with SEQUENCE (0x30), followed by an INTEGER (0x02) for version.
  def matches?(:snmp, <<0x30, _len, 0x02, _rest::binary>>), do: true
  def matches?(:snmp, _), do: false

  # Fallback for unrecognized atoms (should not happen if config is validated)
  def matches?(_, _), do: false
end
