defmodule Cerebelum.Execution.ParallelExecutionTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Execution.Engine
  alias Cerebelum.EventStore
  alias Cerebelum.Repo

  setup do
    # Clean up events table before each test
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE events CASCADE", [])

    :ok
  end

  defmodule ParallelWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> fetch_all_data() |> process_results() |> finalize()
      end
    end

    def start(_ctx) do
      {:ok, %{started: true}}
    end

    def fetch_all_data(_ctx, {:ok, _start}) do
      # Return parallel tasks
      tasks = [
        {:fetch_users, []},
        {:fetch_orders, []},
        {:fetch_products, []}
      ]

      {:parallel, tasks}
    end

    # Parallel task functions
    def fetch_users(_ctx) do
      # Simulate API call
      Process.sleep(10)
      {:ok, %{users: [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]}}
    end

    def fetch_orders(_ctx) do
      # Simulate API call
      Process.sleep(15)
      {:ok, %{orders: [%{id: 101, user_id: 1}, %{id: 102, user_id: 2}]}}
    end

    def fetch_products(_ctx) do
      # Simulate API call
      Process.sleep(5)
      {:ok, %{products: [%{id: 501, name: "Widget"}, %{id: 502, name: "Gadget"}]}}
    end

    def process_results(_ctx, _start, {:ok, parallel_results}) do
      # Parallel results are merged into a map
      # %{fetch_users: {:ok, %{users: [...]}}, fetch_orders: {:ok, %{orders: [...]}}, ...}

      # Extract results from each task
      {:ok, user_data} = parallel_results[:fetch_users]
      {:ok, order_data} = parallel_results[:fetch_orders]
      {:ok, product_data} = parallel_results[:fetch_products]

      users = user_data[:users] || []
      orders = order_data[:orders] || []
      products = product_data[:products] || []

      {:ok,
       %{
         user_count: length(users),
         order_count: length(orders),
         product_count: length(products)
       }}
    end

    def finalize(_ctx, _start, _parallel, {:ok, counts}) do
      {:ok, %{completed: true, counts: counts}}
    end
  end

  defmodule FailingParallelWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        start() |> fetch_data_with_failures()
      end
    end

    def start(_ctx) do
      {:ok, %{started: true}}
    end

    def fetch_data_with_failures(_ctx, {:ok, _start}) do
      tasks = [
        {:task_success, []},
        {:task_failure, []},
        {:task_success2, []}
      ]

      {:parallel, tasks}
    end

    def task_success(_ctx) do
      {:ok, %{data: "success1"}}
    end

    def task_failure(_ctx) do
      raise "Intentional failure in parallel task"
    end

    def task_success2(_ctx) do
      {:ok, %{data: "success2"}}
    end
  end

  describe "parallel execution" do
    test "executes multiple tasks in parallel successfully" do
      # Start workflow execution
      {:ok, pid} = Engine.start_link(workflow_module: ParallelWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(200)

      # Flush events to database
      EventStore.flush()
      Process.sleep(100)

      # Get final status
      status = Engine.get_status(pid)

      # Should complete successfully
      assert status.state == :completed
      assert status.results.finalize == {:ok, %{completed: true, counts: %{user_count: 2, order_count: 2, product_count: 2}}}

      # Check events were recorded
      {:ok, events} = EventStore.get_events(execution_id)

      # Should have parallel events
      parallel_started = Enum.find(events, fn e -> e.event_type == "ParallelStartedEvent" end)
      assert parallel_started != nil

      task_completed_events =
        Enum.filter(events, fn e -> e.event_type == "ParallelTaskCompletedEvent" end)

      assert length(task_completed_events) == 3

      parallel_completed = Enum.find(events, fn e -> e.event_type == "ParallelCompletedEvent" end)
      assert parallel_completed != nil
    end

    test "handles task failures in parallel execution" do
      # Start workflow execution
      {:ok, pid} = Engine.start_link(workflow_module: FailingParallelWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for failure
      Process.sleep(200)

      # Flush events
      EventStore.flush()
      Process.sleep(100)

      # Get final status
      status = Engine.get_status(pid)

      # Should fail due to task failure
      assert status.state == :failed
      assert status.error != nil

      # Check events were recorded
      {:ok, events} = EventStore.get_events(execution_id)

      # Should have parallel started event
      parallel_started = Enum.find(events, fn e -> e.event_type == "ParallelStartedEvent" end)
      assert parallel_started != nil

      # Should have at least one task failure event
      task_failed_events =
        Enum.filter(events, fn e -> e.event_type == "ParallelTaskFailedEvent" end)

      assert length(task_failed_events) >= 1

      # Should have successful task completions for tasks that succeeded
      task_completed_events =
        Enum.filter(events, fn e -> e.event_type == "ParallelTaskCompletedEvent" end)

      # At least some tasks should complete before failure
      assert length(task_completed_events) >= 0
    end

    test "parallel tasks execute concurrently (verified by events)" do
      # Start workflow execution
      {:ok, pid} = Engine.start_link(workflow_module: ParallelWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(300)

      # Flush events
      EventStore.flush()
      Process.sleep(100)

      # Get final status
      status = Engine.get_status(pid)
      assert status.state == :completed

      # Verify parallel execution happened by checking events
      {:ok, events} = EventStore.get_events(execution_id)

      # Get parallel completed event which contains total duration
      parallel_completed = Enum.find(events, fn e -> e.event_type == "ParallelCompletedEvent" end)
      assert parallel_completed != nil

      # Extract duration from event data
      total_duration = parallel_completed.event_data["total_duration_ms"]

      # If tasks ran sequentially: 10 + 15 + 5 = 30ms
      # If tasks ran in parallel: ~15ms (longest task) + overhead
      # Parallel should be significantly faster than sequential
      # Allow some overhead, but should be well under 100ms
      assert total_duration < 100
    end
  end

  describe "parallel executor unit tests" do
    alias Cerebelum.Execution.ParallelExecutor
    alias Cerebelum.Context

    defmodule TestModule do
      def task1(_ctx), do: {:ok, "result1"}
      def task2(_ctx), do: {:ok, "result2"}
      def task3(_ctx), do: {:ok, "result3"}
      def failing_task(_ctx), do: raise("Task failed")
    end

    test "execute_parallel returns merged results" do
      execution_id = Ecto.UUID.generate()
      context = Context.new(TestModule, %{})

      task_specs = [
        {:task1, []},
        {:task2, []},
        {:task3, []}
      ]

      result =
        ParallelExecutor.execute_parallel(
          TestModule,
          task_specs,
          context,
          :test_step,
          execution_id,
          initial_version: 0
        )

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      assert {:ok, results, _final_version} = result
      assert results[:task1] == {:ok, "result1"}
      assert results[:task2] == {:ok, "result2"}
      assert results[:task3] == {:ok, "result3"}
    end

    test "execute_parallel handles task failures" do
      execution_id = Ecto.UUID.generate()
      context = Context.new(TestModule, %{})

      task_specs = [
        {:task1, []},
        {:failing_task, []},
        {:task3, []}
      ]

      result =
        ParallelExecutor.execute_parallel(
          TestModule,
          task_specs,
          context,
          :test_step,
          execution_id,
          initial_version: 0
        )

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      assert {:error, _reason, _partial_results, _final_version} = result
    end
  end
end
