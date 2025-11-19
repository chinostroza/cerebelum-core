defmodule Cerebelum.Endpoint do
  @moduledoc """
  gRPC endpoint configuration for Cerebelum Core.

  Defines which gRPC services are exposed to external SDK workers.
  """

  use GRPC.Endpoint

  # Register the WorkerService
  intercept GRPC.Server.Interceptors.Logger
  run Cerebelum.Infrastructure.WorkerServiceServer
end
