defmodule DataDiode.DiskCleaner do
  @moduledoc """
  Autonomous disk management with health-based retention policies for harsh environments.

  Features:
  - Smart cleanup based on system health and disk usage
  - Temperature-based retention (keep more data when system is unstable)
  - Log rotation to prevent log files from filling disk
  - Data integrity verification (detect zero-length files)
  - Emergency cleanup when disk is critically full
  - Configurable retention policies
  """
  use GenServer
  require Logger

  alias DataDiode.ConfigHelpers

  # 1 hour
  @interval_ms 3_600_000
  @free_threshold_percent 15
  @free_critical_percent 5

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    schedule_cleanup()
    schedule_log_rotation()
    schedule_integrity_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    path = ConfigHelpers.data_dir()
    free_percent = get_disk_free_percent(path)

    cond do
      # Critical - emergency cleanup
      free_percent < @free_critical_percent ->
        Logger.error("DiskCleaner: CRITICAL disk space (#{free_percent}%). Emergency cleanup...")
        emergency_cleanup(path)

      # Warning - smart cleanup
      free_percent < @free_threshold_percent ->
        Logger.info("DiskCleaner: Low disk space (#{free_percent}%). Starting cleanup...")
        smart_cleanup(path)

      # Normal - periodic check
      true ->
        Logger.debug("DiskCleaner: Disk space OK (#{free_percent}% free)")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:rotate_logs, state) do
    Logger.debug("DiskCleaner: Rotating logs...")
    rotate_logs()
    schedule_log_rotation()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_integrity, state) do
    Logger.debug("DiskCleaner: Checking data integrity...")
    corrupt_count = verify_data_integrity(ConfigHelpers.data_dir())

    if corrupt_count > 0 do
      Logger.warning("DiskCleaner: Found and removed #{corrupt_count} corrupt files")
    end

    schedule_integrity_check()
    {:noreply, state}
  end

  # Scheduling
  defp schedule_cleanup do
    interval = Application.get_env(:data_diode, :disk_cleaner_interval, @interval_ms)
    Process.send_after(self(), :cleanup, interval)
  end

  defp schedule_log_rotation do
    # 24 hours
    interval = Application.get_env(:data_diode, :log_rotation_interval, 86_400_000)
    Process.send_after(self(), :rotate_logs, interval)
  end

  defp schedule_integrity_check do
    # 2 hours
    interval = Application.get_env(:data_diode, :integrity_check_interval, 7_200_000)
    Process.send_after(self(), :check_integrity, interval)
  end

  # Smart cleanup with health-based retention
  defp smart_cleanup(path) do
    health = get_system_health()
    multiplier = get_retention_multiplier(health)
    batch_size = trunc(ConfigHelpers.disk_cleanup_batch_size() * multiplier)

    Logger.info(
      "DiskCleaner: Smart cleanup with retention multiplier #{multiplier} (batch size: #{batch_size})"
    )

    cleanup_disk(path, batch_size)
  end

  defp get_retention_multiplier(health) do
    # Check environmental conditions
    env_status =
      try do
        DataDiode.EnvironmentalMonitor.monitor_all_zones()[:status]
      rescue
        _ -> :unknown
      end

    # Keep MORE data when system is under stress
    cond do
      # Hot or cold - system might be unstable
      env_status == :critical_hot or env_status == :warning_hot -> 2.0
      env_status == :critical_cold or env_status == :warning_cold -> 2.0
      # System unhealthy - preserve for forensics
      health != :healthy -> 2.0
      # Normal conditions
      true -> 1.0
    end
  end

  defp get_system_health do
    # Check if critical processes are alive
    critical = [
      DataDiode.S1.Listener,
      DataDiode.S2.Listener,
      DataDiode.S1.Encapsulator,
      DataDiode.S2.Decapsulator
    ]

    all_alive =
      Enum.all?(critical, fn mod ->
        pid = Process.whereis(mod)
        pid != nil and Process.alive?(pid)
      end)

    if all_alive, do: :healthy, else: :degraded
  end

  # Emergency cleanup (keep only last hour)
  defp emergency_cleanup(path) do
    Logger.error("DiskCleaner: EMERGENCY cleanup - keeping only last hour of data")

    # 1 hour ago
    cutoff = DateTime.utc_now() |> DateTime.add(-3600)

    deleted_count =
      path
      |> Path.join("*.dat")
      |> Path.wildcard()
      |> Enum.count(&delete_if_old?(&1, cutoff))

    Logger.error("DiskCleaner: Emergency cleanup deleted #{deleted_count} files")
    deleted_count
  end

  defp delete_if_old?(file, cutoff) do
    if file_older_than?(file, cutoff) do
      delete_file(file)
    else
      false
    end
  end

  defp file_older_than?(file, cutoff) do
    case File.stat(file) do
      {:ok, %{mtime: mtime}} ->
        mtime_datetime = NaiveDateTime.from_erl!(mtime) |> DateTime.from_naive!("Etc/UTC")
        DateTime.compare(mtime_datetime, cutoff) == :lt

      _ ->
        false
    end
  end

  defp delete_file(file) do
    case File.rm(file) do
      :ok ->
        Logger.warning("DiskCleaner: Emergency delete: #{file}")
        true

      _ ->
        false
    end
  end

  @doc """
  Gets disk free percentage for a path.
  """
  def get_disk_free_percent(path) when is_binary(path) do
    case System.cmd("df", [path]) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.at(1)
        |> String.split()
        |> Enum.find(&String.ends_with?(&1, "%"))
        |> String.trim_trailing("%")
        |> case do
          nil -> 100
          val -> 100 - (Integer.parse(val) |> elem(0))
        end

      _ ->
        100
    end
  end

  @doc """
  Deletes oldest .dat files from the data directory.
  Returns the number of files deleted.
  """
  @spec cleanup_disk(Path.t(), pos_integer()) :: non_neg_integer()
  def cleanup_disk(path, batch_size \\ nil) do
    files_to_delete = batch_size || ConfigHelpers.disk_cleanup_batch_size()

    deleted_count =
      path
      |> Path.join("*.dat")
      |> Path.wildcard()
      |> Enum.sort_by(fn file ->
        case File.stat(file) do
          {:ok, stat} -> stat.mtime
          {:error, _} -> DateTime.from_unix!(0)
        end
      end)
      |> Enum.take(files_to_delete)
      |> Enum.count(fn file ->
        case File.rm(file) do
          :ok ->
            Logger.info("DiskCleaner: Deleted old file: #{file}")
            true

          {:error, reason} ->
            Logger.error("DiskCleaner: Failed to delete #{file}: #{inspect(reason)}")
            false
        end
      end)

    if deleted_count > 0 do
      Logger.info("DiskCleaner: Cleaned up #{deleted_count} old file(s) from #{path}")
    else
      Logger.warning("DiskCleaner: No files found to delete in #{path}")
    end

    deleted_count
  end

  # Log rotation
  defp rotate_logs do
    log_dir = Application.app_dir(:data_diode, "log")

    # Rotate and compress old logs
    case File.ls(log_dir) do
      {:ok, log_files} ->
        log_files
        |> Enum.filter(&(String.ends_with?(&1, ".log") and not String.ends_with?(&1, ".gz")))
        |> Enum.each(fn log_file ->
          full_path = Path.join(log_dir, log_file)
          rotate_log_file(full_path)
        end)

      {:error, _reason} ->
        Logger.debug("DiskCleaner: No log directory to rotate")
    end
  end

  defp rotate_log_file(log_file) do
    # Check if file needs rotation (> 10MB)
    case File.stat(log_file) do
      {:ok, %{size: size}} when size > 10_000_000 ->
        timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[:.]/, "")
        archived_name = "#{log_file}.#{timestamp}"

        # Rename to archived
        File.rename(log_file, archived_name)

        # Compress
        System.cmd("gzip", [archived_name])

        Logger.info("DiskCleaner: Rotated log file: #{log_file}")

      _ok ->
        # File too small, no rotation needed
        :ok
    end
  end

  # Data integrity verification
  @doc """
  Verifies data integrity by checking for zero-length files and other corruption.
  Returns the number of corrupt files removed.
  """
  def verify_data_integrity(path) do
    removed_count =
      path
      |> Path.join("*.dat")
      |> Path.wildcard()
      |> Enum.count(fn file ->
        case File.stat(file) do
          {:ok, %{size: 0}} ->
            Logger.warning("DiskCleaner: Corrupt file (zero length): #{file}")
            File.rm(file)
            true

          {:ok, %{size: size}} when size < 28 ->
            # Minimum valid packet size
            Logger.warning("DiskCleaner: Suspicious file (too small): #{file}")
            File.rm(file)
            true

          {:ok, _stat} ->
            false

          {:error, reason} ->
            Logger.error("DiskCleaner: Cannot stat file #{file}: #{inspect(reason)}")
            false
        end
      end)

    removed_count
  end
end
