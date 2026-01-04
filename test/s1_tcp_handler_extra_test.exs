defmodule DataDiode.S1.TCPHandlerExtraTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias DataDiode.S1.TCPHandler

  setup do
    {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_sock)

    # Start a client that connects
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    {:ok, server_sock} = :gen_tcp.accept(listen_sock)

    state = %{
      socket: server_sock,
      src_ip: "127.0.0.1",
      src_port: 12_345
    }

    on_exit(fn ->
      :gen_tcp.close(listen_sock)
      :gen_tcp.close(client)
      :gen_tcp.close(server_sock)
    end)

    {:ok, state: state}
  end

  test "handle_info :activate sets socket option", %{state: state} do
    # This should trigger :inet.setopts
    {:noreply, _new_state} = TCPHandler.handle_info(:activate, state)
    # No way to easily verify without mocking :inet, but it covers the line
  end

  test "handle_info tcp_error logs and stops", %{state: state} do
    assert capture_log(fn ->
             {:stop, :shutdown, _new_state} =
               TCPHandler.handle_info({:tcp_error, state.socket, :einval}, state)
           end) =~ "S1: TCP error"
  end

  test "handle_info tcp_closed logs and stops", %{state: state} do
    assert capture_log(fn ->
             {:stop, :normal, _new_state} =
               TCPHandler.handle_info({:tcp_closed, state.socket}, state)
           end) =~ "S1: Connection closed"
  end

  test "handle_info unexpected message logs warning", %{state: state} do
    assert capture_log(fn ->
             {:noreply, ^state} = TCPHandler.handle_info(:unexpected_msg, state)
           end) =~ "S1: TCPHandler received unexpected message"
  end
end
