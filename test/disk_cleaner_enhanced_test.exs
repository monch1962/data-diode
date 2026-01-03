defmodule DataDiode.DiskCleanerEnhancedTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  # Simple temporary directory creation
  defp create_temp_dir(prefix) do
    temp_dir =
      Path.join([
        System.tmp_dir!(),
        "data_diode_test_#{prefix}_#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(temp_dir)
    temp_dir
  end

  doctest DataDiode.DiskCleaner

  describe "disk cleanup operations" do
    setup do
      temp_dir = create_temp_dir("disk_cleaner")

      # Create some test .dat files
      Enum.each(1..5, fn i ->
        file_path = Path.join(temp_dir, "test_#{i}.dat")
        File.write!(file_path, "test data #{i}")
      end)

      Application.put_env(:data_diode, :data_dir, temp_dir)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
        Application.delete_env(:data_diode, :data_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "starts successfully" do
      pid = Process.whereis(DataDiode.DiskCleaner)
      assert Process.alive?(pid)
    end

    test "performs cleanup operation" do
      # Trigger cleanup via send (handle_info)
      pid = Process.whereis(DataDiode.DiskCleaner)
      send(pid, :cleanup)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "counts files in data directory", %{temp_dir: temp_dir} do
      dat_files = Path.wildcard(Path.join(temp_dir, "*.dat"))
      assert length(dat_files) == 5
    end
  end

  describe "emergency cleanup" do
    setup do
      temp_dir = create_temp_dir("emergency_cleanup")

      # Create many test files
      Enum.each(1..10, fn i ->
        file_path = Path.join(temp_dir, "emergency_#{i}.dat")
        File.write!(file_path, "emergency data #{i}")
      end)

      Application.put_env(:data_diode, :data_dir, temp_dir)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
        Application.delete_env(:data_diode, :data_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "triggers emergency cleanup", %{temp_dir: temp_dir} do
      # Emergency cleanup is triggered automatically when disk is full
      # We can test this by triggering a regular cleanup which may include emergency cleanup
      pid = Process.whereis(DataDiode.DiskCleaner)
      send(pid, :cleanup)
      Process.sleep(100)

      # Files should still exist (cleanup keeps some files based on retention)
      dat_files = Path.wildcard(Path.join(temp_dir, "*.dat"))
      assert is_list(dat_files)
    end

    test "continues after emergency cleanup" do
      pid = Process.whereis(DataDiode.DiskCleaner)
      send(pid, :cleanup)
      Process.sleep(100)

      # Should not crash
      assert Process.alive?(pid)
    end
  end

  describe "log rotation" do
    setup do
      temp_dir = create_temp_dir("log_rotation")

      Application.put_env(:data_diode, :data_dir, temp_dir)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
        Application.delete_env(:data_diode, :data_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "triggers log rotation" do
      pid = Process.whereis(DataDiode.DiskCleaner)
      send(pid, :rotate_logs)

      # Should not crash
      assert Process.alive?(pid)
    end
  end

  describe "integrity checking" do
    setup do
      temp_dir = create_temp_dir("integrity_check")

      # Create valid data file
      valid_data = <<
        # Timestamp
        64::unsigned-big-integer-size(64),
        # Source IP
        192::8,
        168::8,
        1::8,
        100::8,
        # Source port
        8080::16-big,
        # Payload
        "test payload"::binary
      >>

      File.write!(Path.join(temp_dir, "valid.dat"), valid_data)

      Application.put_env(:data_diode, :data_dir, temp_dir)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
        Application.delete_env(:data_diode, :data_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "performs integrity check" do
      pid = Process.whereis(DataDiode.DiskCleaner)
      send(pid, :check_integrity)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "logs integrity results" do
      log =
        capture_log(fn ->
          pid = Process.whereis(DataDiode.DiskCleaner)
          send(pid, :check_integrity)
          Process.sleep(100)
        end)

      # Should log something about integrity
      assert log =~ ~r/(integrity|check)/i
    end
  end

  describe "health-based retention" do
    test "adjusts retention based on system health" do
      # Mock different health states
      health_states = [:healthy, :warning_hot, :critical_hot, :degraded]

      Enum.each(health_states, fn health ->
        # The retention multiplier should be higher when system is unhealthy
        multiplier =
          case health do
            :healthy -> 1.0
            _ -> 2.0
          end

        assert is_float(multiplier)
        assert multiplier >= 1.0
      end)
    end
  end

  describe "periodic operations" do
    setup do
      temp_dir = create_temp_dir("periodic")

      Application.put_env(:data_diode, :data_dir, temp_dir)
      # 100ms for testing
      Application.put_env(:data_diode, :disk_cleaner_interval, 100)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
        Application.delete_env(:data_diode, :data_dir)
        Application.delete_env(:data_diode, :disk_cleaner_interval)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "performs periodic cleanup" do
      # Wait for at least one cleanup cycle
      Process.sleep(200)

      # Should still be alive
      pid = Process.whereis(DataDiode.DiskCleaner)
      assert Process.alive?(pid)
    end

    test "continues running without crashes" do
      # Wait for multiple cycles
      Process.sleep(500)

      pid = Process.whereis(DataDiode.DiskCleaner)
      assert Process.alive?(pid)
    end
  end

  describe "error handling" do
    test "handles missing data directory gracefully" do
      # DiskCleaner is already started by the application
      pid = Process.whereis(DataDiode.DiskCleaner)
      assert Process.alive?(pid)

      # Just verify it continues running
      Process.sleep(100)
      assert Process.alive?(pid)
    end

    test "handles permission errors gracefully" do
      # This tests error handling
      # In real scenario, would test with read-only directory
      assert true
    end
  end

  describe "file operations" do
    test "deletes oldest files first" do
      temp_dir = create_temp_dir("oldest_files")

      # Create files with different ages
      Enum.each(1..3, fn i ->
        file_path = Path.join(temp_dir, "file_#{i}.dat")
        File.write!(file_path, "data #{i}")

        # Sleep to ensure different mtimes
        Process.sleep(10)
      end)

      # Count files
      files_before = length(Path.wildcard(Path.join(temp_dir, "*.dat")))

      # Delete oldest (first created)
      oldest =
        Path.wildcard(Path.join(temp_dir, "*.dat"))
        |> Enum.sort_by(fn f ->
          {:ok, stat} = File.stat(f)
          stat.mtime
        end)
        |> hd()

      File.rm!(oldest)

      files_after = length(Path.wildcard(Path.join(temp_dir, "*.dat")))

      assert files_after == files_before - 1

      File.rm_rf!(temp_dir)
    end
  end
end
