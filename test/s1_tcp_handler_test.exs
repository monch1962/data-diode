defmodule DataDiode.S1.EncapsulatorMock do
  # Placeholder for Mox
end

Mox.defmock(DataDiode.S1.EncapsulatorMock, for: DataDiode.S1.Encapsulator)

defmodule DataDiode.S1.TCPHandlerTest do
  use ExUnit.Case, async: true
  alias DataDiode.S1.TCPHandler
  import Mox

  setup do
    Application.put_env(:data_diode, :encapsulator, DataDiode.S1.EncapsulatorMock)
    :ok = set_mox_global()
    
    on_exit(fn ->
      Application.delete_env(:data_diode, :encapsulator)
    end)
    :ok
  end

  test "terminate closes socket" do
    {:ok, listen} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listen)
    {:ok, _client} = :gen_tcp.connect(~c"127.0.0.1", port, [])
    {:ok, server_socket} = :gen_tcp.accept(listen)
    
    state = %{socket: server_socket, src_ip: "1.2.3.4"}
    assert :ok == TCPHandler.terminate(:normal, state)
    
    :gen_tcp.close(listen)
  end

  test "handle_info :tcp processes data and calls encapsulator" do
    # (Existing test is fine)
    # Start a real listener to get a valid socket
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)
    
    # Connect a client to generate a server-side socket
    {:ok, client_socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, server_socket} = :gen_tcp.accept(listen_socket)
    
    # Initialize the handler with the real server socket
    # We can use the GenServer state structure directly for handle_info
    # We need to manually setopts active: :once because our code does that.
    # Actually, the code does it in init and handle_info.
    
    # Test Init
    assert {:ok, state} = TCPHandler.init(server_socket)
    
    payload = "Hello World"
    
    # Expectation: Encapsulator should be called
    expect(DataDiode.S1.EncapsulatorMock, :encapsulate_and_send, fn _ip, _port, data ->
      assert data == payload
      :ok
    end)

    msg = {:tcp, server_socket, payload}
    assert {:noreply, ^state} = TCPHandler.handle_info(msg, state)
    
    # Clean up
    :gen_tcp.close(client_socket)
    
    # We can try to verify synchronously since it's a cast but Mox might need a tiny yield
    # or better yet, use a helper that retries verify if needed, or just sleep very little
    Process.sleep(10)
    verify!()
    :gen_tcp.close(server_socket)
    :gen_tcp.close(listen_socket)
  end

  test "handle_info :tcp drops oversized packets" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen)
    {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, server_socket} = :gen_tcp.accept(listen)
    
    state = %{socket: server_socket, src_ip: "1.2.3.4", src_port: 80}
    
    # Create a packet larger than 1MB
    big_data = :crypto.strong_rand_bytes(1_048_576 + 1)
    
    assert {:noreply, ^state} = TCPHandler.handle_info({:tcp, server_socket, big_data}, state)
    
    # Clean up
    :gen_tcp.close(server_socket)
    :gen_tcp.close(client)
    :gen_tcp.close(listen)
  end

  test "handle_info :unknown logs and continues" do
    state = %{socket: :dummy, src_ip: "1", src_port: 2}
    assert {:noreply, ^state} = TCPHandler.handle_info(:unknown, state)
  end

  test "handle_info :accept_loop catch-all" do
    state = %{socket: :dummy, src_ip: "1", src_port: 2}
    assert {:noreply, ^state} = TCPHandler.handle_info(:accept_loop, state)
  end
  
  test "handle_info :tcp_closed returns stop" do
    state = %{socket: :dummy, src_ip: "1.2.3.4", src_port: 80}
    assert {:stop, :normal, ^state} = TCPHandler.handle_info({:tcp_closed, :dummy}, state)
  end
  
  test "handle_info :tcp_error stops the process" do
    state = %{socket: :dummy_socket, src_ip: "1.2.3.4", src_port: 80}
    msg = {:tcp_error, :dummy_socket, :econnreset}
    assert {:stop, :shutdown, state} == TCPHandler.handle_info(msg, state)
  end
end
