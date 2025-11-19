defmodule Cerebelum.Persistence.EventTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Persistence.Event
  alias Cerebelum.Events.{ExecutionStartedEvent, StepExecutedEvent}

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        execution_id: "exec-123",
        event_type: "ExecutionStartedEvent",
        event_data: %{workflow_module: "MyWorkflow"},
        version: 0
      }

      changeset = Event.changeset(%Event{}, attrs)

      assert changeset.valid?
      assert changeset.changes.execution_id == "exec-123"
      assert changeset.changes.event_type == "ExecutionStartedEvent"
      assert changeset.changes.version == 0
    end

    test "validates required fields" do
      changeset = Event.changeset(%Event{}, %{})

      refute changeset.valid?
      assert %{execution_id: ["can't be blank"]} = errors_on(changeset)
      assert %{event_type: ["can't be blank"]} = errors_on(changeset)
      assert %{event_data: ["can't be blank"]} = errors_on(changeset)
      assert %{version: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates version is non-negative" do
      attrs = %{
        execution_id: "exec-123",
        event_type: "ExecutionStartedEvent",
        event_data: %{},
        version: -1
      }

      changeset = Event.changeset(%Event{}, attrs)

      refute changeset.valid?
      assert %{version: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "validates execution_id length" do
      attrs = %{
        execution_id: "",
        event_type: "ExecutionStartedEvent",
        event_data: %{},
        version: 0
      }

      changeset = Event.changeset(%Event{}, attrs)

      refute changeset.valid?
      # Empty string triggers "can't be blank" validation first
      assert %{execution_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates event_type length" do
      attrs = %{
        execution_id: "exec-123",
        event_type: "",
        event_data: %{},
        version: 0
      }

      changeset = Event.changeset(%Event{}, attrs)

      refute changeset.valid?
      # Empty string triggers "can't be blank" validation first
      assert %{event_type: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "from_domain_event/1" do
    test "converts ExecutionStartedEvent to persistence event" do
      domain_event = ExecutionStartedEvent.new(
        "exec-123",
        TestWorkflow,
        %{input: "test"},
        0,
        correlation_id: "corr-123"
      )

      event = Event.from_domain_event(domain_event)

      assert event.execution_id == "exec-123"
      assert event.event_type == "ExecutionStartedEvent"
      assert event.version == 0
      assert is_map(event.event_data)
      assert event.event_data["workflow_module"] == "Elixir.TestWorkflow"
    end

    test "converts StepExecutedEvent to persistence event" do
      domain_event = StepExecutedEvent.new(
        "exec-123",
        :my_step,
        0,
        [],
        {:ok, %{result: "success"}},
        100,
        1
      )

      event = Event.from_domain_event(domain_event)

      assert event.execution_id == "exec-123"
      assert event.event_type == "StepExecutedEvent"
      assert event.version == 1
      assert event.event_data["step_name"] == "my_step"
    end

    test "serializes nested maps" do
      domain_event = ExecutionStartedEvent.new(
        "exec-123",
        TestWorkflow,
        %{nested: %{deep: %{value: 42}}},
        0
      )

      event = Event.from_domain_event(domain_event)

      assert event.event_data["inputs"]["nested"]["deep"]["value"] == 42
    end

    test "serializes DateTime values" do
      now = DateTime.utc_now()
      domain_event = %ExecutionStartedEvent{
        event_id: "evt-123",
        execution_id: "exec-123",
        workflow_module: TestWorkflow,
        workflow_version: "abc",
        inputs: %{},
        correlation_id: nil,
        tags: [],
        timestamp: now,
        version: 0
      }

      event = Event.from_domain_event(domain_event)

      assert is_binary(event.event_data["timestamp"])
      assert String.contains?(event.event_data["timestamp"], "Z")
    end

    test "serializes tuples as lists" do
      domain_event = StepExecutedEvent.new(
        "exec-123",
        :my_step,
        0,
        [],
        {:ok, {:nested, :tuple}},
        100,
        1
      )

      event = Event.from_domain_event(domain_event)

      # Tuples are converted to lists for JSON serialization
      assert is_list(event.event_data["result"])
    end

    test "serializes exceptions" do
      error = %RuntimeError{message: "Something went wrong"}
      domain_event = %StepExecutedEvent{
        event_id: "evt-123",
        execution_id: "exec-123",
        step_name: :failing_step,
        step_index: 0,
        args: [],
        result: {:error, error},
        duration_ms: 50,
        timestamp: DateTime.utc_now(),
        version: 1
      }

      event = Event.from_domain_event(domain_event)

      # Exception should be serialized with __exception__ marker
      result_data = event.event_data["result"]
      assert is_list(result_data)
      [_error_atom, error_data] = result_data
      assert error_data["__exception__"]
      assert error_data["message"] == "Something went wrong"
    end
  end

  describe "to_domain_event/1" do
    test "converts persistence event back to ExecutionStartedEvent" do
      persistence_event = %Event{
        execution_id: "exec-123",
        event_type: "ExecutionStartedEvent",
        event_data: %{
          "event_id" => "evt-123",
          "execution_id" => "exec-123",
          "workflow_module" => "TestWorkflow",
          "workflow_version" => "abc123",
          "inputs" => %{},
          "correlation_id" => nil,
          "tags" => [],
          "timestamp" => "2024-01-01T00:00:00Z",
          "version" => 0
        },
        version: 0
      }

      domain_event = Event.to_domain_event(persistence_event)

      assert domain_event.__struct__ == ExecutionStartedEvent
      assert domain_event.execution_id == "exec-123"
      assert domain_event.version == 0
    end

    test "converts persistence event back to StepExecutedEvent" do
      persistence_event = %Event{
        execution_id: "exec-123",
        event_type: "StepExecutedEvent",
        event_data: %{
          "event_id" => "evt-123",
          "execution_id" => "exec-123",
          "step_name" => "my_step",
          "step_index" => 0,
          "args" => [],
          "result" => ["ok", %{"value" => 42}],
          "duration_ms" => 100,
          "timestamp" => "2024-01-01T00:00:00Z",
          "version" => 1
        },
        version: 1
      }

      domain_event = Event.to_domain_event(persistence_event)

      assert domain_event.__struct__ == StepExecutedEvent
      assert domain_event.execution_id == "exec-123"
      # Atoms are serialized as strings, so they remain strings after deserialization
      assert domain_event.step_name == "my_step"
    end
  end

  # Helper function to extract errors from changeset
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
