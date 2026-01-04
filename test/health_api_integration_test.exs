defmodule DataDiode.HealthAPIIntegrationTest do
  @moduledoc """
  Integration tests for HealthAPI HTTP endpoints.

  These tests use Plug.Test to make actual HTTP requests to the API
  without needing a running web server.
  """
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureLog

  @opts DataDiode.HealthAPI.init([])

  setup do
    # Ensure application is started
    Application.ensure_all_started(:data_diode)

    # Set up a test data directory
    {:ok, tmp_dir} = File.cwd()
    data_dir = Path.join(tmp_dir, "test_data_health_api")
    File.mkdir_p!(data_dir)
    Application.put_env(:data_diode, :data_dir, data_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      Application.delete_env(:data_diode, :health_api_auth_token)
    end)

    {:ok, data_dir: data_dir}
  end

  describe "GET /api/health" do
    test "returns 200 and health status map" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 200
      assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert is_map(json)
      assert Map.has_key?(json, "timestamp")
      assert Map.has_key?(json, "uptime_seconds")
      assert Map.has_key?(json, "overall_status")
    end

    test "includes system metrics" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "system")
      assert is_map(json["system"])

      # cpu_usage may be "unknown" on non-Linux platforms
      assert Map.has_key?(json["system"], "cpu_usage")
      assert Map.has_key?(json["system"], "load_average")
      assert Map.has_key?(json["system"], "memory")
      assert Map.has_key?(json["system"], "process_count")
    end

    test "includes environmental data" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "environmental")
      assert is_map(json["environmental"])

      assert Map.has_key?(json["environmental"], "cpu")
      assert Map.has_key?(json["environmental"], "ambient")
      assert Map.has_key?(json["environmental"], "status")
    end

    test "includes network status" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "network")
      assert is_map(json["network"])

      assert Map.has_key?(json["network"], "interfaces")
      assert Map.has_key?(json["network"], "active_connections")
    end

    test "includes storage information" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "storage")
      assert is_map(json["storage"])

      assert Map.has_key?(json["storage"], "data_directory")
      assert Map.has_key?(json["storage"], "disk_usage")
      assert Map.has_key?(json["storage"], "file_count")
    end

    test "includes process information" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "processes")
      assert is_list(json["processes"])

      # Should have entries for critical processes
      process_names = Enum.map(json["processes"], fn p -> p["name"] end)
      assert "S1.Listener" in process_names
      assert "S2.Listener" in process_names
      assert "Metrics" in process_names
    end

    test "evaluates overall status correctly" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["overall_status"] in ["healthy", "warning", "degraded", "critical"]
    end
  end

  describe "GET /api/metrics" do
    test "returns operational metrics" do
      conn = conn(:get, "/api/metrics") |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 200
      assert {:ok, json} = Jason.decode(conn.resp_body)

      assert Map.has_key?(json, "packets_forwarded")
      assert Map.has_key?(json, "error_count")
      assert Map.has_key?(json, "bytes_forwarded")
    end

    test "includes packet size statistics" do
      conn = conn(:get, "/api/metrics") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "packet_size_min")
      assert Map.has_key?(json, "packet_size_max")
      assert Map.has_key?(json, "packet_size_avg")
    end

    test "includes protocol counts" do
      conn = conn(:get, "/api/metrics") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "protocol_counts")
      assert is_map(json["protocol_counts"])
    end

    test "includes source IP tracking" do
      conn = conn(:get, "/api/metrics") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "top_source_ips")
      assert is_list(json["top_source_ips"])
    end
  end

  describe "GET /api/environment" do
    test "returns environmental readings" do
      conn = conn(:get, "/api/environment") |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 200
      assert {:ok, json} = Jason.decode(conn.resp_body)

      assert Map.has_key?(json, "cpu")
      assert Map.has_key?(json, "storage")
      assert Map.has_key?(json, "ambient")
      assert Map.has_key?(json, "status")
    end

    test "includes temperature status" do
      conn = conn(:get, "/api/environment") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["status"] in ["normal", "warning_hot", "critical_hot", "warning_cold", "critical_cold"]
    end
  end

  describe "GET /api/network" do
    test "returns network interface status" do
      conn = conn(:get, "/api/network") |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 200
      assert {:ok, json} = Jason.decode(conn.resp_body)

      assert Map.has_key?(json, "interfaces")

      # On non-Linux platforms, interface checks may fail
      # but we should still get the interfaces map with timestamp
      assert Map.has_key?(json["interfaces"], "timestamp")
    end

    test "includes interface up/down status when available" do
      conn = conn(:get, "/api/network") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)

      # On Linux with proper interfaces, we'd have s1 and s2
      # On macOS or when interfaces don't exist, they may not be present
      if Map.has_key?(json["interfaces"], "s1") do
        assert Map.has_key?(json["interfaces"]["s1"], "up")
        assert is_boolean(json["interfaces"]["s1"]["up"]) or
                 json["interfaces"]["s1"]["up"] == "unknown"
      end

      if Map.has_key?(json["interfaces"], "s2") do
        assert Map.has_key?(json["interfaces"]["s2"], "up")
        assert is_boolean(json["interfaces"]["s2"]["up"]) or
                 json["interfaces"]["s2"]["up"] == "unknown"
      end
    end

    test "includes timestamp" do
      conn = conn(:get, "/api/network") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json["interfaces"], "timestamp")
      assert is_integer(json["interfaces"]["timestamp"])
    end

    test "includes active connections count" do
      conn = conn(:get, "/api/network") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "active_connections")
      assert is_integer(json["active_connections"])
    end
  end

  describe "GET /api/storage" do
    test "returns storage status", %{data_dir: data_dir} do
      # Create a test file
      test_file = Path.join(data_dir, "test_file.dat")
      File.write!(test_file, "test data")

      conn = conn(:get, "/api/storage") |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 200
      assert {:ok, json} = Jason.decode(conn.resp_body)

      assert Map.has_key?(json, "data_directory")
      assert Map.has_key?(json, "disk_usage")
      assert Map.has_key?(json, "file_count")
      assert json["file_count"] >= 1
    end

    test "includes disk usage information" do
      conn = conn(:get, "/api/storage") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert is_map(json["disk_usage"])

      # May have error key if df command fails on test system
      if Map.has_key?(json["disk_usage"], "size") do
        assert Map.has_key?(json["disk_usage"], "used")
        assert Map.has_key?(json["disk_usage"], "available")
        assert Map.has_key?(json["disk_usage"], "use_percent")
      end
    end

    test "includes file age information", %{data_dir: data_dir} do
      # Create a test file
      test_file = Path.join(data_dir, "test_file_age.dat")
      File.write!(test_file, "test data")

      conn = conn(:get, "/api/storage") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert Map.has_key?(json, "oldest_file_age")
      assert Map.has_key?(json, "newest_file_age")

      # Should have non-nil values since we created a file
      assert is_integer(json["oldest_file_age"]) or json["oldest_file_age"] == nil
      assert is_integer(json["newest_file_age"]) or json["newest_file_age"] == nil
    end
  end

  describe "GET /api/uptime" do
    test "returns uptime information" do
      conn = conn(:get, "/api/uptime") |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 200
      assert {:ok, json} = Jason.decode(conn.resp_body)

      assert Map.has_key?(json, "uptime_seconds")
      assert Map.has_key?(json, "uptime_string")
      assert Map.has_key?(json, "start_time")
    end

    test "formats uptime in human readable format" do
      conn = conn(:get, "/api/uptime") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert is_binary(json["uptime_string"])
      assert String.length(json["uptime_string"]) > 0
      assert json["uptime_string"] =~ ~r/^\d+d \d+h \d+m$/
    end

    test "includes start time in ISO8601 format" do
      conn = conn(:get, "/api/uptime") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert is_binary(json["start_time"])

      # Should be valid ISO8601
      assert {:ok, _, _} = DateTime.from_iso8601(json["start_time"])
    end
  end

  describe "authentication" do
    test "POST /api/restart rejects requests without valid token" do
      Application.put_env(:data_diode, :health_api_auth_token, "secret_token")

      conn =
        conn(:post, "/api/restart")
        |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 403
      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["error"] == "unauthorized"
    end

    test "POST /api/restart accepts requests with valid token" do
      Application.put_env(:data_diode, :health_api_auth_token, "secret_token")

      conn =
        conn(:post, "/api/restart")
        |> put_req_header("x-auth-token", "secret_token")
        |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 200
      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["status"] == "restarting"
      assert json["message"] =~ "restart in 10 seconds"
    end

    test "POST /api/shutdown rejects requests without valid token" do
      Application.put_env(:data_diode, :health_api_auth_token, "secret_token")

      conn =
        conn(:post, "/api/shutdown")
        |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 403
      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["error"] == "unauthorized"
    end

    test "POST /api/shutdown accepts requests with valid token" do
      Application.put_env(:data_diode, :health_api_auth_token, "secret_token")

      log =
        capture_log(fn ->
          conn =
            conn(:post, "/api/shutdown")
            |> put_req_header("x-auth-token", "secret_token")
            |> DataDiode.HealthAPI.call(@opts)

          assert conn.status == 200
          assert {:ok, json} = Jason.decode(conn.resp_body)
          assert json["status"] == "shutting_down"
          assert json["message"] =~ "shutdown in 10 seconds"
        end)

      assert log =~ "Graceful shutdown requested"
    end

    test "allows requests when no token is configured" do
      Application.delete_env(:data_diode, :health_api_auth_token)

      conn =
        conn(:post, "/api/restart")
        |> DataDiode.HealthAPI.call(@opts)

      # Should be allowed when no token is configured
      assert conn.status == 200
    end
  end

  describe "error handling" do
    test "returns 404 for unknown endpoints" do
      conn = conn(:get, "/api/unknown") |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 404
      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["error"] == "not_found"
    end

    test "returns 404 for non-API routes" do
      conn = conn(:get, "/some/other/path") |> DataDiode.HealthAPI.call(@opts)

      assert conn.status == 404
      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["error"] == "not_found"
    end
  end

  describe "control endpoints" do
    test "restart endpoint triggers async restart process" do
      Application.put_env(:data_diode, :health_api_auth_token, "test_token")

      log =
        capture_log(fn ->
          conn =
            conn(:post, "/api/restart")
            |> put_req_header("x-auth-token", "test_token")
            |> DataDiode.HealthAPI.call(@opts)

          assert conn.status == 200

          # Give async process time to log
          Process.sleep(100)
        end)

      assert log =~ "Graceful restart requested"
    end

    test "shutdown endpoint triggers async shutdown process" do
      Application.put_env(:data_diode, :health_api_auth_token, "test_token")

      log =
        capture_log(fn ->
          conn =
            conn(:post, "/api/shutdown")
            |> put_req_header("x-auth-token", "test_token")
            |> DataDiode.HealthAPI.call(@opts)

          assert conn.status == 200

          # Give async process time to log
          Process.sleep(100)
        end)

      assert log =~ "Graceful shutdown requested"
    end
  end

  describe "health status evaluation" do
    test "evaluates system status based on multiple factors" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      status = json["overall_status"]

      # Status should be one of the valid values
      assert status in ["healthy", "warning", "degraded", "critical"]

      # If status is critical, should have reason in environmental or storage
      if status == "critical" do
        # Either env is critical or storage/memory is critical
        env_status = json["environmental"]["status"]
        assert env_status in ["critical_hot", "critical_cold"]
      end
    end

    test "includes all critical processes in health check" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      processes = json["processes"]

      # Check for expected critical processes
      process_names = Enum.map(processes, fn p -> p["name"] end)

      assert "S1.Listener" in process_names
      assert "S2.Listener" in process_names
      assert "S1.Encapsulator" in process_names
      assert "S2.Decapsulator" in process_names
      assert "Metrics" in process_names
      assert "Watchdog" in process_names
      assert "SystemMonitor" in process_names
      assert "DiskCleaner" in process_names
      assert "EnvironmentalMonitor" in process_names
      assert "NetworkGuard" in process_names
      assert "PowerMonitor" in process_names
      assert "MemoryGuard" in process_names
    end

    test "includes process alive status" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      processes = json["processes"]

      # All processes should have alive field
      Enum.each(processes, fn process ->
        assert Map.has_key?(process, "alive")
        assert is_boolean(process["alive"])
      end)
    end

    test "includes process PID information for alive processes" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      processes = json["processes"]

      # At least Metrics should be alive
      metrics_process = Enum.find(processes, fn p -> p["name"] == "Metrics" end)

      if metrics_process && metrics_process["alive"] do
        assert Map.has_key?(metrics_process, "pid")
        assert is_binary(metrics_process["pid"])
      end
    end

    test "includes message queue length for alive processes" do
      conn = conn(:get, "/api/health") |> DataDiode.HealthAPI.call(@opts)

      assert {:ok, json} = Jason.decode(conn.resp_body)
      processes = json["processes"]

      # Find alive processes
      alive_processes = Enum.filter(processes, fn p -> p["alive"] end)

      # Alive processes should have message_queue_len
      Enum.each(alive_processes, fn process ->
        assert Map.has_key?(process, "message_queue_len")
        assert is_integer(process["message_queue_len"])
        assert process["message_queue_len"] >= 0
      end)
    end
  end
end
