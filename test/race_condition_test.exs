defmodule DataDiode.RaceConditionTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  alias DataDiode.Metrics
  alias DataDiode.S2.Listener

  setup do
    Application.put_env(:data_diode, :s2_port, 0)
    # Ensure a fresh metrics state if possible, though it's global
    :ok
  end

  # Ensure application is started for all tests
  setup do
    Application.ensure_all_started(:data_diode)
    :ok
  end

  test "S2.Listener task exhaustion is now visible" do
    # 1. Start a real listener with a unique name
    {:ok, pid} = Listener.start_link(name: :s2_exhaustion_test_v2)
    socket = :sys.get_state(pid)
    {:ok, port} = :inet.port(socket)

    # 2. Fill up the Task Supervisor
    tasks =
      Enum.map(1..200, fn _ ->
        Task.Supervisor.async_nolink(DataDiode.S2.TaskSupervisor, fn ->
          Process.sleep(1000)
        end)
      end)

    # 3. Send the 201st packet.
    {:ok, sender} = :gen_udp.open(0)
    packet = <<127, 0, 0, 1, 0, 80, "overflow">>

    log =
      capture_log(fn ->
        :ok = :gen_udp.send(sender, {127, 0, 0, 1}, port, packet)
        Process.sleep(100)
      end)

    # VERIFY FIX: The log should now contain the error message
    assert log =~ "Failed to spawn processing task"
    assert log =~ "max_children"

    # Clean up
    Enum.each(tasks, fn t -> Task.shutdown(t, :brutal_kill) end)
    :gen_udp.close(sender)
    GenServer.stop(pid)
  end

  test "Concurrent Write/Delete Stress (No crash)" do
    path = "/tmp/diode_stress_v2"
    File.mkdir_p!(path)
    Application.put_env(:data_diode, :data_dir, path)

    # Spawn 50 concurrent writers
    writers =
      Enum.map(1..50, fn _ ->
        Task.async(fn ->
          Enum.each(1..20, fn i ->
            DataDiode.S2.Decapsulator.process_packet(<<127, 0, 0, 1, 80, 0, 0, 0, 4, "data#{i}">>)
          end)
        end)
      end)

    # Simultaneously run cleaner
    cleaner_task =
      Task.async(fn ->
        Enum.each(1..10, fn _ ->
          DataDiode.DiskCleaner.handle_info(:cleanup, %{})
          Process.sleep(10)
        end)
      end)

    Enum.each(writers, &Task.await(&1, 5000))
    Task.await(cleaner_task)

    # Verify no crashes occurred. Since it's a simulation, we just expect :ok
    Logger.info("Stress test completed successfully without crashes.")

    # Clean up
    File.rm_rf!(path)
    Application.delete_env(:data_diode, :data_dir)
  end
end
