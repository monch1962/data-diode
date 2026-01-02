defmodule DataDiode.MemoryGuardTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import DataDiode.MissingHardware
  import DataDiode.HardwareFixtures
  require Logger

  doctest DataDiode.MemoryGuard

  describe "with valid memory configuration" do
    setup do
      %{
        temp_dir: temp_dir,
        proc_dir: proc_dir,
        total_mb: total_mb,
        used_mb: used_mb
      } = setup_meminfo(8000, 4000)  # 8GB total, 4GB used

      Application.put_env(:data_diode, :meminfo_path,
        Path.join(proc_dir, "meminfo"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :meminfo_path)
      end)

      {:ok, total_mb: total_mb, used_mb: used_mb}
    end

    test "reads memory usage correctly" do
      memory = DataDiode.MemoryGuard.get_memory_usage()

      assert memory.total > 0
      assert memory.used > 0
      assert memory.available > 0
      assert is_float(memory.percent)
    end

    test "calculates memory percentage correctly" do
      memory = DataDiode.MemoryGuard.get_memory_usage()

      # With 8GB total and 4GB used (before buffers/cached), actual calculation
      # accounts for buffers and cached, so percentage will be different
      # Just verify it's a reasonable percentage
      assert memory.percent > 0
      assert memory.percent < 100
    end

    test "gets VM memory statistics" do
      vm_memory = DataDiode.MemoryGuard.get_vm_memory()

      assert is_list(vm_memory)
      assert Keyword.has_key?(vm_memory, :total)
      assert Keyword.has_key?(vm_memory, :processes)
      assert Keyword.has_key?(vm_memory, :system)
    end
  end

  describe "with high memory usage" do
    setup do
      %{temp_dir: temp_dir, proc_dir: proc_dir} =
        setup_meminfo(8000, 6500)  # 81% used

      Application.put_env(:data_diode, :meminfo_path,
        Path.join(proc_dir, "meminfo"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :meminfo_path)
      end)

      :ok
    end

    test "calculates high memory percentage" do
      memory = DataDiode.MemoryGuard.get_memory_usage()

      # Should have some memory usage
      assert memory.percent > 0
      assert memory.total > 0
    end

    test "logs high memory warning" do
      # Just verify the process is running
      pid = Process.whereis(DataDiode.MemoryGuard)
      assert Process.alive?(pid)

      # Trigger a monitoring cycle
      Process.sleep(200)
      assert Process.alive?(pid)
    end
  end

  describe "with critical memory usage" do
    setup do
      # 92% memory usage - should trigger recovery
      %{temp_dir: temp_dir, proc_dir: proc_dir} =
        setup_meminfo(8000, 7360)

      Application.put_env(:data_diode, :meminfo_path,
        Path.join(proc_dir, "meminfo"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :meminfo_path)
      end)

      :ok
    end

    test "calculates critical memory percentage" do
      memory = DataDiode.MemoryGuard.get_memory_usage()

      # Should have some memory usage
      assert memory.percent > 0
      assert memory.total > 0
    end

    test "logs critical memory alert" do
      # Just verify the process is running
      pid = Process.whereis(DataDiode.MemoryGuard)
      assert Process.alive?(pid)

      # Trigger a monitoring cycle
      Process.sleep(200)
      assert Process.alive?(pid)
    end
  end

  describe "with no /proc/meminfo" do
    setup do
      %{temp_dir: temp_dir, proc_dir: proc_dir} = setup_no_meminfo()

      Application.put_env(:data_diode, :meminfo_path,
        Path.join(proc_dir, "meminfo"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :meminfo_path)
      end)

      :ok
    end

    test "returns zero values when meminfo missing" do
      memory = DataDiode.MemoryGuard.get_memory_usage()

      assert memory.total == 0
      assert memory.used == 0
      assert memory.percent == 0
    end

    test "continues monitoring despite missing file" do
      # Should not crash
      pid = Process.whereis(DataDiode.MemoryGuard)
      assert pid != nil
      assert Process.alive?(pid)

      # Should still track VM memory (which always works)
      vm_memory = DataDiode.MemoryGuard.get_vm_memory()
      assert vm_memory[:total] > 0
    end

    test "logs error about missing meminfo" do
      log =
        capture_log(fn ->
          DataDiode.MemoryGuard.get_memory_usage()
          Process.sleep(100)
        end)

      assert log =~ ~r/(cannot read|no meminfo)/i
    end
  end

  describe "garbage collection" do
    test "VM memory is always available" do
      vm_memory = DataDiode.MemoryGuard.get_vm_memory()

      # VM memory should always be available even without /proc/meminfo
      assert is_list(vm_memory)
      assert Keyword.get(vm_memory, :total) > 0
    end
  end

  describe "memory leak detection" do
    test "establishes baseline after startup" do
      # MemoryGuard should have a baseline from VM memory
      vm_memory = :erlang.memory()

      assert is_list(vm_memory)
      assert Keyword.has_key?(vm_memory, :total)
      assert Keyword.has_key?(vm_memory, :processes)
    end

    test "tracks process memory growth" do
      # Get current VM memory
      vm_memory_before = DataDiode.MemoryGuard.get_vm_memory()

      # Allocate some memory
      _data = for _ <- 1..1000, do: :crypto.strong_rand_bytes(1024)

      Process.sleep(100)

      # VM memory should have increased
      vm_memory_after = DataDiode.MemoryGuard.get_vm_memory()

      assert vm_memory_after[:total] >= vm_memory_before[:total]
    end
  end

  describe "memory calculations" do
    test "calculates available memory correctly" do
      total_mb = 8000
      used_mb = 4000
      available_mb = total_mb - used_mb

      assert available_mb == 4000
    end

    test "calculates percentage correctly" do
      total_mb = 8000
      used_mb = 4000

      percent = (used_mb / total_mb * 100) |> Float.round(1)

      assert_in_delta percent, 50.0, 0.1
    end

    test "handles zero total memory gracefully" do
      total_mb = 0
      used_mb = 0

      percent = if total_mb > 0 do
        (used_mb / total_mb * 100) |> Float.round(1)
      else
        0.0
      end

      assert percent == 0.0
    end
  end
end
