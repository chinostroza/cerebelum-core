defmodule Cerebelum.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Execution supervisor for managing workflow executions
      Cerebelum.Execution.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Cerebelum.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
