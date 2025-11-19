defmodule Cerebelum.Execution.StateReconstructorTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Execution.{Engine, StateReconstructor}
  alias Cerebelum.EventStore
  alias Cerebelum.Repo
  alias Cerebelum.Examples.CounterWorkflow

  setup do
    # Checkout sandbox connection for test isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Allow EventStore GenServer to use the sandbox connection
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), Process.whereis(Cerebelum.EventStore))

    # Clean up events table before each test (Repo and EventStore already started by app)
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE events CASCADE", [])

    :ok
  end

  describe "reconstruct/1" do
    test "reconstructs state from successful execution" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})

      # Get execution ID from status
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Get final status
      final_status = Engine.get_status(pid)
      assert final_status.state == :completed

      # Force flush events
      EventStore.flush()
      Process.sleep(50)

      # Reconstruct state
      {:ok, reconstructed} = StateReconstructor.reconstruct(execution_id)

      # Verify reconstruction matches final state
      assert reconstructed.execution_id == execution_id
      assert reconstructed.workflow_module == "Elixir.Cerebelum.Examples.CounterWorkflow"
      assert reconstructed.status == :completed
      assert Map.has_key?(reconstructed.results, :initialize)
      assert Map.has_key?(reconstructed.results, :increment)
      assert Map.has_key?(reconstructed.results, :double)
      assert Map.has_key?(reconstructed.results, :finalize)
      assert reconstructed.error == nil
      assert reconstructed.events_applied > 0
    end

    test "returns error for non-existent execution" do
      result = StateReconstructor.reconstruct("non-existent-id")
      assert result == {:error, :not_found}
    end
  end

  describe "reconstruct_to_version/2" do
    test "reconstructs partial state up to specific version" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})

      # Get execution ID from status
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Force flush events
      EventStore.flush()
      Process.sleep(50)

      # Get all events to know how many there are
      {:ok, events} = EventStore.get_events(execution_id)
      assert length(events) > 2

      # Reconstruct only first 2 events (ExecutionStarted + StepExecuted for initialize)
      {:ok, partial_state} = StateReconstructor.reconstruct_to_version(execution_id, 1)

      # Should have status :running since we haven't seen completion event
      assert partial_state.status == :running
      # Should have initialize result
      assert Map.has_key?(partial_state.results, :initialize)
      # Should NOT have later results yet
      assert not Map.has_key?(partial_state.results, :finalize)
      assert partial_state.events_applied == 2
    end

    test "can reconstruct state at different points in time" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})

      # Get execution ID from status
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Force flush events
      EventStore.flush()
      Process.sleep(50)

      # Get full state
      {:ok, full_state} = StateReconstructor.reconstruct(execution_id)

      # Reconstruct at version 0 (just started)
      {:ok, v0_state} = StateReconstructor.reconstruct_to_version(execution_id, 0)
      assert v0_state.status == :running
      assert map_size(v0_state.results) == 0

      # Each subsequent version should add more state
      {:ok, v1_state} = StateReconstructor.reconstruct_to_version(execution_id, 1)
      assert map_size(v1_state.results) >= 1

      # Full reconstruction should have all 4 steps
      assert map_size(full_state.results) == 4
      assert full_state.status == :completed
    end
  end

  describe "state consistency" do
    test "reconstructed state matches live engine state" do
      # Execute workflow
      {:ok, pid} = Engine.start_link(workflow_module: CounterWorkflow, inputs: %{})

      # Get execution ID from status
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(150)

      # Get live status
      live_status = Engine.get_status(pid)

      # Force flush events
      EventStore.flush()
      Process.sleep(50)

      # Reconstruct state
      {:ok, reconstructed} = StateReconstructor.reconstruct(execution_id)

      # Verify key fields match
      assert reconstructed.execution_id == live_status.execution_id
      assert reconstructed.status == live_status.state
      assert reconstructed.results == live_status.results
      assert reconstructed.iteration == live_status.iteration
    end
  end
end
