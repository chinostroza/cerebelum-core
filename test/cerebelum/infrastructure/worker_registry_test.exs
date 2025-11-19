defmodule Cerebelum.Infrastructure.WorkerRegistryTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Infrastructure.WorkerRegistry

  setup do
    # Registry is started by Application, so we just need to clean it up
    # Get all workers and unregister them
    workers = WorkerRegistry.get_workers(:all)
    Enum.each(workers, fn worker ->
      WorkerRegistry.unregister_worker(worker.worker_id)
    end)

    :ok
  end

  describe "register_worker/2" do
    test "successfully registers a new worker" do
      metadata = %{
        language: "kotlin",
        capabilities: ["TestWorkflow", "PaymentWorkflow"],
        version: "1.0.0",
        metadata: %{"region" => "us-east-1"}
      }

      assert {:ok, worker} = WorkerRegistry.register_worker("worker-1", metadata)

      assert worker.worker_id == "worker-1"
      assert worker.language == "kotlin"
      assert worker.capabilities == ["TestWorkflow", "PaymentWorkflow"]
      assert worker.version == "1.0.0"
      assert worker.status == :idle
      assert worker.registered_at > 0
      assert worker.last_heartbeat > 0
    end

    test "returns error when registering duplicate worker" do
      metadata = %{language: "typescript", capabilities: [], version: "1.0.0"}

      assert {:ok, _} = WorkerRegistry.register_worker("worker-1", metadata)
      assert {:error, :already_registered} = WorkerRegistry.register_worker("worker-1", metadata)
    end

    test "registers multiple workers with different IDs" do
      assert {:ok, _} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})
      assert {:ok, _} = WorkerRegistry.register_worker("worker-2", %{language: "typescript"})
      assert {:ok, _} = WorkerRegistry.register_worker("worker-3", %{language: "python"})

      workers = WorkerRegistry.get_workers(:all)
      assert length(workers) == 3
    end
  end

  describe "heartbeat/2" do
    test "updates last_heartbeat timestamp" do
      {:ok, worker1} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})
      initial_heartbeat = worker1.last_heartbeat

      # Wait a bit and send heartbeat
      :timer.sleep(1100)  # Wait > 1 second for timestamp to change
      WorkerRegistry.heartbeat("worker-1", :idle)

      # Heartbeat is async (cast), so wait for it to process
      :timer.sleep(50)

      # Get updated worker
      {:ok, worker2} = WorkerRegistry.get_worker("worker-1")
      assert worker2.last_heartbeat > initial_heartbeat
    end

    test "updates worker status" do
      {:ok, _} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})

      WorkerRegistry.heartbeat("worker-1", :busy)
      :timer.sleep(50)  # Wait for async cast
      {:ok, worker} = WorkerRegistry.get_worker("worker-1")
      assert worker.status == :busy

      WorkerRegistry.heartbeat("worker-1", :draining)
      :timer.sleep(50)  # Wait for async cast
      {:ok, worker} = WorkerRegistry.get_worker("worker-1")
      assert worker.status == :draining
    end

    test "handles heartbeat from unregistered worker gracefully" do
      # Should not crash
      WorkerRegistry.heartbeat("nonexistent-worker", :idle)
    end
  end

  describe "unregister_worker/2" do
    test "successfully unregisters a worker" do
      {:ok, _} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})

      assert :ok = WorkerRegistry.unregister_worker("worker-1", "shutdown")
      assert {:error, :not_found} = WorkerRegistry.get_worker("worker-1")
    end

    test "returns error when unregistering non-existent worker" do
      assert {:error, :not_found} = WorkerRegistry.unregister_worker("nonexistent", "test")
    end
  end

  describe "get_worker/1" do
    test "retrieves worker by ID" do
      {:ok, _} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})

      assert {:ok, worker} = WorkerRegistry.get_worker("worker-1")
      assert worker.worker_id == "worker-1"
    end

    test "returns error for non-existent worker" do
      assert {:error, :not_found} = WorkerRegistry.get_worker("nonexistent")
    end
  end

  describe "get_workers/1" do
    setup do
      {:ok, _} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})
      {:ok, _} = WorkerRegistry.register_worker("worker-2", %{language: "typescript"})
      {:ok, _} = WorkerRegistry.register_worker("worker-3", %{language: "python"})

      # Set different statuses
      WorkerRegistry.heartbeat("worker-1", :idle)
      WorkerRegistry.heartbeat("worker-2", :busy)
      WorkerRegistry.heartbeat("worker-3", :draining)

      :ok
    end

    test "returns all workers" do
      workers = WorkerRegistry.get_workers(:all)
      assert length(workers) == 3
    end

    test "returns only idle workers" do
      workers = WorkerRegistry.get_workers(:idle)
      assert length(workers) == 1
      assert hd(workers).worker_id == "worker-1"
    end

    test "returns only busy workers" do
      workers = WorkerRegistry.get_workers(:busy)
      assert length(workers) == 1
      assert hd(workers).worker_id == "worker-2"
    end

    test "returns only draining workers" do
      workers = WorkerRegistry.get_workers(:draining)
      assert length(workers) == 1
      assert hd(workers).worker_id == "worker-3"
    end
  end

  describe "get_idle_workers/0" do
    test "returns only idle workers" do
      {:ok, _} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})
      {:ok, _} = WorkerRegistry.register_worker("worker-2", %{language: "typescript"})
      
      WorkerRegistry.heartbeat("worker-1", :idle)
      WorkerRegistry.heartbeat("worker-2", :busy)

      idle_workers = WorkerRegistry.get_idle_workers()
      assert length(idle_workers) == 1
      assert hd(idle_workers).worker_id == "worker-1"
    end
  end

  describe "get_stats/0" do
    test "returns correct pool statistics" do
      {:ok, _} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})
      {:ok, _} = WorkerRegistry.register_worker("worker-2", %{language: "typescript"})
      {:ok, _} = WorkerRegistry.register_worker("worker-3", %{language: "python"})

      WorkerRegistry.heartbeat("worker-1", :idle)
      WorkerRegistry.heartbeat("worker-2", :busy)
      WorkerRegistry.heartbeat("worker-3", :draining)

      stats = WorkerRegistry.get_stats()

      assert stats.total == 3
      assert stats.idle == 1
      assert stats.busy == 1
      assert stats.draining == 1
    end

    test "returns zeros when no workers registered" do
      stats = WorkerRegistry.get_stats()

      assert stats.total == 0
      assert stats.idle == 0
      assert stats.busy == 0
      assert stats.draining == 0
    end
  end

  describe "dead worker detection" do
    @tag :capture_log
    test "automatically deregisters workers after timeout" do
      # Register a worker
      {:ok, worker} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})
      
      # Manually set last_heartbeat to be old (simulate dead worker)
      # We need to access the ETS table directly for this test
      old_time = worker.last_heartbeat - 31  # 31 seconds ago (> 30s threshold)
      dead_worker = %{worker | last_heartbeat: old_time}
      :ets.insert(:worker_registry, {"worker-1", dead_worker})

      # Trigger health check manually by sending message to registry
      send(Process.whereis(WorkerRegistry), :health_check)
      
      # Give it time to process
      :timer.sleep(100)

      # Worker should be deregistered
      assert {:error, :not_found} = WorkerRegistry.get_worker("worker-1")
    end

    test "does not deregister workers with recent heartbeats" do
      {:ok, _} = WorkerRegistry.register_worker("worker-1", %{language: "kotlin"})
      
      # Send recent heartbeat
      WorkerRegistry.heartbeat("worker-1", :idle)

      # Trigger health check
      send(Process.whereis(WorkerRegistry), :health_check)
      :timer.sleep(100)

      # Worker should still be registered
      assert {:ok, _worker} = WorkerRegistry.get_worker("worker-1")
    end
  end
end
