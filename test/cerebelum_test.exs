defmodule CerebelumTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Examples.CounterWorkflow

  setup do
    # Clean up any executions from previous tests
    Cerebelum.list_executions()
    |> Enum.each(fn exec -> Cerebelum.stop_execution(exec.pid) end)

    :timer.sleep(10)
    :ok
  end

  describe "execute_workflow/2" do
    test "starts a workflow execution" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      assert is_binary(execution.id)
      assert is_pid(execution.pid)
      assert Process.alive?(execution.pid)

      # Cleanup
      Cerebelum.stop_execution(execution.pid)
    end

    test "accepts inputs" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{test: "data"})

      {:ok, status} = Cerebelum.get_execution_status(execution.pid)
      assert status.context.inputs == %{test: "data"}

      Cerebelum.stop_execution(execution.pid)
    end

    test "returns unique execution IDs" do
      {:ok, exec1} = Cerebelum.execute_workflow(CounterWorkflow, %{})
      {:ok, exec2} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      assert exec1.id != exec2.id

      Cerebelum.stop_execution(exec1.pid)
      Cerebelum.stop_execution(exec2.pid)
    end
  end

  describe "execute_workflow/3" do
    test "accepts options" do
      {:ok, execution} = Cerebelum.execute_workflow(
        CounterWorkflow,
        %{},
        correlation_id: "trace-123",
        tags: ["test"]
      )

      {:ok, status} = Cerebelum.get_execution_status(execution.pid)
      assert status.context.correlation_id == "trace-123"
      assert "test" in status.context.tags

      Cerebelum.stop_execution(execution.pid)
    end

    test "accepts custom execution_id" do
      custom_id = "my-custom-id-#{:rand.uniform(1000)}"

      {:ok, execution} = Cerebelum.execute_workflow(
        CounterWorkflow,
        %{},
        execution_id: custom_id
      )

      assert execution.id == custom_id

      Cerebelum.stop_execution(execution.pid)
    end
  end

  describe "get_execution_status/1" do
    test "gets status by PID" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      {:ok, status} = Cerebelum.get_execution_status(execution.pid)

      assert is_map(status)
      assert status.execution_id == execution.id
      assert status.workflow_module == CounterWorkflow

      Cerebelum.stop_execution(execution.pid)
    end

    test "gets status by execution ID" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      {:ok, status} = Cerebelum.get_execution_status(execution.id)

      assert status.execution_id == execution.id

      Cerebelum.stop_execution(execution.pid)
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = Cerebelum.get_execution_status("non-existent")
    end

    test "returns error for terminated execution" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      Cerebelum.stop_execution(execution.pid)
      :timer.sleep(50)

      assert {:error, :not_found} = Cerebelum.get_execution_status(execution.pid)
    end
  end

  describe "stop_execution/1" do
    test "stops execution by PID" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      assert :ok = Cerebelum.stop_execution(execution.pid)

      :timer.sleep(50)
      refute Process.alive?(execution.pid)
    end

    test "stops execution by ID" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      assert :ok = Cerebelum.stop_execution(execution.id)

      :timer.sleep(50)
      refute Process.alive?(execution.pid)
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = Cerebelum.stop_execution("non-existent")
    end
  end

  describe "list_executions/0" do
    test "lists all running executions" do
      {:ok, exec1} = Cerebelum.execute_workflow(CounterWorkflow, %{})
      {:ok, exec2} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      executions = Cerebelum.list_executions()

      assert length(executions) >= 2

      ids = Enum.map(executions, & &1.id)
      assert exec1.id in ids
      assert exec2.id in ids

      Cerebelum.stop_execution(exec1.pid)
      Cerebelum.stop_execution(exec2.pid)
    end

    test "returns empty list when no executions" do
      # Clean up first
      Cerebelum.list_executions()
      |> Enum.each(&Cerebelum.stop_execution(&1.pid))

      :timer.sleep(50)

      executions = Cerebelum.list_executions()
      assert executions == []
    end

    test "execution info includes key fields" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      [info | _] = Cerebelum.list_executions()

      assert Map.has_key?(info, :id)
      assert Map.has_key?(info, :pid)
      assert Map.has_key?(info, :state)
      assert Map.has_key?(info, :workflow_module)
      assert Map.has_key?(info, :current_step)
      assert Map.has_key?(info, :progress)

      Cerebelum.stop_execution(execution.pid)
    end
  end

  describe "count_executions/0" do
    test "counts running executions" do
      initial_count = Cerebelum.count_executions()

      {:ok, exec1} = Cerebelum.execute_workflow(CounterWorkflow, %{})
      {:ok, exec2} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      assert Cerebelum.count_executions() == initial_count + 2

      Cerebelum.stop_execution(exec1.pid)
      Cerebelum.stop_execution(exec2.pid)
    end
  end

  describe "end-to-end workflow execution" do
    test "executes workflow to completion" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      # Wait for execution to complete
      :timer.sleep(150)

      {:ok, status} = Cerebelum.get_execution_status(execution.id)

      assert status.state == :completed
      assert map_size(status.results) == 4
      assert status.results[:initialize] == {:ok, 0}
      assert status.results[:finalize] == {:ok, 2}

      Cerebelum.stop_execution(execution.pid)
    end

    test "tracks execution progress" do
      {:ok, execution} = Cerebelum.execute_workflow(CounterWorkflow, %{})

      # Check initial state
      {:ok, status} = Cerebelum.get_execution_status(execution.pid)
      assert status.state in [:initializing, :executing_step, :completed]

      # Wait and check final state
      :timer.sleep(150)
      {:ok, final_status} = Cerebelum.get_execution_status(execution.id)
      assert final_status.state == :completed

      Cerebelum.stop_execution(execution.pid)
    end
  end
end
