defmodule DataDiode.S1.UDPListenerTest do
  use ExUnit.Case, async: false
  import Mox

  setup :set_mox_from_context

  setup do
    # Configure ports
    Application.put_env(:data_diode, :s1_udp_port, 0)
    Application.put_env(:data_diode, :decapsulator, DataDiode.S2.DecapsulatorMock)

    # Start app dependencies if not started
    Application.ensure_all_started(:data_diode)

    on_exit(fn ->
      Application.delete_env(:data_diode, :s1_udp_port)
      Application.delete_env(:data_diode, :decapsulator)
    end)

    :ok
  end

  test "S1 UDP Listener forwards packets to S2 via Encapsulator" do
    set_mox_global()

    # 1. Start isolated S2 Listener on ephemeral port
    Application.put_env(:data_diode, :s2_port, 0)
    Application.put_env(:data_diode, :decapsulator, DataDiode.S2.DecapsulatorMock)
    {:ok, s2_pid} = DataDiode.S2.Listener.start_link(name: :s2_test_instance)

    # Get the S2 port
    socket_s2 = :sys.get_state(s2_pid)
    {:ok, {_, s2_port}} = :inet.sockname(socket_s2)

    # 2. Start a local Encapsulator pointed at our isolated S2
    # We pass s2_port in the environment since the GenServer reads it from there in init
    Application.put_env(:data_diode, :s2_port, s2_port)
    {:ok, enc_pid} = DataDiode.S1.Encapsulator.start_link(name: :isolated_encapsulator)

    # 3. Start S1 UDP Listener pointing to our local Encapsulator
    {:ok, s1_udp_pid} =
      DataDiode.S1.UDPListener.start_link(
        name: :s1_udp_test_instance,
        encapsulator: enc_pid
      )

    # Get the S1 port
    # Note: socket is now inside a map in state
    %{socket: socket_s1} = :sys.get_state(s1_udp_pid)
    {:ok, {_, s1_port}} = :inet.sockname(socket_s1)

    test_payload = "UDP_TEST_DATA"

    # Prepare expectation
    parent = self()

    expect(DataDiode.S2.DecapsulatorMock, :process_packet, fn _data ->
      send(parent, :packet_reached_s2)
      :ok
    end)

    # 4. Open a sender socket and send to S1
    {:ok, sender} = :gen_udp.open(0, [:binary])
    :ok = :gen_udp.send(sender, ~c"127.0.0.1", s1_port, test_payload)

    # 5. Verify it reached S2
    assert_receive :packet_reached_s2, 2000

    :gen_udp.close(sender)
    GenServer.stop(s1_udp_pid)
    GenServer.stop(enc_pid)
    GenServer.stop(s2_pid)
  end

  test "S1 UDP Listener handles configuration edge cases" do
    # 1. Port is nil (disabled)
    Application.put_env(:data_diode, :s1_udp_port, nil)
    assert DataDiode.S1.UDPListener.start_link(name: :s1_udp_nil_test) == :ignore

    # 2. Invalid port (string)
    Application.put_env(:data_diode, :s1_udp_port, "ABC")
    Process.flag(:trap_exit, true)

    assert {:error, :invalid_config} =
             DataDiode.S1.UDPListener.start_link(name: :s1_udp_invalid_test)

    Process.flag(:trap_exit, false)

    # 3. IP Binding variants
    Application.put_env(:data_diode, :s1_udp_port, 0)

    # Valid IP
    Application.put_env(:data_diode, :s1_ip, "127.0.0.1")
    {:ok, p1} = DataDiode.S1.UDPListener.start_link(name: :s1_udp_ip_test)
    GenServer.stop(p1)

    # :any
    Application.put_env(:data_diode, :s1_ip, :any)
    {:ok, p_any} = DataDiode.S1.UDPListener.start_link(name: :s1_udp_any_test)
    GenServer.stop(p_any)

    # Invalid IP (should fall back to :any)
    Application.put_env(:data_diode, :s1_ip, "999.999.999.999")
    {:ok, p2} = DataDiode.S1.UDPListener.start_link(name: :s1_udp_bad_ip_test)
    GenServer.stop(p2)

    # Restore
    Application.delete_env(:data_diode, :s1_ip)
  end

  test "S1 UDP Listener handles socket errors and unexpected messages" do
    import ExUnit.CaptureLog

    {:ok, pid} = DataDiode.S1.UDPListener.start_link(name: :s1_udp_error_test)

    # 1. Unexpected message
    assert capture_log(fn ->
             send(pid, :unknown_msg)
             Process.sleep(50)
           end) =~ "Received unexpected message: :unknown_msg"

    # 2. UDP Error
    assert capture_log(fn ->
             send(pid, {:udp_error, :socket, :einval})
             Process.sleep(50)
           end) =~ "Socket error: :einval"

    # 3. UDP Closed
    Process.flag(:trap_exit, true)

    assert capture_log(fn ->
             send(pid, {:udp_closed, :socket})
             Process.sleep(50)
           end) =~ "Listener socket closed unexpectedly"

    assert_receive {:EXIT, ^pid, :udp_closed}
    Process.flag(:trap_exit, false)
  end

  test "S1 UDP Listener init failure on port in use" do
    {:ok, socket} = :gen_udp.open(0)
    {:ok, {_, port}} = :inet.sockname(socket)

    Application.put_env(:data_diode, :s1_udp_port, port)
    Process.flag(:trap_exit, true)
    assert {:error, :eaddrinuse} = DataDiode.S1.UDPListener.start_link(name: :s1_udp_in_use_test)
    Process.flag(:trap_exit, false)

    :gen_udp.close(socket)
  end

  test "S1 UDP Listener handles non-tuple IP addresses" do
    {:ok, pid} = DataDiode.S1.UDPListener.start_link(name: :s1_udp_str_ip_test)

    # Manually send a message where IP is a string (rare but possible via manual process msg)
    # This exercises the fallback in ip_to_string/1
    send(pid, {:udp, self(), "127.0.0.1", 1234, "payload"})

    # Should not crash. We can verify it didn't crash by checking if it's still alive.
    Process.sleep(50)
    assert Process.alive?(pid)

    GenServer.stop(pid)
  end
end
