defmodule DataDiode.DiskCleanerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias DataDiode.DiskCleaner

  test "get_disk_free_percent handles df output correctly" do
    # This is hard to mock System.cmd without Mox, but we can test the parsing logic
    # if we expose it, or just rely on the real command on Mac/Linux.
    percent = DiskCleaner.get_disk_free_percent("/")
    assert is_integer(percent)
    assert percent >= 0 and percent <= 100
  end

  test "data_dir returns configured or default directory" do
    Application.put_env(:data_diode, :data_dir, "/tmp/diode_test")
    assert DiskCleaner.data_dir() == "/tmp/diode_test"
    
    Application.delete_env(:data_diode, :data_dir)
    assert DiskCleaner.data_dir() == "."
  end

  test "cleanup_disk logs simulation message" do
    assert capture_log(fn ->
      DiskCleaner.cleanup_disk("/tmp")
    end) =~ "DiskCleaner: Simulation - would delete oldest .dat files"
  end

  setup do
    Application.put_env(:data_diode, :disk_cleaner_interval, 0)
    on_exit(fn ->
      Application.delete_env(:data_diode, :disk_cleaner_interval)
    end)
    :ok
  end

  test "handle_info :cleanup schedules next cleanup" do
    # We use a manual start to avoid the automatic scheduling for this test if needed,
    # but here we just test the callback.
    {:noreply, _state} = DiskCleaner.handle_info(:cleanup, %{})
    # Verify a message is sent to self
    assert_receive :cleanup, 500
  end
end
