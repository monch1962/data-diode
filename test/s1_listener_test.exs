defmodule DataDiode.S1.ListenerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias DataDiode.S1.Listener

  setup do
    # Force ephemeral ports to avoid :eaddrinuse
    Application.put_env(:data_diode, :s1_port, 0)
    Application.delete_env(:data_diode, :s1_ip)

    on_exit(fn ->
      Application.delete_env(:data_diode, :s1_port)
      Application.delete_env(:data_diode, :s1_ip)
    end)

    :ok
  end

  test "listen_options returns expected settings" do
    opts = Listener.listen_options()
    assert :inet in opts
    assert {:reuseaddr, true} in opts
  end

  test "init returns local socket on success" do
    # Using ephemeral port 0
    Application.put_env(:data_diode, :s1_port, 0)
    assert {:ok, socket} = Listener.init(:ok)
    assert is_port(socket)
    :gen_tcp.close(socket)
  end

  test "handle_info :accept_loop handles error gracefully" do
    # Create a real listen socket and then close it to force an accept error.
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    :ok = :gen_tcp.close(listen_socket)
    # Mock a closed socket error
    # We close the socket so accept returns {:error, :closed}
    :gen_tcp.close(listen_socket)

    assert {:stop, :closed, ^listen_socket} = Listener.handle_info(:accept_loop, listen_socket)
  end

  test "accepts connection and delegates to HandlerSupervisor" do
    # Start a real listener on port 0
    {:ok, pid} = Listener.start_link(name: :s1_test_listener_integration_unique)

    # Get the actual port
    socket = :sys.get_state(pid)
    {:ok, port} = :inet.port(socket)

    # Connect a client
    {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

    # Verify at least one child was started in HandlerSupervisor
    # We use a simple retry loop because start_handler is async
    wait_until(fn ->
      %{active: count} = DynamicSupervisor.count_children(DataDiode.S1.HandlerSupervisor)
      count >= 1
    end)

    # Clean up
    :gen_tcp.close(client)
    GenServer.stop(pid)
  end

  defp wait_until(fun, attempts \\ 10) do
    if attempts == 0 do
      flunk("Condition not met after 10 attempts")
    else
      if fun.() do
        :ok
      else
        Process.sleep(10)
        wait_until(fun, attempts - 1)
      end
    end
  end

  test "recovers from socket closure (flapping interface)" do
    # Start a real listener UNLINKED so the test doesn't crash when it stops
    Application.put_env(:data_diode, :s1_port, 0)
    {:ok, pid} = GenServer.start(Listener, :ok, name: :s1_flapping_test_unique)

    # Monitor it
    ref = Process.monitor(pid)

    # Get the current listen socket
    socket = :sys.get_state(pid)

    # Simulate a sudden socket closure
    :gen_tcp.close(socket)

    # It should terminate because of the fatal error in accept loop
    assert_receive {:DOWN, ^ref, :process, ^pid, :closed}, 1000
  end

  test "listen_options handles valid IP" do
    Application.put_env(:data_diode, :s1_ip, "127.0.0.1")
    opts = Listener.listen_options()
    assert Keyword.get(opts, :ip) == {127, 0, 0, 1}
  end

  test "listen_options handles invalid IP" do
    Application.put_env(:data_diode, :s1_ip, "invalid")
    opts = Listener.listen_options()
    refute Keyword.has_key?(opts, :ip)
  end

  test "handle_info :accept_loop timeout case" do
    {:ok, socket} = :gen_tcp.listen(0, [])
    # This just verifies it returns noreply and sends itself the next loop
    assert {:noreply, ^socket} = Listener.handle_info(:accept_loop, socket)
    :gen_tcp.close(socket)
  end

  test "resolves to default port when s1_port is not set" do
    Application.delete_env(:data_diode, :s1_port)
    assert {:ok, 8080} = Listener.resolve_listen_port()
  end

  test "resolves to specified port from Application config" do
    Application.put_env(:data_diode, :s1_port, 42_000)
    assert {:ok, 42_000} = Listener.resolve_listen_port()
  end

  test "returns error for invalid port configuration" do
    Application.put_env(:data_diode, :s1_port, -1)

    on_exit(fn ->
      # Restore valid port to avoid breaking subsequent tests
      Application.put_env(:data_diode, :s1_port, 0)
    end)

    assert {:error, {:invalid_port, -1}} = Listener.resolve_listen_port()
  end

  test "returns error for port too large" do
    Application.put_env(:data_diode, :s1_port, 70_000)

    on_exit(fn ->
      # Restore valid port to avoid breaking subsequent tests
      Application.put_env(:data_diode, :s1_port, 0)
    end)

    assert {:error, {:invalid_port, 70_000}} = Listener.resolve_listen_port()
  end

  test "returns error for non-integer port" do
    Application.put_env(:data_diode, :s1_port, "not_a_number")

    on_exit(fn ->
      # Restore valid port to avoid breaking subsequent tests
      Application.put_env(:data_diode, :s1_port, 0)
    end)

    assert {:error, {:invalid_port, "not_a_number"}} = Listener.resolve_listen_port()
  end

  test "listen_options handles :any IP" do
    Application.put_env(:data_diode, :s1_ip, :any)
    opts = Listener.listen_options()
    # Should have base options but no specific :ip option
    assert :binary in opts
    assert :inet in opts
    refute Keyword.has_key?(opts, :ip)
  end

  test "listen_options handles nil IP" do
    opts = Listener.listen_options(nil)
    # Should have base options but no specific :ip option
    assert :binary in opts
    assert :inet in opts
    refute Keyword.has_key?(opts, :ip)
  end

  test "listen_options includes IP when explicitly provided" do
    opts = Listener.listen_options("192.168.1.1")
    assert {:ip, {192, 168, 1, 1}} in opts
  end

  test "handle_info with unexpected message logs and continues" do
    {:ok, socket} = :gen_tcp.listen(0, [])

    assert capture_log(fn ->
             {:noreply, ^socket} = Listener.handle_info(:unexpected_message, socket)
           end) =~ "unexpected message"

    :gen_tcp.close(socket)
  end

  test "handle_call returns port number" do
    {:ok, pid} = Listener.start_link(name: :s1_port_test_unique)
    socket = :sys.get_state(pid)
    {:ok, port} = :inet.port(socket)

    assert {:reply, ^port, ^socket} = Listener.handle_call(:port, self(), socket)

    GenServer.stop(pid)
  end
end
