defmodule DataDiode.Application do
  use Application

  @impl true
  def start(_type, _args) do
  # Define the children processes the supervisor must start and monitor.
  children = [

    # 2. Service 1: TCP Listener (S1)
    %{
      id: DataDiode.S1.Listener,
      start: {DataDiode.S1.Listener, :start_link, []},
      type: :worker
    },

    # 3. Service 2: UDP Listener (S2) - RESTORED
    %{
      id: DataDiode.S2.Listener,
      start: {DataDiode.S2.Listener, :start_link, []},
      type: :worker
    }
  ]

  # Define the supervision strategy: :one_for_one
  opts = [strategy: :one_for_one, name: DataDiode.Supervisor]

  # Start the supervisor with the defined children
  Supervisor.start_link(children, opts)
end
end
