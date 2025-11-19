defmodule Cerebelum.Infrastructure.WorkerServiceServerTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Infrastructure.WorkerServiceServer
  alias Cerebelum.Worker.{
    RegisterRequest,
    RegisterResponse,
    HeartbeatRequest,
    HeartbeatResponse
  }

  describe "register/2" do
    test "successfully registers a worker" do
      request = %RegisterRequest{
        worker_id: "worker-1",
        language: "kotlin",
        capabilities: ["TestWorkflow"],
        metadata: %{},
        version: "1.0.0"
      }

      response = WorkerServiceServer.register(request, nil)

      assert %RegisterResponse{} = response
      assert response.success == true
      assert response.message == "Worker registered successfully"
      assert response.heartbeat_interval_ms == 10_000
    end
  end

  describe "heartbeat/2" do
    test "acknowledges heartbeat from worker" do
      request = %HeartbeatRequest{
        worker_id: "worker-1",
        status: :IDLE
      }

      response = WorkerServiceServer.heartbeat(request, nil)

      assert %HeartbeatResponse{} = response
      assert response.acknowledged == true
      assert response.commands == []
    end
  end
end
