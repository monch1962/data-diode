defmodule DataDiode.Application do
  @moduledoc """
  Main application module for the Data Diode.
  Initializes and supervises all child processes.

  Harsh environment configuration:
  - Increased max_restarts (50 instead of 20) for unstable conditions
  - Extended max_seconds window (10 instead of 5)
  - All critical processes monitored by supervisor
  - Environmental monitoring and health checking
  - Power management for UPS integration
  """
  use Application

  @impl true
  def start(_type, _args) do
    # Setup log rotation before starting logger
    setup_log_rotation()

    # Validate configuration before starting any processes
    DataDiode.ConfigValidator.validate!()

    # Define the children processes the supervisor must start and monitor.
    children = [
      # 1. Operational Metrics Agent
      %{
        id: DataDiode.Metrics,
        start: {DataDiode.Metrics, :start_link, [[]]},
        type: :worker
      },

      # 2. Environmental Monitoring (NEW for harsh environments)
      {DataDiode.EnvironmentalMonitor, []},

      # 3. Power Monitoring (NEW for harsh environments)
      {DataDiode.PowerMonitor, []},

      # 4. Memory Guard (NEW for harsh environments)
      {DataDiode.MemoryGuard, []},

      # 5. System Monitoring
      {DataDiode.SystemMonitor, []},

      # 6. Service 1: TCP Listener (S1)
      %{
        id: DataDiode.S1.Listener,
        start: {DataDiode.S1.Listener, :start_link, []},
        type: :worker
      },

      # 7. Service 1: UDP Listener (S1)
      {DataDiode.S1.UDPListener, []},

      # 8. Service 1: TCP Handler Supervisor (Dynamic)
      %{
        id: DataDiode.S1.HandlerSupervisor,
        start: {DataDiode.S1.HandlerSupervisor, :start_link, []},
        type: :supervisor
      },

      # 9. Service 1: Encapsulator (S1 Worker)
      %{
        id: DataDiode.S1.Encapsulator,
        start: {DataDiode.S1.Encapsulator, :start_link, []},
        type: :worker
      },

      # 10. Service 1: Heartbeat Generator
      {DataDiode.S1.Heartbeat, []},

      # 11. Service 2: Heartbeat Monitor
      {DataDiode.S2.HeartbeatMonitor, []},

      # 12. Service 2: UDP Listener (S2)
      %{
        id: DataDiode.S2.Listener,
        start: {DataDiode.S2.Listener, :start_link, []},
        type: :worker
      },

      # 13. Service 2: Async Task Supervisor
      # OT Hardening: Limit concurrent processing tasks
      {Task.Supervisor, name: DataDiode.S2.TaskSupervisor, max_children: 200},

      # 14. Network Interface Monitoring (NEW for harsh environments)
      {DataDiode.NetworkGuard, []},

      # 15. Autonomous Maintenance (Enhanced for harsh environments)
      {DataDiode.DiskCleaner, []},

      # 16. Hardware Watchdog Monitoring
      {DataDiode.Watchdog, []}
    ]

    # Add Health API only in production to avoid port conflicts during tests
    children =
      if Mix.env() == :prod do
        children ++
          [{Plug.Cowboy, scheme: :http, plug: DataDiode.HealthAPI, options: [port: 4000]}]
      else
        children
      end

    # Define the supervision strategy: :one_for_one
    # Harsh environment: Increased restart tolerance
    opts = [
      strategy: :one_for_one,
      name: DataDiode.Supervisor,
      # Increased from 20 for harsh environments
      max_restarts: 50,
      # Extended window from 5 seconds
      max_seconds: 10
    ]

    # Start the supervisor with the defined children
    Supervisor.start_link(children, opts)
  end

  # Setup log rotation for harsh environments
  defp setup_log_rotation do
    log_dir = Path.join([Application.app_dir(:data_diode), "log"])
    File.mkdir_p!(log_dir)

    # Configure logger to use file with rotation
    config = [
      path: Path.join(log_dir, "data_diode.log"),
      level: :info,
      rotate: :daily,
      # Keep 90 days of logs for harsh environments
      keep: 90
    ]

    Application.put_env(:logger, :backends, [:console, {LoggerFileBackend, :error_log}])
    Application.put_env(:logger, :error_log, config)
  end
end
