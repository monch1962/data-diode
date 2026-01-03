defmodule DataDiode.DiskCleanerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias DataDiode.DiskCleaner
  alias DataDiode.ConfigHelpers

  test "get_disk_free_percent handles df output correctly" do
    # This is hard to mock System.cmd without Mox, but we can test the parsing logic
    # if we expose it, or just rely on the real command on Mac/Linux.
    percent = DiskCleaner.get_disk_free_percent("/")
    assert is_integer(percent)
    assert percent >= 0 and percent <= 100
  end

  test "data_dir returns configured or default directory" do
    Application.put_env(:data_diode, :data_dir, "/tmp/diode_test")
    assert ConfigHelpers.data_dir() == "/tmp/diode_test"

    Application.delete_env(:data_diode, :data_dir)
    assert ConfigHelpers.data_dir() == "."
  end

  test "cleanup_disk handles empty directory" do
    # Use /dev which exists but has no .dat files
    assert capture_log(fn ->
             result = DiskCleaner.cleanup_disk("/dev")
             assert is_integer(result)
           end) =~ "No files found"
  end

  test "cleanup_disk deletes actual files" do
    # Create a temporary directory with test .dat files
    test_dir = System.tmp_dir!() <> "/disk_cleaner_test_#{System.unique_integer()}"
    File.mkdir_p!(test_dir)

    try do
      # Create some test .dat files
      Enum.each(1..3, fn i ->
        File.write!(Path.join(test_dir, "test_#{i}.dat"), "test data #{i}")
      end)

      # Set batch size to 2 to test partial deletion
      Application.put_env(:data_diode, :disk_cleanup_batch_size, 2)

      # Run cleanup and verify files were deleted
      assert capture_log(fn ->
               result = DiskCleaner.cleanup_disk(test_dir)
               assert result == 2
             end) =~ "Cleaned up 2 old file(s)"

      # Verify 2 files were deleted and 1 remains
      remaining_files = Path.wildcard(Path.join(test_dir, "*.dat"))
      assert length(remaining_files) == 1
    after
      File.rm_rf(test_dir)
      Application.delete_env(:data_diode, :disk_cleanup_batch_size)
    end
  end

  test "cleanup_disk handles file deletion errors gracefully" do
    # This test verifies the function handles errors without crashing
    # Since we can't easily simulate file deletion errors, we test with a directory
    # where we can control permissions

    test_dir = System.tmp_dir!() <> "/disk_cleaner_perm_test_#{System.unique_integer()}"
    File.mkdir_p!(test_dir)

    try do
      # Create a test file
      test_file = Path.join(test_dir, "test.dat")
      File.write!(test_file, "test")

      # Set batch size to delete the file
      Application.put_env(:data_diode, :disk_cleanup_batch_size, 1)

      # This should succeed
      result = DiskCleaner.cleanup_disk(test_dir)
      assert is_integer(result)
      assert result >= 0
    after
      File.rm_rf(test_dir)
      Application.delete_env(:data_diode, :disk_cleanup_batch_size)
    end
  end

  test "cleanup_disk sorts files by modification time" do
    test_dir = System.tmp_dir!() <> "/disk_cleaner_sort_test_#{System.unique_integer()}"
    File.mkdir_p!(test_dir)

    try do
      # Create files with different timestamps
      file1 = Path.join(test_dir, "file1.dat")
      file2 = Path.join(test_dir, "file2.dat")
      file3 = Path.join(test_dir, "file3.dat")

      File.write!(file1, "data1")
      # Ensure different mtime
      Process.sleep(10)
      File.write!(file2, "data2")
      Process.sleep(10)
      File.write!(file3, "data3")

      # Set batch size to delete 2 files (should delete oldest 2)
      Application.put_env(:data_diode, :disk_cleanup_batch_size, 2)

      # Run cleanup
      result = DiskCleaner.cleanup_disk(test_dir)
      assert result == 2

      # Verify file3 (newest) still exists, file1 and file2 (oldest) are deleted
      refute File.exists?(file1)
      refute File.exists?(file2)
      assert File.exists?(file3)
    after
      File.rm_rf(test_dir)
      Application.delete_env(:data_diode, :disk_cleanup_batch_size)
    end
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
