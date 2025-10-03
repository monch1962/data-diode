defmodule DataDiode.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Define the children processes the supervisor must start and monitor.
    children = [
      # 🚨 FINAL FIX: Use the full map-style child specification.
      # This explicitly tells the supervisor to call DataDiode.S1.Listener.start_link() (zero args).
      %{
        id: DataDiode.S1.Listener,
        start: {DataDiode.S1.Listener, :start_link, []},
        # GenServer should be listed as a worker
        type: :worker
      }
    ]

    # Define the supervision strategy: :one_for_one
    opts = [strategy: :one_for_one, name: DataDiode.Supervisor]

    # Start the supervisor with the defined children
    Supervisor.start_link(children, opts)
  end
end
