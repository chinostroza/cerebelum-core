defmodule Cerebelum.Debug.InspectorTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Debug.Inspector
  alias Cerebelum.Execution.Engine
  alias Cerebelum.EventStore
  alias Cerebelum.Repo
  alias Cerebelum.Examples.CounterWorkflow

  setup do
    # Checkout sandbox connection for test isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Allow EventStore GenServer to use the sandbox connection
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), Process.whereis(Cerebelum.EventStore))

    # Clean up events table before each test
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE events CASCADE", [])

    :ok
  end

  describe "state_at_version/2" do
    test "reconstructs state at specific version" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get state at version 0 (just started)
      {:ok, state_v0} = Inspector.state_at_version(execution_id, 0)
      assert state_v0.status == :running
      assert map_size(state_v0.results) == 0

      # Get state at version 1 (after first step)
      {:ok, state_v1} = Inspector.state_at_version(execution_id, 1)
      assert state_v1.status == :running
      assert Map.has_key?(state_v1.results, :initialize)
    end

    test "returns error for non-existent execution" do
      result = Inspector.state_at_version("non-existent", 0)
      assert result == {:error, :not_found}
    end
  end

  describe "current_state/1" do
    test "returns final state of execution" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get current state
      {:ok, state} = Inspector.current_state(execution_id)

      assert state.status == :completed
      assert map_size(state.results) == 4
      assert Map.has_key?(state.results, :initialize)
      assert Map.has_key?(state.results, :finalize)
    end
  end

  describe "state_at_step/2" do
    test "returns state after specific step execution" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get state after increment step
      {:ok, state} = Inspector.state_at_step(execution_id, :increment)

      assert state.status == :running
      assert Map.has_key?(state.results, :initialize)
      assert Map.has_key?(state.results, :increment)
      assert not Map.has_key?(state.results, :double)
    end

    test "returns error for non-existent step" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Try to get state for non-existent step
      result = Inspector.state_at_step(execution_id, :nonexistent)
      assert result == {:error, :step_not_found}
    end
  end

  describe "diff_versions/3" do
    test "computes diff between two versions" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Diff between version 1 and 3
      {:ok, diff} = Inspector.diff_versions(execution_id, 1, 3)

      # Version 1 has initialize, version 3 has initialize + increment + double
      assert :increment in diff.results_added
      assert :double in diff.results_added
      assert diff.results_removed == []
    end
  end

  describe "diff_at_step/2" do
    test "computes diff before and after step" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Diff at increment step
      {:ok, diff} = Inspector.diff_at_step(execution_id, :increment)

      # increment should be added
      assert :increment in diff.results_added
      assert diff.current_step_changed == {:initialize, :increment}
    end

    test "diffs at first step shows changes from initial state" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Diff at first step should show what was added
      {:ok, diff} = Inspector.diff_at_step(execution_id, :initialize)

      # Should show initialize was added
      assert :initialize in diff.results_added
      assert diff.results_removed == []
      assert diff.current_step_changed == {nil, :initialize}
    end
  end

  describe "list_steps/1" do
    test "lists all executed steps" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # List steps
      {:ok, steps} = Inspector.list_steps(execution_id)

      assert length(steps) == 4
      assert :initialize in steps
      assert :increment in steps
      assert :double in steps
      assert :finalize in steps
    end
  end

  describe "timeline/1" do
    test "returns execution timeline with events" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get timeline
      {:ok, timeline} = Inspector.timeline(execution_id)

      assert length(timeline) > 0

      # First event should be ExecutionStartedEvent
      first_event = List.first(timeline)
      assert first_event.version == 0
      assert first_event.type == "ExecutionStartedEvent"
      assert first_event.step == nil

      # Should have StepExecutedEvent entries
      step_events = Enum.filter(timeline, &(&1.type == "StepExecutedEvent"))
      assert length(step_events) >= 4
    end
  end

  describe "stats/1" do
    test "returns execution statistics" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get stats
      {:ok, stats} = Inspector.stats(execution_id)

      assert stats.total_steps == 4
      assert stats.status == :completed
      assert stats.iterations == 0
      assert stats.has_error == false
      assert stats.total_events > 0
    end
  end

  describe "find_error/1" do
    defmodule FailingTestWorkflow do
      use Cerebelum.Workflow

      workflow do
        timeline do
          step1() |> step2() |> step3()
        end
      end

      def step1(_ctx), do: {:ok, 1}
      def step2(_ctx, {:ok, _}), do: raise("Test error")
      def step3(_ctx, {:ok, _}, {:ok, _}), do: {:ok, 3}
    end

    test "finds error event in failed execution" do
      # Execute failing workflow
      {:ok, pid} = Engine.start_link(workflow_module: FailingTestWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for failure
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Find error
      {:ok, error} = Inspector.find_error(execution_id)

      assert error != nil
      # Note: error.kind is a string because events serialize atoms as strings
      assert error.kind == "exception"
      assert error.step == "step2"
      assert error.message =~ "Test error"
    end

    test "returns nil for successful execution" do
      # Execute successful workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Find error (should be nil)
      {:ok, error} = Inspector.find_error(execution_id)
      assert error == nil
    end
  end
end
