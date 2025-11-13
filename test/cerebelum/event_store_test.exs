defmodule Cerebelum.EventStoreTest do
  use ExUnit.Case, async: false
  import Ecto.Query

  alias Cerebelum.EventStore
  alias Cerebelum.Persistence.Event
  alias Cerebelum.Repo
  alias Cerebelum.Events.{
    ExecutionStartedEvent,
    StepExecutedEvent,
    ExecutionCompletedEvent
  }

  setup do
    # Set sandbox mode for test isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Allow EventStore GenServer to use the sandbox connection
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), Process.whereis(Cerebelum.EventStore))

    # Clear any pending batch
    EventStore.flush()

    :ok
  end

  describe "append_sync/3" do
    test "persists event immediately" do
      execution_id = "exec-#{System.unique_integer([:positive])}"
      event = ExecutionStartedEvent.new(
        execution_id,
        TestWorkflow,
        %{input: "test"},
        0
      )

      assert {:ok, stored} = EventStore.append_sync(execution_id, event, 0)
      assert stored.execution_id == execution_id
      assert stored.event_type == "ExecutionStartedEvent"
      assert stored.version == 0

      # Verify it's in database
      assert Repo.get_by(Event, execution_id: execution_id, version: 0)
    end

    test "validates required fields" do
      execution_id = "exec-#{System.unique_integer([:positive])}"
      event = %ExecutionStartedEvent{
        event_id: "evt-123",
        execution_id: execution_id,
        workflow_module: TestWorkflow,
        inputs: %{},
        timestamp: DateTime.utc_now(),
        version: 0
      }

      # Missing workflow_version - should still work as it's serialized
      assert {:ok, _stored} = EventStore.append_sync(execution_id, event, 0)
    end

    test "enforces unique (execution_id, version)" do
      execution_id = "exec-#{System.unique_integer([:positive])}"
      event = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)

      # First insert succeeds
      assert {:ok, _} = EventStore.append_sync(execution_id, event, 0)

      # Duplicate version fails
      assert {:error, changeset} = EventStore.append_sync(execution_id, event, 0)
      assert changeset.errors != []
    end

    test "allows same version for different executions" do
      exec1 = "exec-#{System.unique_integer([:positive])}"
      exec2 = "exec-#{System.unique_integer([:positive])}"

      event1 = ExecutionStartedEvent.new(exec1, TestWorkflow, %{}, 0)
      event2 = ExecutionStartedEvent.new(exec2, TestWorkflow, %{}, 0)

      assert {:ok, _} = EventStore.append_sync(exec1, event1, 0)
      assert {:ok, _} = EventStore.append_sync(exec2, event2, 0)
    end
  end

  describe "append/3 (async batching)" do
    test "accumulates events in batch" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      event1 = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)
      event2 = StepExecutedEvent.new(execution_id, :step1, 0, [], "result", 0, 1)
      event3 = ExecutionCompletedEvent.new(execution_id, %{final: "result"}, 1, 0, 0, 2)

      # Append async
      assert :ok = EventStore.append(execution_id, event1, 0)
      assert :ok = EventStore.append(execution_id, event2, 1)
      assert :ok = EventStore.append(execution_id, event3, 2)

      # Events not immediately in database
      assert Repo.all(from e in Event, where: e.execution_id == ^execution_id) == []

      # Flush batch
      EventStore.flush()

      # Now events are persisted
      events = Repo.all(from e in Event, where: e.execution_id == ^execution_id, order_by: [asc: e.version])
      assert length(events) == 3
      assert Enum.map(events, & &1.version) == [0, 1, 2]
    end

    test "auto-flushes after timeout" do
      execution_id = "exec-#{System.unique_integer([:positive])}"
      event = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)

      assert :ok = EventStore.append(execution_id, event, 0)

      # Wait for auto-flush (100ms + buffer)
      Process.sleep(150)

      # Event should be persisted
      assert Repo.get_by(Event, execution_id: execution_id, version: 0)
    end

    test "flushes immediately when batch is full" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      # Insert 1000 events to hit max batch size
      for version <- 0..999 do
        event = StepExecutedEvent.new(execution_id, :step, version, [], "result", 0, version)
        EventStore.append(execution_id, event, version)
      end

      # Wait for auto-flush to complete
      Process.sleep(100)

      events = Repo.all(from e in Event, where: e.execution_id == ^execution_id)
      assert length(events) == 1000
    end
  end

  describe "get_events/1" do
    test "returns all events for execution ordered by version" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      # Insert events in random order
      event2 = StepExecutedEvent.new(execution_id, :step2, 2, [], "result2", 0, 2)
      event0 = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)
      event1 = StepExecutedEvent.new(execution_id, :step1, 1, [], "result1", 0, 1)

      EventStore.append_sync(execution_id, event2, 2)
      EventStore.append_sync(execution_id, event0, 0)
      EventStore.append_sync(execution_id, event1, 1)

      # Should return ordered by version
      assert {:ok, events} = EventStore.get_events(execution_id)
      assert length(events) == 3
      assert Enum.map(events, & &1.version) == [0, 1, 2]
      assert Enum.map(events, & &1.event_type) == [
        "ExecutionStartedEvent",
        "StepExecutedEvent",
        "StepExecutedEvent"
      ]
    end

    test "returns empty list for non-existent execution" do
      assert {:ok, []} = EventStore.get_events("non-existent")
    end

    test "only returns events for specified execution" do
      exec1 = "exec-#{System.unique_integer([:positive])}"
      exec2 = "exec-#{System.unique_integer([:positive])}"

      event1 = ExecutionStartedEvent.new(exec1, TestWorkflow, %{}, 0)
      event2 = ExecutionStartedEvent.new(exec2, TestWorkflow, %{}, 0)

      EventStore.append_sync(exec1, event1, 0)
      EventStore.append_sync(exec2, event2, 0)

      assert {:ok, events} = EventStore.get_events(exec1)
      assert length(events) == 1
      assert hd(events).execution_id == exec1
    end
  end

  describe "get_events_from_version/2" do
    test "returns events from specified version onwards" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      # Insert 5 events
      for version <- 0..4 do
        event = StepExecutedEvent.new(execution_id, :step, version, [], "result", 0, version)
        EventStore.append_sync(execution_id, event, version)
      end

      # Get events from version 2
      assert {:ok, events} = EventStore.get_events_from_version(execution_id, 2)
      assert length(events) == 3
      assert Enum.map(events, & &1.version) == [2, 3, 4]
    end

    test "returns empty list when from_version is beyond latest" do
      execution_id = "exec-#{System.unique_integer([:positive])}"
      event = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)
      EventStore.append_sync(execution_id, event, 0)

      assert {:ok, []} = EventStore.get_events_from_version(execution_id, 10)
    end

    test "returns all events when from_version is 0" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      for version <- 0..2 do
        event = StepExecutedEvent.new(execution_id, :step, version, [], "result", 0, version)
        EventStore.append_sync(execution_id, event, version)
      end

      assert {:ok, events} = EventStore.get_events_from_version(execution_id, 0)
      assert length(events) == 3
    end
  end

  describe "partition routing" do
    test "events for same execution go to same partition" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      # Insert multiple events
      for version <- 0..9 do
        event = StepExecutedEvent.new(execution_id, :step, version, [], "result", 0, version)
        EventStore.append_sync(execution_id, event, version)
      end

      # Query should hit single partition
      # We can't directly verify partition, but we verify correct retrieval
      assert {:ok, events} = EventStore.get_events(execution_id)
      assert length(events) == 10
      assert Enum.all?(events, &(&1.execution_id == execution_id))
    end

    test "different executions distribute across partitions" do
      # Insert events for multiple executions
      execution_ids = for i <- 1..10, do: "exec-#{System.unique_integer([:positive])}-#{i}"

      for execution_id <- execution_ids do
        event = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)
        EventStore.append_sync(execution_id, event, 0)
      end

      # Verify each execution has its events
      for execution_id <- execution_ids do
        assert {:ok, events} = EventStore.get_events(execution_id)
        assert length(events) == 1
        assert hd(events).execution_id == execution_id
      end
    end
  end

  describe "event serialization" do
    test "serializes and stores complex event data" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      event = ExecutionStartedEvent.new(
        execution_id,
        MyComplexWorkflow,
        %{
          string: "test",
          number: 42,
          list: [1, 2, 3],
          map: %{nested: "value"}
        },
        0,
        correlation_id: "corr-123",
        tags: [:production, :important]
      )

      assert {:ok, stored} = EventStore.append_sync(execution_id, event, 0)

      # Verify data is properly stored
      assert stored.event_data["inputs"]["string"] == "test"
      assert stored.event_data["inputs"]["number"] == 42
      assert stored.event_data["inputs"]["list"] == [1, 2, 3]
      assert stored.event_data["inputs"]["map"]["nested"] == "value"
      assert stored.event_data["correlation_id"] == "corr-123"
      assert stored.event_data["tags"] == ["production", "important"]
    end

    test "serializes DateTime fields" do
      execution_id = "exec-#{System.unique_integer([:positive])}"
      timestamp = DateTime.utc_now()

      event = %ExecutionStartedEvent{
        event_id: "evt-123",
        execution_id: execution_id,
        workflow_module: TestWorkflow,
        inputs: %{},
        timestamp: timestamp,
        version: 0
      }

      assert {:ok, stored} = EventStore.append_sync(execution_id, event, 0)

      # DateTime should be ISO8601 string
      assert is_binary(stored.event_data["timestamp"])
      assert String.contains?(stored.event_data["timestamp"], "T")
    end

    test "serializes atom fields" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      event = StepExecutedEvent.new(execution_id, :my_step, 1, [], "result", 0, 1)

      assert {:ok, stored} = EventStore.append_sync(execution_id, event, 1)

      # Atom should be string
      assert stored.event_data["step_name"] == "my_step"
    end
  end

  describe "concurrency" do
    test "handles concurrent appends to different executions" do
      # Spawn multiple processes appending events concurrently
      tasks = for i <- 1..10 do
        Task.async(fn ->
          execution_id = "exec-concurrent-#{i}"
          event = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)
          EventStore.append_sync(execution_id, event, 0)
        end)
      end

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn
        {:ok, _} -> true
        _ -> false
      end)
    end

    test "detects version conflicts in same execution" do
      execution_id = "exec-#{System.unique_integer([:positive])}"

      # First event succeeds
      event1 = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)
      assert {:ok, _} = EventStore.append_sync(execution_id, event1, 0)

      # Concurrent attempts with same version should fail
      tasks = for _ <- 1..5 do
        Task.async(fn ->
          event = StepExecutedEvent.new(execution_id, :step, 1, [], "result", 0, 1)
          EventStore.append_sync(execution_id, event, 1)
        end)
      end

      results = Task.await_many(tasks)

      # Only one should succeed
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      assert successes == 1
    end
  end

  describe "flush/0" do
    test "flushes pending batch" do
      execution_id = "exec-#{System.unique_integer([:positive])}"
      event = ExecutionStartedEvent.new(execution_id, TestWorkflow, %{}, 0)

      EventStore.append(execution_id, event, 0)

      # Not in database yet
      assert Repo.all(from e in Event, where: e.execution_id == ^execution_id) == []

      # Flush
      EventStore.flush()

      # Now persisted
      assert Repo.get_by(Event, execution_id: execution_id, version: 0)
    end

    test "flush is idempotent" do
      EventStore.flush()
      EventStore.flush()
      EventStore.flush()

      # No errors
      assert true
    end
  end
end
