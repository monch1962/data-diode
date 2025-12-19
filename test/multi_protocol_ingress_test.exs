defmodule DataDiode.MultiProtocolIngressTest do
  use ExUnit.Case, async: false
  import Mox

  setup :set_mox_global

  setup do
    # 1. Defense Configuration: Allow BOTH :modbus and :snmp
    Application.put_env(:data_diode, :protocol_allow_list, [:modbus, :snmp])
    Application.put_env(:data_diode, :decapsulator, DataDiode.S2.DecapsulatorMock)

    # 2. Setup ephemeral ports for isolated S2
    Application.put_env(:data_diode, :s2_port, 0)
    {:ok, s2_pid} = DataDiode.S2.Listener.start_link(name: :s2_multi_isolated)

    # Get the S2 port
    socket_s2 = :sys.get_state(s2_pid)
    {:ok, {_, s2_port}} = :inet.sockname(socket_s2)

    # 3. Setup local Encapsulator pointed at S2
    Application.put_env(:data_diode, :s2_port, s2_port)
    {:ok, enc_pid} = DataDiode.S1.Encapsulator.start_link(name: :enc_multi_isolated)

    # Point TCP handlers to our isolated encapsulator
    Application.put_env(:data_diode, :encapsulator, enc_pid)

    # 4. Setup TCP Listener (S1)
    Application.put_env(:data_diode, :s1_port, 0)
    {:ok, s1_tcp_pid} = DataDiode.S1.Listener.start_link(name: :s1_tcp_multi_isolated)
    # This helper works because we used :name
    s1_tcp_port = DataDiode.S1.Listener.port()

    # 5. Setup UDP Listener (S1)
    Application.put_env(:data_diode, :s1_udp_port, 0)

    {:ok, s1_udp_pid} =
      DataDiode.S1.UDPListener.start_link(
        name: :s1_udp_multi_isolated,
        encapsulator: enc_pid
      )

    %{socket: socket_s1_udp} = :sys.get_state(s1_udp_pid)
    {:ok, {_, s1_udp_port}} = :inet.sockname(socket_s1_udp)

    on_exit(fn ->
      Application.delete_env(:data_diode, :protocol_allow_list)
      Application.delete_env(:data_diode, :decapsulator)
      Application.delete_env(:data_diode, :s1_port)
      Application.delete_env(:data_diode, :s1_udp_port)
      Application.delete_env(:data_diode, :s2_port)
      Application.delete_env(:data_diode, :encapsulator)

      [s1_udp_pid, s1_tcp_pid, enc_pid, s2_pid]
      |> Enum.filter(&Process.alive?/1)
      |> Enum.each(&GenServer.stop/1)
    end)

    %{
      s1_tcp_port: s1_tcp_port,
      s1_udp_port: s1_udp_port
    }
  end

  test "Concurrent TCP (Modbus) and UDP (SNMP) Ingress", %{
    s1_tcp_port: tcp_port,
    s1_udp_port: udp_port
  } do
    parent = self()

    # Expected Decapsulations
    # We expect 2 packets at S2. We'll send specific ones to distinguish.
    expect(DataDiode.S2.DecapsulatorMock, :process_packet, 2, fn data ->
      # Extract payload to see what it is
      # Header is 4 bytes IP + 2 bytes Port. Total 6 bytes.
      # BUT wait, the decapsulated data is just the payload if processed correctly?
      # No, process_packet(final_packet) returns :ok, but it's a mock.
      # Usually the decapsulator would extract payload.
      # In the mock we receive the FULL packet (header + payload + CRC).
      # 4(IP) + 2(Port) + 4(CRC)
      payload_len = byte_size(data) - 10
      <<_header::6-binary, payload::binary-size(payload_len), _crc::4-binary>> = data

      cond do
        payload ==
            <<0x01, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01, 0x03, 0x00, 0x00, 0x00, 0x01>> ->
          send(parent, :modbus_reached_s2)

        payload == <<0x30, 0x2C, 0x02, 0x01, 0x01>> ->
          send(parent, :snmp_reached_s2)

        true ->
          send(parent, {:unknown_packet_reached_s2, payload})
      end

      :ok
    end)

    # 1. Send Modbus TCP
    modbus_payload = <<0x01, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01, 0x03, 0x00, 0x00, 0x00, 0x01>>
    {:ok, tcp_sock} = :gen_tcp.connect(~c"127.0.0.1", tcp_port, [:binary, active: false])
    :ok = :gen_tcp.send(tcp_sock, modbus_payload)
    :gen_tcp.close(tcp_sock)

    # 2. Send SNMP UDP
    # SNMP (SEQUENCE + INTEGER)
    snmp_payload = <<0x30, 0x2C, 0x02, 0x01, 0x01>>
    {:ok, udp_sock} = :gen_udp.open(0, [:binary])
    :ok = :gen_udp.send(udp_sock, ~c"127.0.0.1", udp_port, snmp_payload)
    :gen_udp.close(udp_sock)

    # 3. Verify both reached S2
    assert_receive :modbus_reached_s2, 2000
    assert_receive :snmp_reached_s2, 2000
  end

  test "Mixed Allowed/Blocked Protocols through Dual Ingress", %{
    s1_tcp_port: tcp_port,
    s1_udp_port: udp_port
  } do
    # Only 1 packet should reach S2 (the allowed one)
    parent = self()

    expect(DataDiode.S2.DecapsulatorMock, :process_packet, 1, fn _data ->
      send(parent, :packet_reached_s2)
      :ok
    end)

    # 1. Blocked: HTTP over TCP
    {:ok, tcp_sock} = :gen_tcp.connect(~c"127.0.0.1", tcp_port, [:binary, active: false])
    :ok = :gen_tcp.send(tcp_sock, "GET / HTTP/1.1\r\n\r\n")
    :gen_tcp.close(tcp_sock)

    # 2. Allowed: SNMP over UDP
    snmp_payload = <<0x30, 0x2C, 0x02, 0x01, 0x01>>
    {:ok, udp_sock} = :gen_udp.open(0, [:binary])
    :ok = :gen_udp.send(udp_sock, ~c"127.0.0.1", udp_port, snmp_payload)
    :gen_udp.close(udp_sock)

    # 3. Verify ONLY one reached S2
    assert_receive :packet_reached_s2, 1000
    refute_receive :packet_reached_s2, 500
  end
end
