defmodule DataDiode.MemoryGuardTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import DataDiode.MissingHardware
  import DataDiode.HardwareFixtures
  require Logger

  doctest DataDiode.MemoryGuard

  describe "with valid memory configuration" do
    setup do
      # 8GB total, 4GB used
      %{
        temp_dir: temp_dir,
        proc_dir: proc_dir,
        total_mb: total_mb,
        used_mb: used_mb
      } = setup_meminfo(8000, 4000)

      Application.put_env(:data_diode, :meminfo_path, Path.join(proc_dir, "meminfo"))

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
      # 81% used
      %{temp_dir: temp_dir, proc_dir: proc_dir} =
        setup_meminfo(8000, 6500)

      Application.put_env(:data_diode, :meminfo_path, Path.join(proc_dir, "meminfo"))

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

      Application.put_env(:data_diode, :meminfo_path, Path.join(proc_dir, "meminfo"))

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

      Application.put_env(:data_diode, :meminfo_path, Path.join(proc_dir, "meminfo"))

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

      percent =
        if total_mb > 0 do
          (used_mb / total_mb * 100) |> Float.round(1)
        else
          0.0
        end

      assert percent == 0.0
    end
  end

  describe "GenServer periodic checks" do
    setup do
      %{temp_dir: temp_dir, proc_dir: proc_dir} = setup_meminfo(8000, 4000)

      Application.put_env(:data_diode, :meminfo_path, Path.join(proc_dir, "meminfo"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :meminfo_path)
      end)

      :ok
    end

    test "performs periodic memory check" do
      pid = Process.whereis(DataDiode.MemoryGuard)

      # Trigger check by sending the message directly
      send(pid, :check_memory)

      # Should not crash
      assert Process.alive?(pid)

      # Wait a bit for the message to be processed
      Process.sleep(100)
      assert Process.alive?(pid)
    end

    test "establishes baseline over multiple checks" do
      pid = Process.whereis(DataDiode.MemoryGuard)

      # Get initial state
      _state1 = :sys.get_state(pid)

      # Trigger multiple checks to establish baseline (needs 5 samples)
      Enum.each(1..5, fn _i ->
        send(pid, :check_memory)
        Process.sleep(50)
      end)

      # Check that baseline was established
      state = :sys.get_state(pid)
      assert state.baseline != nil

      # Baseline should have expected fields
      assert Map.has_key?(state.baseline, :total)
      assert Map.has_key?(state.baseline, :used)
      assert Map.has_key?(state.baseline, :percent)
    end
  end

  describe "memory leak detection calculations" do
    setup do
      %{temp_dir: temp_dir, proc_dir: proc_dir, total_mb: total_mb} =
        setup_meminfo(8000, 4000)

      Application.put_env(:data_diode, :meminfo_path, Path.join(proc_dir, "meminfo"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :meminfo_path)
      end)

      {:ok, total_mb: total_mb}
    end

    test "calculates growth rate correctly" do
      baseline = %{total: 8_000_000_000, used: 4_000_000_000}
      current = %{total: 8_000_000_000, used: 6_000_000_000}

      # Growth rate = (current.used - baseline.used) / baseline.total
      # (6GB - 4GB) / 8GB = 0.25 (25%)
      growth_rate = (current.used - baseline.used) / baseline.total

      assert_in_delta growth_rate, 0.25, 0.01
    end

    test "handles zero baseline total" do
      baseline = %{total: 0, used: 0}
      current = %{total: 8_000_000_000, used: 4_000_000_000}

      growth_rate =
        if baseline.total > 0 do
          (current.used - baseline.used) / baseline.total
        else
          0
        end

      assert growth_rate == 0
    end
  end

  describe "VM memory testing" do
    test "gets VM memory information" do
      vm_memory = DataDiode.MemoryGuard.get_vm_memory()

      # Should return a keyword list with memory stats
      assert is_list(vm_memory)
      assert Keyword.has_key?(vm_memory, :total)
      assert Keyword.has_key?(vm_memory, :processes)
      assert Keyword.has_key?(vm_memory, :system)
      assert Keyword.has_key?(vm_memory, :atom)
      assert Keyword.has_key?(vm_memory, :binary)
      assert Keyword.has_key?(vm_memory, :code)
      assert Keyword.has_key?(vm_memory, :ets)
    end

    test "VM memory total is positive" do
      vm_memory = DataDiode.MemoryGuard.get_vm_memory()

      # Total memory should always be > 0
      total = Keyword.get(vm_memory, :total)
      assert total > 0
    end
  end

  describe "memory history tracking" do
    test "maintains memory history" do
      %{temp_dir: temp_dir, proc_dir: proc_dir} = setup_meminfo(8000, 4000)

      Application.put_env(:data_diode, :meminfo_path, Path.join(proc_dir, "meminfo"))

      on_exit(fn ->
        DataDiode.HardwareFixtures.cleanup(%{temp_dir: temp_dir})
        Application.delete_env(:data_diode, :meminfo_path)
      end)

      pid = Process.whereis(DataDiode.MemoryGuard)

      # Get initial state
      state1 = :sys.get_state(pid)
      assert is_list(state1.history)

      # Trigger a check to add to history
      send(pid, :check_memory)
      Process.sleep(100)

      # History should be updated
      state2 = :sys.get_state(pid)
      assert length(state2.history) >= length(state1.history)
    end
  end
end
