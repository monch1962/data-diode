defmodule DataDiode.ProtocolDefinitionsTest do
  use ExUnit.Case, async: true
  alias DataDiode.ProtocolDefinitions

  test "matches? :any" do
    assert ProtocolDefinitions.matches?(:any, "anything")
    assert ProtocolDefinitions.matches?(:any, <<1, 2, 3>>)
  end

  test "matches? :modbus" do
    # Valid Modbus TCP (ProtoID 0x0000)
    valid = <<0x01, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01, 0x03, 0x00, 0x00, 0x00, 0x01>>
    assert ProtocolDefinitions.matches?(:modbus, valid)

    # Invalid: ProtoID 0x0001
    invalid_proto = <<0x01, 0x01, 0x00, 0x01, 0x00, 0x06, 0x01, 0x03, 0x00, 0x00, 0x00, 0x01>>
    refute ProtocolDefinitions.matches?(:modbus, invalid_proto)

    # Invalid: Too short
    assert ProtocolDefinitions.matches?(:modbus, <<1, 2, 3>>) == false
  end

  test "matches? :dnp3" do
    # Valid DNP3 start bytes 0x05, 0x64
    assert ProtocolDefinitions.matches?(:dnp3, <<0x05, 0x64, 1, 2, 3>>)

    # Invalid
    refute ProtocolDefinitions.matches?(:dnp3, <<0x05, 0x65, 1, 2, 3>>)
    refute ProtocolDefinitions.matches?(:dnp3, <<0x01>>)
  end

  test "matches? :mqtt" do
    # Valid MQTT (bits 4-7 are packet type 1-14)
    # CONNECT
    assert ProtocolDefinitions.matches?(:mqtt, <<0x10, 0>>)
    # PUBLISH
    assert ProtocolDefinitions.matches?(:mqtt, <<0x30, 0>>)
    # DISCONNECT
    assert ProtocolDefinitions.matches?(:mqtt, <<0xE0, 0>>)

    # Invalid: type 0 (reserved)
    refute ProtocolDefinitions.matches?(:mqtt, <<0x00, 0>>)
    # Invalid: type 15 (reserved)
    refute ProtocolDefinitions.matches?(:mqtt, <<0xF0, 0>>)
    # Invalid: empty
    refute ProtocolDefinitions.matches?(:mqtt, <<>>)
  end

  test "matches? :snmp" do
    # Valid SNMP (SEQUENCE + INTEGER)
    assert ProtocolDefinitions.matches?(:snmp, <<0x30, 0x2C, 0x02, 0x01, 0x01>>)

    # Invalid
    refute ProtocolDefinitions.matches?(:snmp, <<0x31, 1, 2>>)
    refute ProtocolDefinitions.matches?(:snmp, <<0x30, 0x2C, 0x03, 1, 2>>)
  end

  test "matches? unknown atom" do
    refute ProtocolDefinitions.matches?(:unknown, "payload")
  end
end
