defmodule Cerebelum.Infrastructure.TaskRouterTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Infrastructure.TaskRouter
  alias Cerebelum.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Clear ETS tables before each test
    :ets.delete_all_objects(:task_queue)
    :ets.delete_all_objects(:execution_worker_mapping)
    :ets.delete_all_objects(:pending_polls)

    :ok
  end

  describe "queue_task/2" do
    test "queues a task and returns task_id" do
      execution_id = "exec_123"
      task = %{
        workflow_module: "TestWorkflow",
        step_name: "process",
        inputs: %{data: "test"}
      }

      {:ok, task_id} = TaskRouter.queue_task(execution_id, task)

      assert is_binary(task_id)
      assert String.starts_with?(task_id, "task_")

      # Verify task is in queue
      stats = TaskRouter.get_stats()
      assert stats.pending_tasks == 1
    end

    test "queues multiple tasks for same execution" do
      execution_id = "exec_123"

      {:ok, task_id_1} = TaskRouter.queue_task(execution_id, %{step_name: "step1"})
      {:ok, task_id_2} = TaskRouter.queue_task(execution_id, %{step_name: "step2"})

      assert task_id_1 != task_id_2

      stats = TaskRouter.get_stats()
      assert stats.pending_tasks == 2
    end

    test "notifies waiting workers when task queued" do
      worker_id = "worker_1"
      execution_id = "exec_123"

      # Worker starts polling (will block)
      poll_task = Task.async(fn ->
        TaskRouter.poll_for_task(worker_id, 5000)
      end)

      # Give worker time to enter long-poll state
      :timer.sleep(100)

      # Queue a task (should notify waiting worker)
      {:ok, _task_id} = TaskRouter.queue_task(execution_id, %{step_name: "process"})

      # Worker should receive task immediately
      assert {:ok, task} = Task.await(poll_task)
      assert task.step_name == "process"
    end
  end

  describe "poll_for_task/2" do
    test "returns task immediately if available" do
      execution_id = "exec_123"
      worker_id = "worker_1"

      {:ok, _task_id} = TaskRouter.queue_task(execution_id, %{
        step_name: "process",
        inputs: %{data: "test"}
      })

      assert {:ok, task} = TaskRouter.poll_for_task(worker_id, 1000)
      assert task.execution_id == execution_id
      assert task.step_name == "process"
      assert task.inputs == %{data: "test"}
      assert task.status == :pending
    end

    test "long-polls until task available" do
      worker_id = "worker_1"
      execution_id = "exec_123"

      start_time = System.monotonic_time(:millisecond)

      # Worker starts polling (will block)
      poll_task = Task.async(fn ->
        TaskRouter.poll_for_task(worker_id, 5000)
      end)

      # Wait 500ms, then queue task
      :timer.sleep(500)
      {:ok, _task_id} = TaskRouter.queue_task(execution_id, %{step_name: "delayed"})

      # Worker should get task after ~500ms
      assert {:ok, task} = Task.await(poll_task)
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert task.step_name == "delayed"
      assert elapsed >= 500 and elapsed < 1000
    end

    test "returns timeout error when no task available" do
      worker_id = "worker_1"

      assert {:error, :timeout} = TaskRouter.poll_for_task(worker_id, 100)
    end

    test "respects maximum timeout of 30 seconds" do
      worker_id = "worker_1"

      start_time = System.monotonic_time(:millisecond)

      # Request 60s timeout (should be capped at 30s)
      assert {:error, :timeout} = TaskRouter.poll_for_task(worker_id, 60_000)

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should timeout around 30s, not 60s
      # Allow some margin for processing time
      assert elapsed >= 29_000 and elapsed <= 31_000
    end

    test "multiple workers can poll concurrently" do
      # Queue 3 tasks for 3 DIFFERENT executions
      # (same execution would be sticky-routed to same worker)
      exec_1 = "exec_1"
      exec_2 = "exec_2"
      exec_3 = "exec_3"

      # Start 3 workers polling
      workers = for i <- 1..3 do
        worker_id = "worker_#{i}"
        Task.async(fn ->
          {worker_id, TaskRouter.poll_for_task(worker_id, 5000)}
        end)
      end

      # Give workers time to enter long-poll state
      :timer.sleep(100)

      # Queue 3 tasks for DIFFERENT executions with small delays
      {:ok, _} = TaskRouter.queue_task(exec_1, %{step_name: "step_1"})
      :timer.sleep(50)
      {:ok, _} = TaskRouter.queue_task(exec_2, %{step_name: "step_2"})
      :timer.sleep(50)
      {:ok, _} = TaskRouter.queue_task(exec_3, %{step_name: "step_3"})

      # All workers should get tasks
      results = Enum.map(workers, &Task.await/1)

      assert length(results) == 3

      # Count how many workers got tasks
      successful_polls = Enum.count(results, fn {_worker_id, result} ->
        match?({:ok, _task}, result)
      end)

      # All workers should get tasks (different executions, no sticky routing)
      assert successful_polls == 3, "Expected 3 workers to get tasks, got #{successful_polls}"

      # All tasks should be assigned
      stats = TaskRouter.get_stats()
      assert stats.pending_tasks == 0
    end
  end

  describe "sticky routing" do
    test "assigns tasks from same execution to same worker" do
      execution_id = "exec_123"
      worker_1 = "worker_1"
      worker_2 = "worker_2"

      # Queue 3 tasks for same execution
      {:ok, _} = TaskRouter.queue_task(execution_id, %{step_name: "step1"})
      {:ok, _} = TaskRouter.queue_task(execution_id, %{step_name: "step2"})
      {:ok, _} = TaskRouter.queue_task(execution_id, %{step_name: "step3"})

      # Worker 1 gets first task
      {:ok, task1} = TaskRouter.poll_for_task(worker_1, 100)
      assert task1.execution_id == execution_id

      # Worker 1 should get second task (sticky routing)
      {:ok, task2} = TaskRouter.poll_for_task(worker_1, 100)
      assert task2.execution_id == execution_id

      # Worker 1 should get third task
      {:ok, task3} = TaskRouter.poll_for_task(worker_1, 100)
      assert task3.execution_id == execution_id

      # Worker 2 should timeout (no tasks left)
      assert {:error, :timeout} = TaskRouter.poll_for_task(worker_2, 100)
    end

    test "fallback to any worker when preferred worker unavailable" do
      exec_1 = "exec_1"
      exec_2 = "exec_2"
      worker_1 = "worker_1"
      worker_2 = "worker_2"

      # Queue tasks for two different executions
      {:ok, _} = TaskRouter.queue_task(exec_1, %{step_name: "step1"})
      {:ok, _} = TaskRouter.queue_task(exec_2, %{step_name: "step2"})

      # Worker 1 gets first available task (becomes preferred worker for that execution)
      {:ok, task1} = TaskRouter.poll_for_task(worker_1, 100)
      first_execution = task1.execution_id
      assert first_execution in [exec_1, exec_2]

      # Worker 2 gets task from the other execution
      {:ok, task2} = TaskRouter.poll_for_task(worker_2, 100)
      second_execution = task2.execution_id
      assert second_execution in [exec_1, exec_2]
      assert second_execution != first_execution
    end

    test "worker handles tasks from multiple executions when needed" do
      exec_1 = "exec_1"
      exec_2 = "exec_2"
      worker_1 = "worker_1"

      # Queue tasks for two different executions
      {:ok, _} = TaskRouter.queue_task(exec_1, %{step_name: "step1"})
      {:ok, _} = TaskRouter.queue_task(exec_2, %{step_name: "step2"})

      # Worker 1 gets both tasks (only worker available)
      {:ok, task1} = TaskRouter.poll_for_task(worker_1, 100)
      {:ok, task2} = TaskRouter.poll_for_task(worker_1, 100)

      # Should get tasks from both executions
      execution_ids = [task1.execution_id, task2.execution_id]
      assert exec_1 in execution_ids
      assert exec_2 in execution_ids
    end
  end

  describe "submit_result/3" do
    test "accepts task result from worker" do
      execution_id = "exec_123"
      worker_id = "worker_1"

      # Queue and poll task
      {:ok, _task_id} = TaskRouter.queue_task(execution_id, %{step_name: "process"})
      {:ok, task} = TaskRouter.poll_for_task(worker_id, 100)

      result = %{
        task_id: task.task_id,
        execution_id: execution_id,
        worker_id: worker_id,
        status: :success,
        result: %{output: "done"},
        completed_at: System.system_time(:millisecond)
      }

      assert {:ok, :ack} = TaskRouter.submit_result(task.task_id, worker_id, result)
    end

    test "accepts failed task result" do
      execution_id = "exec_123"
      worker_id = "worker_1"

      {:ok, _task_id} = TaskRouter.queue_task(execution_id, %{step_name: "process"})
      {:ok, task} = TaskRouter.poll_for_task(worker_id, 100)

      result = %{
        task_id: task.task_id,
        execution_id: execution_id,
        worker_id: worker_id,
        status: :failed,
        error: %{
          kind: "RuntimeError",
          message: "Something went wrong",
          stacktrace: "line 1\nline 2"
        },
        completed_at: System.system_time(:millisecond)
      }

      assert {:ok, :ack} = TaskRouter.submit_result(task.task_id, worker_id, result)
    end
  end

  describe "cancel_tasks/1" do
    test "removes all pending tasks for an execution" do
      execution_id = "exec_123"

      # Queue 3 tasks
      {:ok, _} = TaskRouter.queue_task(execution_id, %{step_name: "step1"})
      {:ok, _} = TaskRouter.queue_task(execution_id, %{step_name: "step2"})
      {:ok, _} = TaskRouter.queue_task(execution_id, %{step_name: "step3"})

      stats = TaskRouter.get_stats()
      assert stats.pending_tasks == 3

      # Cancel all tasks
      assert :ok = TaskRouter.cancel_tasks(execution_id)

      # Queue should be empty
      stats = TaskRouter.get_stats()
      assert stats.pending_tasks == 0

      # Workers should timeout
      assert {:error, :timeout} = TaskRouter.poll_for_task("worker_1", 100)
    end

    test "only cancels tasks for specified execution" do
      exec_1 = "exec_1"
      exec_2 = "exec_2"

      {:ok, _} = TaskRouter.queue_task(exec_1, %{step_name: "step1"})
      {:ok, _} = TaskRouter.queue_task(exec_2, %{step_name: "step2"})

      # Cancel only exec_1 tasks
      :ok = TaskRouter.cancel_tasks(exec_1)

      # exec_2 task should still be available
      {:ok, task} = TaskRouter.poll_for_task("worker_1", 100)
      assert task.execution_id == exec_2
    end
  end

  describe "get_stats/0" do
    test "returns task queue statistics" do
      stats = TaskRouter.get_stats()

      assert Map.has_key?(stats, :pending_tasks)
      assert Map.has_key?(stats, :pending_polls)
      assert Map.has_key?(stats, :active_executions)

      assert stats.pending_tasks == 0
      assert stats.pending_polls == 0
      assert stats.active_executions == 0
    end

    test "tracks pending tasks correctly" do
      {:ok, _} = TaskRouter.queue_task("exec_1", %{step_name: "step1"})
      {:ok, _} = TaskRouter.queue_task("exec_2", %{step_name: "step2"})

      stats = TaskRouter.get_stats()
      assert stats.pending_tasks == 2
    end

    test "tracks pending polls correctly" do
      # Start 2 workers long-polling
      task1 = Task.async(fn -> TaskRouter.poll_for_task("worker_1", 5000) end)
      task2 = Task.async(fn -> TaskRouter.poll_for_task("worker_2", 5000) end)

      # Give workers time to enter long-poll state
      :timer.sleep(100)

      stats = TaskRouter.get_stats()
      assert stats.pending_polls == 2

      # Cleanup
      {:ok, _} = TaskRouter.queue_task("exec_1", %{step_name: "step1"})
      {:ok, _} = TaskRouter.queue_task("exec_2", %{step_name: "step2"})
      Task.await(task1)
      Task.await(task2)
    end

    test "tracks active executions correctly" do
      # Worker polls and gets task
      {:ok, _} = TaskRouter.queue_task("exec_1", %{step_name: "step1"})
      {:ok, _task} = TaskRouter.poll_for_task("worker_1", 100)

      stats = TaskRouter.get_stats()
      assert stats.active_executions >= 1
    end
  end

  describe "performance" do
    @tag :performance
    @tag timeout: 10_000
    test "distributes 100 tasks to 10 workers in under 1 second" do
      execution_id = "exec_perf"
      num_tasks = 100
      num_workers = 10

      # Queue all tasks
      for i <- 1..num_tasks do
        {:ok, _} = TaskRouter.queue_task(execution_id, %{step_name: "step_#{i}"})
      end

      start_time = System.monotonic_time(:millisecond)

      # Start workers polling
      workers = for i <- 1..num_workers do
        Task.async(fn ->
          worker_id = "worker_#{i}"
          poll_until_empty(worker_id, [])
        end)
      end

      # Collect all tasks
      all_tasks = workers
        |> Enum.map(&Task.await(&1, 5000))
        |> List.flatten()

      elapsed = System.monotonic_time(:millisecond) - start_time

      # All tasks should be assigned
      assert length(all_tasks) == num_tasks

      # Should complete in under 1 second
      assert elapsed < 1000, "Distribution took #{elapsed}ms (expected < 1000ms)"
    end
  end

  # Helper function for performance test
  defp poll_until_empty(worker_id, acc) do
    case TaskRouter.poll_for_task(worker_id, 100) do
      {:ok, task} -> poll_until_empty(worker_id, [task | acc])
      {:error, :timeout} -> acc
    end
  end
end
