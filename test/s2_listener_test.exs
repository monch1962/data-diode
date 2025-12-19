Mox.defmock(DataDiode.S2.DecapsulatorMock, for: DataDiode.S2.Decapsulator)

defmodule DataDiode.S2.ListenerTest do
  use ExUnit.Case, async: false
  alias DataDiode.S2.Listener

  import Mox

  setup do
    Application.put_env(:data_diode, :decapsulator, DataDiode.S2.DecapsulatorMock)
    Application.put_env(:data_diode, :s2_port, 0)
    Application.delete_env(:data_diode, :s2_ip)

    :ok = set_mox_global()
    
    on_exit(fn ->
      Application.delete_env(:data_diode, :decapsulator)
      Application.delete_env(:data_diode, :s2_port)
      Application.delete_env(:data_diode, :s2_ip)
    end)
    :ok
  end

  # Test case 1: Successful packet reception and delegation
  test "udp_options handles valid IP" do
    Application.put_env(:data_diode, :s2_ip, "127.0.0.1")
    opts = Listener.udp_options()
    assert Keyword.get(opts, :ip) == {127, 0, 0, 1}
  end

  test "udp_options handles invalid IP" do
    Application.put_env(:data_diode, :s2_ip, "invalid")
    opts = Listener.udp_options()
    # It falls back to default options which DON'T include :ip
    refute Keyword.has_key?(opts, :ip)
  end

  test "resolve_listen_port returns configured port" do
    Application.put_env(:data_diode, :s2_port, 9999)
    assert {:ok, 9999} == Listener.resolve_listen_port()
    Application.delete_env(:data_diode, :s2_port)
  end

  test "udp_options returns expected settings" do
    opts = Listener.udp_options()
    assert :binary in opts
    assert {:active, :once} in opts
  end

  test "init returns local socket on success" do
    # Using ephemeral port 0
    Application.put_env(:data_diode, :s2_port, 0)
    assert {:ok, socket} = Listener.init(:ok)
    assert is_port(socket)
    :gen_udp.close(socket)
  end

  test "saturation test: handles many rapid UDP packets" do
    # Use real Decapsulator to avoid Mox multi-process expectation hell in stress test
    Application.put_env(:data_diode, :decapsulator, DataDiode.S2.Decapsulator)
    
    # Start a real listener
    Application.put_env(:data_diode, :s2_port, 0)
    {:ok, pid} = Listener.start_link(name: :s2_saturation_test_unique)
    
    # Get port
    socket = :sys.get_state(pid)
    {:ok, port} = :inet.port(socket)
    
    # Send 100 packets rapidly
    {:ok, sender} = :gen_udp.open(0, [])
    packet = <<127, 0, 0, 1, 0, 80, "payload">>
    
    Enum.each(1..100, fn _ ->
      :gen_udp.send(sender, ~c"127.0.0.1", port, packet)
    end)
    
    # Verify app doesn't crash
    Process.sleep(100)
    assert Process.alive?(pid)
    
    :gen_udp.close(sender)
    GenServer.stop(pid)
    Application.delete_env(:data_diode, :decapsulator)
  end

  test "handle_info :udp_closed stops the process" do
    assert {:stop, :udp_closed, :dummy_socket} == Listener.handle_info({:udp_closed, :dummy_socket}, :dummy_state)
  end

  test "integration: UDP listener accepts packet and processes it" do
    # Use real decapsulator for integration
    Application.put_env(:data_diode, :decapsulator, DataDiode.S2.Decapsulator)
    
    # Start a real listener on port 0
    {:ok, pid} = Listener.start_link(name: :s2_test_listener)
    
    # Get the port
    socket = :sys.get_state(pid)
    {:ok, port} = :inet.port(socket)
    
    # Send a packet
    {:ok, sender} = :gen_udp.open(0)
    packet = <<1, 2, 3, 4, 0, 80, "Hello">>
    :ok = :gen_udp.send(sender, {127, 0, 0, 1}, port, packet)
    
    # Wait for the task to be spawned (no easy way to verify without poll or mock)
    # But we can at least ensure it doesn't crash
    Process.sleep(10)
    
    # Clean up
    :gen_udp.close(sender)
    GenServer.stop(pid)
  end

  test "UDP listener receives packet and delegates to Decapsulator" do
    expect(DataDiode.S2.DecapsulatorMock, :process_packet, fn packet ->
      assert is_binary(packet)
      :ok
    end)

    # Start a fresh listener on port 0
    {:ok, pid} = Listener.start_link(name: :s2_fresh_mock_test)
    
    # Get port
    socket = :sys.get_state(pid)
    {:ok, port} = :inet.port(socket)

    ip_header = <<127, 0, 0, 1>>
    port_header = <<1234::size(16)>>
    payload = "test payload"
    packet = ip_header <> port_header <> payload

    {:ok, sender_socket} = :gen_udp.open(0)
    :ok = :gen_udp.send(sender_socket, {127, 0, 0, 1}, port, packet)
    :gen_udp.close(sender_socket)

    # Use verify_count instead of sleep if possible, or a very small sleep since it's async
    Process.sleep(20)
    verify!()
    GenServer.stop(pid)
  end
end
