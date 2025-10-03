defmodule DataDiode.S2.DecapsulatorMock do
  # <-- CRITICAL FIX: Forces the compiler to load Mox before processing 'use Mox'
  require Mox
  use Mox, for: DataDiode.S2.Decapsulator
end

defmodule DataDiode.S2.ListenerTest do
  use ExUnit.Case, async: true
  use Supervisor
  alias DataDiode.S2.Listener
  alias DataDiode.S2.DecapsulatorMock, as: Decapsulator

  import Mox

  setup do
    # Ensure the mock is verified after each test
    :ok = set_mox_global()
    :ok
  end

  # Test case 1: Successful packet reception and delegation
  test "UDP listener receives packet and delegates to Decapsulator" do
    # 1. Setup Mock Expectation
    # We expect DecapsulatorMock.process_packet/1 to be called exactly once
    # with any binary data, and it should return :ok.
    expect(DataDiode.S2.DecapsulatorMock, :process_packet, fn packet -> # Use the fully qualified name here
      assert is_binary(packet)
      assert byte_size(packet) > 6 # Ensure header + payload exists
      :ok
    end)

    # 2. Start the Listener (already started by the mix test process)
    listener_pid = Process.whereis(Listener)
    assert is_pid(listener_pid)

    # 3. Send a simulated UDP packet to the listener's default port (42001)
    # Simulating the raw binary data sent by S1.
    # IP (127.0.0.1) = <<127, 0, 0, 1>>
    # Port (1234) = <<0, 1234::16>>
    # Payload = "test payload"
    ip_header = <<127, 0, 0, 1>>
    port_header = <<1234::size(16)>>
    payload = "test payload"
    packet = ip_header <> port_header <> payload

    # Simulating the UDP send via Erlang prim_inet functions:
    {:ok, socket} = :gen_udp.open(0)
    # The default listening port for S2 is 42001
    :ok = :gen_udp.send(socket, {127, 0, 0, 1}, 42001, packet)
    :gen_udp.close(socket)

    # 4. Wait for the asynchronous delegation to happen
    Process.sleep(10)

    # Mox verifies the expectation automatically during the setup cleanup,
    # but asserting the call count is explicit.
    assert_called(DataDiode.S2.DecapsulatorMock.process_packet(packet)) # Use the fully qualified name here
  end
end
