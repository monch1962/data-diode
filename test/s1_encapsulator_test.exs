defmodule DataDiode.S1.EncapsulatorTest do
  # Not async because we modify global config
  use ExUnit.Case, async: false
  alias DataDiode.S1.Encapsulator

  setup do
    # Open a local UDP socket to receive the packet
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true])
    {:ok, port} = :inet.port(socket)

    # Configure Encapsulator to send to our test socket
    Application.put_env(:data_diode, :s2_port, port)

    # Ensure Encapsulator is started (it might be already started by app, but we want a fresh one config-wise?)
    # The Encapsulator is a named process. If it's already running with old config, we might have issues.
    # But since encapsulator looks up the port *inside* encapsulate_and_send?
    # Let's check the code:
    # No, it resolves resolve_s2_port() inside init/1.
    # So we must RESTART the Encapsulator to pick up the new port.

    # Stop the global Encapsulator to insure we can start a fresh one or it restarts with new config
    if pid = Process.whereis(Encapsulator) do
      Process.exit(pid, :kill)
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        1000 -> raise "Encapsulator process did not die"
      end
    end

    # Wait for it to come back up (supervised)
    wait_for_encapsulator()

    {:ok, receiver_socket: socket, receiver_port: port}
  end

  defp wait_for_encapsulator(retries \\ 10) do
    case Process.whereis(Encapsulator) do
      nil ->
        if retries > 0 do
          Process.sleep(10)
          wait_for_encapsulator(retries - 1)
        else
          flunk("Encapsulator failed to restart")
        end

      _pid ->
        :ok
    end
  end

  # Ensure application is started for all tests
  setup do
    Application.ensure_all_started(:data_diode)
    :ok
  end

  test "encapsulate_and_send/3 sends correct packet", %{receiver_socket: _socket} do
    # Send a packet
    src_ip = "192.168.1.5"
    src_port = 8888
    payload = "Top Secret"

    :ok = Encapsulator.encapsulate_and_send(src_ip, src_port, payload)

    # Receive it on our test socket
    assert_receive {:udp, _socket, _ip, _port, packet}, 1000

    # Verify Content
    expected_ip = <<192, 168, 1, 5>>
    expected_port = <<8888::integer-big-16>>
    expected_header_payload = expected_ip <> expected_port <> payload
    expected_crc = :erlang.crc32(expected_header_payload)

    assert packet == expected_header_payload <> <<expected_crc::integer-unsigned-big-32>>
  end

  test "handles invalid IP gracefully" do
    # Should just log warning and not crash
    assert :ok = Encapsulator.encapsulate_and_send("invalid", 80, "Fail")

    # Should receive nothing
    refute_receive {:udp, _, _, _, _}, 100
  end

  test "ip_to_binary handles charlists", %{receiver_socket: _socket} do
    # Even though public API uses strings, we can test charlist if we want to hit that clause
    # but the internal call already converts. To hit it directly we'd need to call it.
    # We'll just verify a valid string IP works (hits both clauses)
    assert :ok = Encapsulator.encapsulate_and_send(~c"127.0.0.1", 80, "Charlist")
    assert_receive {:udp, _, _, _, _}, 500
  end

  test "terminate closes gracefully" do
    assert :ok == Encapsulator.terminate(:normal, %{socket: :dummy})
  end
end
