defmodule DataDiode.MemoryGuard do
  @moduledoc """
  Memory monitoring and leak detection for long-running systems in harsh environments.

  Features:
  - Monitors memory usage every 5 minutes
  - Detects memory leaks by comparing against baseline
  - Triggers garbage collection at warning levels (80%)
  - Triggers recovery at critical levels (90%)
  - Logs memory usage statistics
  - Tracks top memory-consuming processes

  Critical for systems that run for months without maintenance.
  """

  use GenServer
  require Logger

  # 5 minutes
  @memory_check_interval 300_000
  # 80%
  @memory_warning_threshold 80
  # 90%
  @memory_critical_threshold 90
  # 50% growth since baseline
  @growth_rate_warning 0.5
  # Number of samples to establish baseline
  @baseline_samples 5

  @type memory_stats :: %{
          total: non_neg_integer(),
          used: non_neg_integer(),
          available: non_neg_integer(),
          percent: float(),
          buffers: non_neg_integer(),
          cached: non_neg_integer(),
          timestamp: integer()
        }

  @type state :: %{
          baseline: memory_stats() | nil,
          samples: [memory_stats()],
          history: [memory_stats()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  @spec init(:ok) :: {:ok, state()}
  def init(:ok) do
    Logger.info("MemoryGuard: Starting memory monitoring")
    schedule_check()
    {:ok, %{baseline: nil, samples: [], history: []}}
  end

  @impl true
  @spec handle_info(:check_memory, state()) :: {:noreply, state()}
  def handle_info(:check_memory, state) do
    current = get_memory_usage()
    new_state = track_baseline(state, current)

    cond do
      current.percent >= @memory_critical_threshold ->
        Logger.error("MemoryGuard: Critical memory usage (#{current.percent}%)")
        trigger_memory_recovery(current)

      state.baseline != nil ->
        growth_rate = calculate_growth_rate(state.baseline, current)

        if growth_rate > @growth_rate_warning do
          Logger.warning(
            "MemoryGuard: Memory leak detected (#{:erlang.float_to_binary(growth_rate * 100, decimals: 1)}% growth)"
          )

          log_memory_analysis()
        end

      current.percent >= @memory_warning_threshold ->
        Logger.warning("MemoryGuard: High memory usage (#{current.percent}%)")
        trigger_garbage_collection()

      true ->
        :ok
    end

    # Log memory stats periodically
    new_state = log_memory_stats(new_state, current)

    schedule_check()
    {:noreply, new_state}
  end

  @doc """
  Gets current memory usage statistics.
  """
  @spec get_memory_usage() :: memory_stats()
  def get_memory_usage do
    # Read from configured meminfo path (default: /proc/meminfo)
    meminfo_path = Application.get_env(:data_diode, :meminfo_path, "/proc/meminfo")

    case File.read(meminfo_path) do
      {:ok, meminfo} ->
        total = parse_meminfo(meminfo, "MemTotal:")
        # If MemAvailable not available (older kernels), calculate from MemFree
        available = parse_meminfo(meminfo, "MemFree:", total)
        buffers = parse_meminfo(meminfo, "Buffers:", 0)
        cached = parse_meminfo(meminfo, "Cached:", 0)

        # Available = free + buffers + cached (reclaimable)
        available = available + buffers + cached

        used = total - available
        percent = (used / total * 100) |> Float.round(1)

        %{
          total: total,
          used: used,
          available: available,
          percent: percent,
          buffers: buffers,
          cached: cached,
          timestamp: System.system_time(:millisecond)
        }

      {:error, reason} ->
        meminfo_path = Application.get_env(:data_diode, :meminfo_path, "/proc/meminfo")
        Logger.error("MemoryGuard: Cannot read #{meminfo_path}: #{inspect(reason)}")
        %{total: 0, used: 0, available: 0, percent: 0}
    end
  end

  @doc """
  Gets Erlang VM memory statistics.
  """
  @spec get_vm_memory() :: keyword()
  def get_vm_memory do
    :erlang.memory()
  end

  # Baseline tracking

  defp track_baseline(%{baseline: nil} = state, current) do
    # Collect samples to establish baseline
    new_samples = [current | state.samples] |> Enum.take(@baseline_samples)

    new_state = %{state | samples: new_samples}

    if length(new_samples) >= @baseline_samples do
      # Calculate baseline from samples
      baseline = calculate_baseline(new_samples)

      Logger.info(
        "MemoryGuard: Baseline established: #{baseline.percent}% used (#{div(baseline.used, 1024)}MB)"
      )

      %{new_state | baseline: baseline, samples: []}
    else
      new_state
    end
  end

  defp track_baseline(state, _current), do: state

  defp calculate_baseline(samples) do
    # Average the samples
    count = length(samples)
    total_used = Enum.reduce(samples, 0, fn s, acc -> acc + s.used end)
    total_avail = Enum.reduce(samples, 0, fn s, acc -> acc + s.available end)

    %{
      total: hd(samples).total,
      used: div(total_used, count),
      available: div(total_avail, count),
      percent: (total_used / (total_used + total_avail) * 100) |> Float.round(1)
    }
  end

  defp calculate_growth_rate(baseline, current) do
    if baseline.total > 0 do
      (current.used - baseline.used) / baseline.total
    else
      0
    end
  end

  # Memory info parsing

  defp parse_meminfo(meminfo, key, default \\ nil) do
    case Regex.run(~r/#{key}\s+(\d+)\s+kB/, meminfo) do
      [_, value] ->
        # Convert KB to bytes
        String.to_integer(value) * 1024

      nil ->
        if default, do: default, else: 0
    end
  end

  # Recovery actions

  defp trigger_garbage_collection do
    Logger.info("MemoryGuard: Triggering garbage collection")

    # Force garbage collection on all processes
    :erlang.garbage_collect()

    # Collect GC stats
    before = :erlang.memory(:total)
    :erlang.garbage_collect()
    after_gc = :erlang.memory(:total)

    freed = before - after_gc

    if freed > 0 do
      Logger.info("MemoryGuard: Garbage collection freed #{div(freed, 1_048_576)}MB")
    end
  end

  defp trigger_memory_recovery(current) do
    Logger.error("MemoryGuard: Triggering memory recovery")

    # Force garbage collection
    :erlang.garbage_collect()

    # Restart non-critical processes to free memory
    restart_non_critical_processes()

    # Trigger disk cleanup to free disk cache
    send(DataDiode.DiskCleaner, :cleanup)

    # Log detailed analysis
    log_memory_analysis()

    # As last resort, could restart specific processes
    if current.percent > 95 do
      Logger.error("MemoryGuard: Memory usage critical, considering process restart")
      # Could restart encapsulator/decapsulator here
    end
  end

  defp restart_non_critical_processes do
    # Restart metrics collector (non-critical)
    if Process.whereis(DataDiode.Metrics) do
      Logger.info("MemoryGuard: Restarting Metrics to free memory")
      GenServer.stop(DataDiode.Metrics)
      Process.sleep(1000)
      # It should restart automatically via supervisor
    end
  end

  defp log_memory_analysis do
    vm_memory = get_vm_memory()
    system_memory = get_memory_usage()

    Logger.info("MemoryGuard: === Memory Analysis ===")

    Logger.info(
      "MemoryGuard: System: #{system_memory.percent}% used (#{div(system_memory.used, 1_048_576)}MB / #{div(system_memory.total, 1_048_576)}MB)"
    )

    Logger.info("MemoryGuard: Erlang VM: #{div(vm_memory[:total], 1_048_576)}MB")
    Logger.info("MemoryGuard:   - Total: #{div(vm_memory[:total], 1_048_576)}MB")
    Logger.info("MemoryGuard:   - Processes: #{div(vm_memory[:processes], 1_048_576)}MB")
    Logger.info("MemoryGuard:   - System: #{div(vm_memory[:system], 1_048_576)}MB")
    Logger.info("MemoryGuard:   - Atom: #{div(vm_memory[:atom], 1_048_576)}MB")
    Logger.info("MemoryGuard:   - Binary: #{div(vm_memory[:binary], 1_048_576)}MB")
    Logger.info("MemoryGuard:   - Code: #{div(vm_memory[:code], 1_048_576)}MB")
    Logger.info("MemoryGuard:   - ETS: #{div(vm_memory[:ets], 1_048_576)}MB")

    # Log process count
    process_count = :erlang.system_info(:process_count)
    Logger.info("MemoryGuard: Process count: #{process_count}")

    # Log top memory-consuming processes
    log_top_processes(10)
  end

  defp log_top_processes(count) do
    Logger.info("MemoryGuard: === Top #{count} Memory-Consuming Processes ===")

    :erlang.processes()
    |> Enum.map(&get_process_memory/1)
    |> Enum.filter(& &1)
    |> Enum.sort_by(fn {_, mem} -> mem end, :desc)
    |> Enum.take(count)
    |> Enum.each(fn {name, mem} ->
      Logger.info("MemoryGuard:   #{name}: #{div(mem, 1_048_576)}MB")
    end)
  end

  defp get_process_memory(pid) do
    case :erlang.process_info(pid, :memory) do
      {:memory, mem} ->
        name = get_process_name(pid)
        {name, mem}

      _ ->
        nil
    end
  end

  defp get_process_name(pid) do
    case :erlang.process_info(pid, :registered_name) do
      {:registered_name, name} -> inspect(name)
      _ -> inspect(pid)
    end
  end

  defp log_memory_stats(state, current) do
    # Add to history
    entry = Map.put(current, :timestamp, System.system_time(:millisecond))
    # Keep last 100 samples
    new_history = [entry | state.history] |> Enum.take(100)

    %{state | history: new_history}
  end

  # Scheduling

  defp schedule_check do
    interval = Application.get_env(:data_diode, :memory_check_interval, @memory_check_interval)
    Process.send_after(self(), :check_memory, interval)
  end
end
