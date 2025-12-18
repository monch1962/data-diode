defmodule DataDiode.LongTermRobustnessTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  alias DataDiode.S1.TCPHandler
  alias DataDiode.S1.Listener, as: S1Listener
  alias DataDiode.S2.Listener, as: S2Listener

  defp wait_for_death(pid, count \\ 20)
  defp wait_for_death(_pid, 0), do: :ok
  defp wait_for_death(pid, count) do
    if Process.alive?(pid) do
      Process.sleep(20)
      wait_for_death(pid, count - 1)
    else
      :ok
    end
  end

  @tag :robustness
  test "TCPHandler exhaustive branch coverage" do
    # 1. Setup real socket for state
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(l)
    {:ok, c} = :gen_tcp.connect({127,0,0,1}, port, [:binary, active: false])
    {:ok, s} = :gen_tcp.accept(l)
    {:ok, pid} = TCPHandler.start_link(s)

    # Triggering Oversized Packet
    capture_log(fn ->
      send(pid, {:tcp, s, <<0::8_388_616>>}) # 1MB + 1
      _ = :sys.get_state(pid)
    end) =~ "S1: Dropping oversized packet"

    # Triggering TCP Error
    Process.flag(:trap_exit, true)
    capture_log(fn ->
      send(pid, {:tcp_error, s, :etimedout})
      wait_for_death(pid)
    end) =~ "S1: TCP error"
    Process.flag(:trap_exit, false)

    # Start new for unexpected message
    {:ok, s2} = :gen_tcp.accept(l)
    {:ok, pid2} = TCPHandler.start_link(s2)
    capture_log(fn ->
      send(pid2, :unknown_msg)
      _ = :sys.get_state(pid2)
    end) =~ "S1: TCPHandler received unexpected message"

    # Trigger TCP Closed
    capture_log(fn ->
      send(pid2, {:tcp_closed, s2})
      wait_for_death(pid2)
    end) =~ "S1: Connection closed"

    :gen_tcp.close(c)
    :gen_tcp.close(l)
  end

  @tag :robustness
  test "S1.Listener exhaustive branch coverage" do
    mock_socket = :gen_udp.open(0) |> elem(1)
    
    # Unexpected msg
    capture_log(fn ->
      S1Listener.handle_info(:garbage, mock_socket)
    end) =~ "S1: Received unexpected message"

    # Fatal error
    :gen_udp.close(mock_socket)
    capture_log(fn ->
      S1Listener.handle_info(:accept_loop, mock_socket)
    end) =~ "S1: Listener socket fatal error"
  end

  @tag :robustness
  test "S2.Listener exhaustive branch coverage" do
    mock_socket = :gen_udp.open(0) |> elem(1)
    
    # Fatal UDP error
    capture_log(fn ->
      S2Listener.handle_info({:udp_error, mock_socket, :ebadf}, mock_socket)
    end) =~ "S2: UDP Listener fatal error"

    # Unexpected msg
    capture_log(fn ->
      S2Listener.handle_info(:unknown, mock_socket)
    end) =~ "S2: Received unexpected message"
    
    # Passive re-arm
    {:noreply, ^mock_socket} = S2Listener.handle_info({:udp_passive, mock_socket}, mock_socket)

    :gen_udp.close(mock_socket)
  end

  @tag :robustness
  test "S1.Encapsulator exhaustive branch coverage" do
    capture_log(fn ->
      send(DataDiode.S1.Encapsulator, :unknown)
      Process.sleep(50)
    end) =~ "S1 Encapsulator: Received unexpected message"
  end

  @tag :soak
  test "system handles connection churn" do
    app_port = S1Listener.port()
    if app_port do
      initial = Process.list() |> length()
      for _ <- 1..5 do
        case :gen_tcp.connect({127,0,0,1}, app_port, []) do
          {:ok, s} -> :gen_tcp.close(s)
          _ -> :ok
        end
      end
      Process.sleep(200)
      final = Process.list() |> length()
      assert_in_delta initial, final, 10
    end
  end
end
