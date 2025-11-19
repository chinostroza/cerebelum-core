defmodule Cerebelum.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Base children that always start
    base_children = [
      # Database repo
      Cerebelum.Repo,

      # Event store for event sourcing
      Cerebelum.EventStore,

      # Execution supervisor for managing workflow executions
      Cerebelum.Execution.Supervisor,

      # Worker registry for SDK worker pool management
      Cerebelum.Infrastructure.WorkerRegistry,

      # Task router for distributing work to SDK workers
      Cerebelum.Infrastructure.TaskRouter,

      # Blueprint registry for storing workflow definitions
      Cerebelum.Infrastructure.BlueprintRegistry,

      # Execution state manager for tracking workflow execution state
      Cerebelum.Infrastructure.ExecutionStateManager,

      # Dead Letter Queue for managing failed tasks
      Cerebelum.Infrastructure.DLQ
    ]

    # Conditionally add gRPC server if enabled
    children = if grpc_enabled?() do
      IO.puts("🔧 Starting gRPC server on port #{grpc_port()}...")
      base_children ++ [
        # gRPC server for multi-language SDK support
        # Register servers directly instead of using Endpoint
        {GRPC.Server.Supervisor,
         servers: [Cerebelum.Infrastructure.WorkerServiceServer],
         port: grpc_port(),
         start_server: true}
      ]
    else
      IO.puts("⚠️  gRPC server disabled")
      base_children
    end

    opts = [strategy: :one_for_one, name: Cerebelum.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp grpc_enabled? do
    Application.get_env(:cerebelum_core, :enable_grpc_server, false)
  end

  defp grpc_port do
    Application.get_env(:cerebelum_core, :grpc_port, 50051)
  end
end
