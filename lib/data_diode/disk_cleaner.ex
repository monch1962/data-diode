defmodule DataDiode.DiskCleaner do
  @moduledoc """
  Autonomous background task to ensure disk space remains available in the data directory.
  """
  use GenServer
  require Logger

  @interval_ms 3_600_000 # 1 hour
  @free_threshold_percent 15

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Check disk space
    if get_disk_free_percent("/") < @free_threshold_percent do
      Logger.info("DiskCleaner: Low disk space detected (< #{@free_threshold_percent}%). Starting autonomous cleanup...")
      perform_cleanup()
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @interval_ms)
  end

  defp get_disk_free_percent(path) do
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

  defp perform_cleanup do
    # In a real app, this would delete oldest files in the data directory.
    # For this simulation, we log the intent.
    Logger.warning("DiskCleaner: Simulation - would delete oldest .dat files now.")
  end
end
