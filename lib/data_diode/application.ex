defmodule DataDiode.Application do
  use Application

  @impl true
  def start(_type, _args) do
  # Define the children processes the supervisor must start and monitor.
  children = [

    # 1. Operational Metrics Agent
    %{
      id: DataDiode.Metrics,
      start: {DataDiode.Metrics, :start_link, [[]]},
      type: :worker
    },
    {DataDiode.SystemMonitor, []},
    # 2. Service 1: TCP Listener (S1)
    %{
      id: DataDiode.S1.Listener,
      start: {DataDiode.S1.Listener, :start_link, []},
      type: :worker
    },

    # 3. Service 1: TCP Handler Supervisor (Dynamic)
    %{
      id: DataDiode.S1.HandlerSupervisor,
      start: {DataDiode.S1.HandlerSupervisor, :start_link, []},
      type: :supervisor
    },

    # 4. Service 1: Encapsulator (S1 Worker)
    %{
      id: DataDiode.S1.Encapsulator,
      start: {DataDiode.S1.Encapsulator, :start_link, []},
      type: :worker
    },

    # 4. Service 1: Heartbeat Generator
    {DataDiode.S1.Heartbeat, []},

    # 5. Service 2: Heartbeat Monitor
    {DataDiode.S2.HeartbeatMonitor, []},

    # 6. Autonomous Maintenance
    {DataDiode.DiskCleaner, []},

    # 3. Service 2: UDP Listener (S2) - RESTORED
    %{
      id: DataDiode.S2.Listener,
      start: {DataDiode.S2.Listener, :start_link, []},
      type: :worker
    },
    # 5. Service 2: Async Task Supervisor
    # OT Hardening: Limit concurrent processing tasks
    {Task.Supervisor, name: DataDiode.S2.TaskSupervisor, max_children: 200}
  ]

  # Define the supervision strategy: :one_for_one
  opts = [
    strategy: :one_for_one,
    name: DataDiode.Supervisor,
    max_restarts: 20,
    max_seconds: 5
  ]

  # Start the supervisor with the defined children
  Supervisor.start_link(children, opts)
  end
end
