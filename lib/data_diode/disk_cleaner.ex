defmodule DataDiode.DiskCleaner do
  @moduledoc """
  Autonomous background task to ensure disk space remains available in the data directory.
  """
  use GenServer
  require Logger

  alias DataDiode.ConfigHelpers

  @interval_ms 3_600_000 # 1 hour
  @free_threshold_percent 15

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Check disk space on data directory
    path = ConfigHelpers.data_dir()
    if get_disk_free_percent(path) < @free_threshold_percent do
      Logger.info("DiskCleaner: Low disk space detected on #{path} (< #{@free_threshold_percent}%). Starting autonomous cleanup...")
      cleanup_disk(path)
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    interval = Application.get_env(:data_diode, :disk_cleaner_interval, @interval_ms)
    Process.send_after(self(), :cleanup, interval)
  end

  def get_disk_free_percent(path) when is_binary(path) do
    case System.cmd("df", [path]) do
      {output, 0} ->
        # Parse the 'Capacity' column
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
      _ -> 100
    end
  end

  @doc """
  Deletes oldest .dat files from the data directory to free up disk space.
  Returns the number of files deleted.
  """
  @spec cleanup_disk(Path.t()) :: non_neg_integer()
  def cleanup_disk(path) do
    files_to_delete = ConfigHelpers.disk_cleanup_batch_size()

    deleted_count =
      path
      |> Path.join("*.dat")
      |> Path.wildcard()
      # Sort by modification time (oldest first)
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
end
