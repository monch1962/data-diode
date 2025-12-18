defmodule DataDiode.S1.HandlerSupervisorTest do
  use ExUnit.Case, async: false
  alias DataDiode.S1.HandlerSupervisor

  test "start_handler/1 starts a TCPHandler process" do
    # We need a dummy socket or a real one.
    # TCPHandler.start_link requires a socket.
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, reuseaddr: true, active: false])
    {:ok, port} = :inet.port(listen_socket)
    {:ok, client_socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, server_socket} = :gen_tcp.accept(listen_socket)

    assert {:ok, pid} = HandlerSupervisor.start_handler(server_socket)
    # Handover ownership so the backend can activate
    assert :ok = :gen_tcp.controlling_process(server_socket, pid)
    send(pid, :activate)
    
    # Wait for :activate to finish
    Process.sleep(50)
    assert Process.alive?(pid)
    
    # Clean up
    :gen_tcp.close(client_socket)
    :gen_tcp.close(server_socket)
    :gen_tcp.close(listen_socket)
  end

  test "handles rapid connections and disconnects" do
    # Start a real listener to accept connections
    port = 8092
    Application.put_env(:data_diode, :s1_port, port)
    {:ok, l_pid} = DataDiode.S1.Listener.start_link(name: :stress_test_listener)
    
    # Rapidly connect and disconnect 50 clients
    Enum.each(1..50, fn _ ->
      {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [])
      :gen_tcp.close(client)
    end)
    
    # Give supervisors time to catch up
    Process.sleep(100)
    
    # Just verify the supervisor is still alive and responsive
    assert %{active: _} = DynamicSupervisor.count_children(DataDiode.S1.HandlerSupervisor)
    
    GenServer.stop(l_pid)
  end

  test "init/1 returns supervisor flags" do
    assert {:ok, %{strategy: :one_for_one}} = HandlerSupervisor.init([])
  end
end
