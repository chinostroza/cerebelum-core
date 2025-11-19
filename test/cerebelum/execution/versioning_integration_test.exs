defmodule Cerebelum.Execution.VersioningIntegrationTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Execution.Engine
  alias Cerebelum.EventStore
  alias Cerebelum.Workflow.Versioning
  alias Cerebelum.Repo

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

  defmodule VersionedWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> step2() |> step3()
      end
    end

    def step1(_ctx), do: {:ok, 1}
    def step2(_ctx, {:ok, _}), do: {:ok, 2}
    def step3(_ctx, {:ok, _}, {:ok, _}), do: {:ok, 3}
  end

  describe "workflow version tracking" do
    test "version is stored in ExecutionStartedEvent" do
      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: VersionedWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for execution to complete
      Process.sleep(100)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get events
      {:ok, events} = EventStore.get_events(execution_id)

      # Find ExecutionStartedEvent
      execution_started = Enum.find(events, fn e -> e.event_type == "ExecutionStartedEvent" end)

      assert execution_started != nil
      assert Map.has_key?(execution_started.event_data, "workflow_version")

      workflow_version = execution_started.event_data["workflow_version"]

      # Version should be a valid SHA256 hash (64 hex characters)
      assert is_binary(workflow_version)
      assert String.length(workflow_version) == 64
      assert String.match?(workflow_version, ~r/^[0-9a-f]{64}$/)
    end

    test "stored version matches workflow metadata version" do
      # Get the workflow version from metadata
      expected_version = Versioning.get_version(VersionedWorkflow)

      # Start workflow
      {:ok, pid} = Engine.start_link(workflow_module: VersionedWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for execution to complete
      Process.sleep(100)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get events
      {:ok, events} = EventStore.get_events(execution_id)

      # Find ExecutionStartedEvent
      execution_started = Enum.find(events, fn e -> e.event_type == "ExecutionStartedEvent" end)

      workflow_version = execution_started.event_data["workflow_version"]

      # Should match the version from metadata
      assert workflow_version == expected_version
    end

    test "multiple executions of same workflow have same version" do
      # Start first execution
      {:ok, pid1} = Engine.start_link(workflow_module: VersionedWorkflow, inputs: %{})
      status1 = Engine.get_status(pid1)
      execution_id1 = status1.execution_id

      # Start second execution
      {:ok, pid2} = Engine.start_link(workflow_module: VersionedWorkflow, inputs: %{})
      status2 = Engine.get_status(pid2)
      execution_id2 = status2.execution_id

      # Wait for both to complete
      Process.sleep(150)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get events for both executions
      {:ok, events1} = EventStore.get_events(execution_id1)
      {:ok, events2} = EventStore.get_events(execution_id2)

      # Find ExecutionStartedEvents
      execution_started1 =
        Enum.find(events1, fn e -> e.event_type == "ExecutionStartedEvent" end)

      execution_started2 =
        Enum.find(events2, fn e -> e.event_type == "ExecutionStartedEvent" end)

      version1 = execution_started1.event_data["workflow_version"]
      version2 = execution_started2.event_data["workflow_version"]

      # Both executions should have the same version
      assert version1 == version2
    end

    test "version can be used to detect workflow changes" do
      # Get the current version
      current_version = Versioning.get_version(VersionedWorkflow)

      # Simulate an old execution with a different version
      fake_old_version = "0000000000000000000000000000000000000000000000000000000000000000"

      # Verify version mismatch
      assert {:error, :mismatch, details} =
               Versioning.verify_version(fake_old_version, current_version)

      assert details.expected == fake_old_version
      assert details.actual == current_version

      # Check if workflow has changed
      assert Versioning.has_changed?(VersionedWorkflow, fake_old_version)
    end
  end

  describe "version mismatch detection for replay" do
    test "can detect version mismatch when replaying" do
      # Start and complete an execution
      {:ok, pid} = Engine.start_link(workflow_module: VersionedWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(100)

      # Flush events
      EventStore.flush()
      Process.sleep(50)

      # Get events
      {:ok, events} = EventStore.get_events(execution_id)

      # Find ExecutionStartedEvent
      execution_started = Enum.find(events, fn e -> e.event_type == "ExecutionStartedEvent" end)
      stored_version = execution_started.event_data["workflow_version"]

      # Get current workflow version
      current_version = Versioning.get_version(VersionedWorkflow)

      # They should match (no code changes)
      assert Versioning.verify_version(stored_version, current_version) == {:ok, :match}

      # Simulate a code change by comparing with a different version
      fake_new_version = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

      assert {:error, :mismatch, _} =
               Versioning.verify_version(stored_version, fake_new_version)
    end

    test "helper function to verify replay compatibility" do
      # This tests the pattern that ReplayEngine would use

      # Start an execution
      {:ok, pid} = Engine.start_link(workflow_module: VersionedWorkflow, inputs: %{})
      status = Engine.get_status(pid)
      execution_id = status.execution_id

      # Wait for completion
      Process.sleep(100)
      EventStore.flush()
      Process.sleep(50)

      # Simulate ReplayEngine verification
      {:ok, events} = EventStore.get_events(execution_id)
      execution_started = Enum.find(events, fn e -> e.event_type == "ExecutionStartedEvent" end)

      event_version = execution_started.event_data["workflow_version"]
      current_version = Versioning.get_version(VersionedWorkflow)

      # Verify compatibility
      case Versioning.verify_version(event_version, current_version) do
        {:ok, :match} ->
          # Versions match - safe to replay
          assert true

        {:error, :mismatch, details} ->
          # Versions don't match - should warn
          IO.warn(
            "Workflow version mismatch. " <>
              "Execution: #{details.expected}, Current: #{details.actual}"
          )

          flunk("Expected versions to match")
      end
    end
  end
end
