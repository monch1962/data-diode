defmodule DataDiode.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = if Mix.target() == :host do
      [
        # Service 1: TCP Listener (S1)
        {
          DataDiode.S1.Listener,
          []
        },
        # Service 2: UDP Listener (S2) - RESTORED
        {
          DataDiode.S2.Listener,
          []
        }
      ]
    else
      # For Nerves, start network and other embedded-related processes
      [
        # Start the VintageNet supervisor
        {VintageNet, []}
      ]
    end

    opts = [strategy: :one_for_one, name: DataDiode.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
