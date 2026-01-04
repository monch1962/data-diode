defmodule DataDiode.HealthAPI do
  @moduledoc """
  HTTP API for remote health monitoring in inaccessible locations.
  Provides comprehensive status without requiring SSH access.

  Endpoints:
  - GET /api/health - Comprehensive health status
  - GET /api/metrics - Operational metrics
  - GET /api/environment - Environmental sensor readings
  - GET /api/network - Network interface status
  - GET /api/storage - Storage and disk usage
  - POST /api/restart - Trigger graceful restart (requires auth)
  - GET /api/uptime - System uptime information

  Authentication uses X-Auth-Token header with configured token.
  """

  use Plug.Router
  require Logger

  import DataDiode.ConfigHelpers

  @type health_status :: %{
          timestamp: String.t(),
          uptime_seconds: non_neg_integer(),
          system: map(),
          environmental: map(),
          network: map(),
          storage: map(),
          processes: [map()],
          overall_status: atom()
        }

  @type storage_status :: %{
          data_directory: String.t(),
          disk_usage: map(),
          file_count: non_neg_integer(),
          oldest_file_age: integer() | nil,
          newest_file_age: integer() | nil
        }

  @type process_status :: %{
          name: String.t(),
          alive: boolean(),
          pid: String.t() | nil,
          message_queue_len: non_neg_integer() | nil
        }

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  # Health endpoint
  get "/api/health" do
    health = get_comprehensive_health()
    send_json(conn, 200, health)
  end

  # Metrics endpoint
  get "/api/metrics" do
    metrics = get_operational_metrics()
    send_json(conn, 200, metrics)
  end

  # Environmental monitoring endpoint
  get "/api/environment" do
    env = get_environmental_status()
    send_json(conn, 200, env)
  end

  # Network status endpoint
  get "/api/network" do
    network = get_network_status()
    send_json(conn, 200, network)
  end

  # Storage status endpoint
  get "/api/storage" do
    storage = get_storage_status()
    send_json(conn, 200, storage)
  end

  # Uptime endpoint
  get "/api/uptime" do
    uptime = get_uptime_info()
    send_json(conn, 200, uptime)
  end

  # Restart endpoint (requires authentication)
  post "/api/restart" do
    if authenticate_request(conn) do
      trigger_graceful_restart()
      send_json(conn, 200, %{status: "restarting", message: "System will restart in 10 seconds"})
    else
      send_json(conn, 403, %{
        error: "unauthorized",
        message: "Invalid or missing authentication token"
      })
    end
  end

  # Shutdown endpoint (requires authentication)
  post "/api/shutdown" do
    if authenticate_request(conn) do
      trigger_graceful_shutdown()

      send_json(conn, 200, %{
        status: "shutting_down",
        message: "System will shutdown in 10 seconds"
      })
    else
      send_json(conn, 403, %{
        error: "unauthorized",
        message: "Invalid or missing authentication token"
      })
    end
  end

  # Catch-all for 404
  match _ do
    send_json(conn, 404, %{error: "not_found", message: "Endpoint not found"})
  end

  # Health aggregation

  @spec get_comprehensive_health() :: health_status()
  defp get_comprehensive_health do
    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      uptime_seconds: get_uptime_seconds(),
      system: get_system_health(),
      environmental: get_environmental_status(),
      network: get_network_status(),
      storage: get_storage_status(),
      processes: get_critical_processes(),
      overall_status: get_overall_status()
    }
  end

  defp get_system_health do
    memory = DataDiode.MemoryGuard.get_memory_usage()
    vm_memory = DataDiode.MemoryGuard.get_vm_memory()

    {load_output, 0} = System.cmd("uptime", [])
    load_average = parse_uptime_load(load_output)

    %{
      cpu_usage: get_cpu_usage(),
      load_average: load_average,
      memory: %{
        total_mb: div(memory.total, 1_048_576),
        used_mb: div(memory.used, 1_048_576),
        available_mb: div(memory.available, 1_048_576),
        percent: memory.percent
      },
      vm_memory: %{
        total_mb: div(vm_memory[:total], 1_048_576),
        processes_mb: div(vm_memory[:processes], 1_048_576),
        system_mb: div(vm_memory[:system], 1_048_576),
        atom_mb: div(vm_memory[:atom], 1_048_576),
        binary_mb: div(vm_memory[:binary], 1_048_576),
        code_mb: div(vm_memory[:code], 1_048_576),
        ets_mb: div(vm_memory[:ets], 1_048_576)
      },
      process_count: :erlang.system_info(:process_count),
      uptime: get_uptime_string()
    }
  end

  defp get_environmental_status do
    DataDiode.EnvironmentalMonitor.monitor_all_zones()
  end

  defp get_network_status do
    interfaces = DataDiode.NetworkGuard.check_network_interfaces()

    handler_count =
      case Process.whereis(DataDiode.S1.HandlerSupervisor) do
        nil ->
          0

        pid ->
          case DynamicSupervisor.count_children(pid) do
            %{active: count} -> count
            _ -> 0
          end
      end

    %{
      interfaces: interfaces,
      active_connections: handler_count,
      s1_port: s1_port(),
      s2_port: s2_port()
    }
  end

  @spec get_storage_status() :: storage_status()
  defp get_storage_status do
    data_dir = data_dir()
    df_info = get_disk_info(data_dir)
    file_stats = get_file_stats(data_dir)

    %{
      data_directory: data_dir,
      disk_usage: df_info,
      file_count: file_stats.count,
      oldest_file_age:
        if(file_stats.oldest, do: DateTime.diff(DateTime.utc_now(), file_stats.oldest), else: nil),
      newest_file_age:
        if(file_stats.newest, do: DateTime.diff(DateTime.utc_now(), file_stats.newest), else: nil)
    }
  end

  defp get_disk_info(data_dir) do
    {df_output, 0} = System.cmd("df", ["-h", data_dir])
    df_lines = String.split(df_output, "\n")

    case Enum.at(df_lines, 1) do
      nil -> %{error: "Cannot parse df output"}
      line -> parse_df_line(line)
    end
  end

  defp parse_df_line(line) do
    parts = String.split(line) |> Enum.filter(&(&1 != ""))

    case parts do
      [device, size, used, avail, use_pct, mount] ->
        %{
          device: device,
          size: size,
          used: used,
          available: avail,
          use_percent: String.trim_trailing(use_pct, "%"),
          mount_point: mount
        }

      _ ->
        %{error: "Unexpected df format"}
    end
  end

  defp get_file_stats(data_dir) do
    dat_files = Path.wildcard(Path.join(data_dir, "*.dat"))
    file_count = length(dat_files)

    if file_count > 0 do
      {oldest, newest} = get_file_ages(dat_files)
      %{count: file_count, oldest: oldest, newest: newest}
    else
      %{count: 0, oldest: nil, newest: nil}
    end
  end

  defp get_file_ages(dat_files) do
    mtimes =
      Enum.map(dat_files, fn file ->
        case File.stat(file) do
          {:ok, stat} ->
            # Convert mtime to DateTime if it's not already
            case stat.mtime do
              %DateTime{} = dt ->
                dt

              {{_y, _m, _d}, {_h, _min, _s}} = erl_time ->
                # Convert Erlang-style tuple to DateTime
                erl_time
                |> NaiveDateTime.from_erl!()
                |> DateTime.from_naive!("Etc/UTC")

              _ ->
                DateTime.from_unix!(0)
            end

          _ ->
            DateTime.from_unix!(0)
        end
      end)

    {Enum.min(mtimes), Enum.max(mtimes)}
  end

  defp get_critical_processes do
    list_critical_processes()
    |> Enum.map(&get_process_status/1)
  end

  defp list_critical_processes do
    [
      {DataDiode.S1.Listener, "S1.Listener"},
      {DataDiode.S2.Listener, "S2.Listener"},
      {DataDiode.S1.Encapsulator, "S1.Encapsulator"},
      {DataDiode.S2.Decapsulator, "S2.Decapsulator"},
      {DataDiode.Metrics, "Metrics"},
      {DataDiode.Watchdog, "Watchdog"},
      {DataDiode.SystemMonitor, "SystemMonitor"},
      {DataDiode.DiskCleaner, "DiskCleaner"},
      {DataDiode.EnvironmentalMonitor, "EnvironmentalMonitor"},
      {DataDiode.NetworkGuard, "NetworkGuard"},
      {DataDiode.PowerMonitor, "PowerMonitor"},
      {DataDiode.MemoryGuard, "MemoryGuard"}
    ]
  end

  @spec get_process_status({atom(), String.t()}) :: process_status()
  defp get_process_status({module, name}) do
    pid = Process.whereis(module)
    alive = pid != nil and Process.alive?(pid)

    info = collect_process_info(pid, alive)

    Map.put(info, :name, name)
    |> Map.put(:alive, alive)
    |> Map.put(:pid, if(alive, do: inspect(pid), else: nil))
  end

  defp collect_process_info(pid, true) do
    case :erlang.process_info(pid, :message_queue_len) do
      {:message_queue_len, len} -> %{message_queue_len: len}
      _ -> %{}
    end
  end

  defp collect_process_info(_pid, _alive), do: %{}

  defp get_operational_metrics do
    DataDiode.Metrics.get_stats()
  end

  defp get_uptime_info do
    uptime_seconds = get_uptime_seconds()
    days = div(uptime_seconds, 86_400)
    hours = div(rem(uptime_seconds, 86_400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)

    %{
      uptime_seconds: uptime_seconds,
      uptime_string: "#{days}d #{hours}h #{minutes}m",
      start_time: get_start_time()
    }
  end

  defp get_overall_status do
    env = get_environmental_status()
    memory = DataDiode.MemoryGuard.get_memory_usage()
    storage = get_storage_status()
    processes = get_critical_processes()

    cond do
      critical_environment?(env) -> :critical
      warning_environment?(env) -> :warning
      critical_memory?(memory) -> :critical
      warning_memory?(memory) -> :warning
      critical_storage?(storage) -> :critical
      warning_storage?(storage) -> :warning
      all_processes_alive?(processes) -> :healthy
      true -> :degraded
    end
  end

  defp critical_environment?(env) do
    env[:status] == :critical_hot or env[:status] == :critical_cold
  end

  defp warning_environment?(env) do
    env[:status] == :warning_hot or env[:status] == :warning_cold
  end

  defp critical_memory?(memory) do
    memory.percent >= 90
  end

  defp warning_memory?(memory) do
    memory.percent >= 80
  end

  defp critical_storage?(storage) do
    storage.disk_usage != %{} and
      not Map.has_key?(storage.disk_usage, :error) and
      String.to_integer(
        storage.disk_usage[:use_percent] || storage.disk_usage["use_percent"] || "0"
      ) >= 95
  end

  defp warning_storage?(storage) do
    storage.disk_usage != %{} and
      not Map.has_key?(storage.disk_usage, :error) and
      String.to_integer(
        storage.disk_usage[:use_percent] || storage.disk_usage["use_percent"] || "0"
      ) >= 90
  end

  defp all_processes_alive?(processes) do
    Enum.all?(processes, & &1[:alive])
  end

  # Utility functions

  defp get_uptime_seconds do
    # Read system uptime from /proc/uptime
    case File.read("/proc/uptime") do
      {:ok, contents} ->
        [uptime_s, _idle_s] = String.split(contents) |> Enum.take(2)
        elem(Float.parse(uptime_s), 0) |> trunc()

      {:error, _} ->
        # Fallback to BEAM uptime
        :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
    end
  end

  defp get_uptime_string do
    uptime_s = get_uptime_seconds()
    days = div(uptime_s, 86_400)
    hours = div(rem(uptime_s, 86_400), 3600)
    minutes = div(rem(uptime_s, 3600), 60)

    "#{days}d #{hours}h #{minutes}m"
  end

  defp get_start_time do
    uptime_s = get_uptime_seconds()

    DateTime.utc_now()
    |> DateTime.add(-uptime_s)
    |> DateTime.to_iso8601()
  end

  defp get_cpu_usage do
    # Parse from /proc/stat or use top
    try do
      case System.cmd("sh", ["-c", "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'"]) do
        {output, 0} ->
          String.trim(output)

        _ ->
          "unknown"
      end
    rescue
      _ ->
        # Command not available on this platform (e.g., macOS)
        "unknown"
    end
  end

  defp parse_uptime_load(output) do
    # Parse load average from uptime output:
    # "load average: 0.05, 0.02, 0.00"
    case Regex.run(~r/load average: ([\d.]+), ([\d.]+), ([\d.]+)/, output) do
      [_, m1, m5, m15] ->
        %{one_minute: m1, five_minute: m5, fifteen_minute: m15}

      _ ->
        %{one_minute: "unknown", five_minute: "unknown", fifteen_minute: "unknown"}
    end
  end

  # Authentication

  @spec authenticate_request(Plug.Conn.t()) :: boolean()
  defp authenticate_request(conn) do
    token = get_req_header(conn, "x-auth-token")
    expected_token = Application.get_env(:data_diode, :health_api_auth_token)

    # If no token is configured, allow all requests
    if expected_token == nil do
      true
    else
      case token do
        [^expected_token] -> true
        _ -> false
      end
    end
  end

  # Control actions

  defp trigger_graceful_restart do
    spawn(fn ->
      Logger.warning("HealthAPI: Graceful restart requested via API")
      # Give time for response
      Process.sleep(10_000)
      System.cmd("shutdown", ["-r", "+1"])
    end)
  end

  defp trigger_graceful_shutdown do
    spawn(fn ->
      Logger.warning("HealthAPI: Graceful shutdown requested via API")
      # Give time for response
      Process.sleep(10_000)
      System.cmd("shutdown", ["-h", "+1"])
    end)
  end

  # Response helpers

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
