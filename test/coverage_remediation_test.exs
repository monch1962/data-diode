defmodule DataDiode.CoverageRemediationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  setup do
    Application.ensure_all_started(:data_diode)
    :ok
  end

  test "S1 Heartbeat: unexpected message" do
    assert capture_log(fn ->
             send(DataDiode.S1.Heartbeat, :unexpected)
             Process.sleep(10)
           end) =~ "S1 Heartbeat: Received unexpected message: :unexpected"
  end

  test "S2 HeartbeatMonitor: unexpected message" do
    assert capture_log(fn ->
             send(DataDiode.S2.HeartbeatMonitor, :unexpected)
             Process.sleep(10)
           end) =~ "S2 HeartbeatMonitor: Received unexpected message: :unexpected"
  end

  test "SystemMonitor: unexpected message and df failure" do
    assert capture_log(fn ->
             send(DataDiode.SystemMonitor, :unexpected)
             Process.sleep(10)
           end) =~ "SystemMonitor: Received unexpected message: :unexpected"

    assert DataDiode.SystemMonitor.get_disk_free(nil) == "unknown"
    assert DataDiode.SystemMonitor.get_disk_free("/invalid/path") == "unknown"
  end

  test "DiskCleaner: df failure path" do
    # We can't easily make System.cmd fail unless we mock it,
    # but we can test the public helper with a bad path.
    # Actually get_disk_free_percent is public.
    assert DataDiode.DiskCleaner.get_disk_free_percent("/non/existent/path/at/all") == 100
  end

  test "Watchdog: pulse write failure" do
    # Make path a directory so File.write fails with :eisdir
    tmp_dir = Path.join(System.tmp_dir!(), "watchdog_fail_dir")
    File.mkdir_p!(tmp_dir)

    assert capture_log(fn ->
             DataDiode.Watchdog.pulse(tmp_dir)
           end) =~ "Watchdog: Failed to pulse"

    File.rm_rf(tmp_dir)
  end

  test "Decapsulator: atomic rename failure simulated" do
    # This is tricky as it's private. But we can trigger it
    # by making the data_dir a location where we can write but not rename?
    # Or just ensure data_dir is a file.

    orig_dir = Application.get_env(:data_diode, :data_dir)
    DataDiode.Metrics.reset_stats()

    # Use a file as the data_dir
    tmp_file = Path.join(System.tmp_dir!(), "decapsulator_fail_file")
    File.write!(tmp_file, "")
    Application.put_env(:data_diode, :data_dir, tmp_file)

    packet = <<127, 0, 0, 1, 0, 80, "PAYLOAD">>
    checksum = :erlang.crc32(packet)
    full_packet = packet <> <<checksum::32>>

    assert capture_log(fn ->
             assert {:error, _} = DataDiode.S2.Decapsulator.process_packet(full_packet)
           end) =~ "S2: Secure write failed"

    # Restore
    Application.put_env(:data_diode, :data_dir, orig_dir)
    File.rm(tmp_file)
  end
end
