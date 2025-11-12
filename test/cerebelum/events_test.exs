defmodule Cerebelum.EventsTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Events
  alias Cerebelum.Events.{
    ExecutionStartedEvent,
    StepExecutedEvent,
    StepFailedEvent,
    DivergeTakenEvent,
    BranchTakenEvent,
    JumpExecutedEvent,
    ExecutionCompletedEvent,
    ExecutionFailedEvent
  }

  doctest Cerebelum.Events

  describe "ExecutionStartedEvent" do
    test "creates event with all required fields" do
      event = ExecutionStartedEvent.new("exec-123", MyWorkflow, %{user_id: 1}, 0)

      assert event.execution_id == "exec-123"
      assert event.workflow_module == MyWorkflow
      assert event.inputs == %{user_id: 1}
      assert event.version == 0
      assert is_binary(event.event_id)
      assert %DateTime{} = event.timestamp
    end

    test "creates event with optional fields" do
      event =
        ExecutionStartedEvent.new("exec-123", MyWorkflow, %{}, 0,
          correlation_id: "trace-1",
          tags: ["priority:high"],
          workflow_version: "1.0.0"
        )

      assert event.correlation_id == "trace-1"
      assert event.tags == ["priority:high"]
      assert event.workflow_version == "1.0.0"
    end

    test "serializes to JSON" do
      event = ExecutionStartedEvent.new("exec-123", MyWorkflow, %{user_id: 1}, 0)

      {:ok, json} = Jason.encode(event)
      assert is_binary(json)
    end

    test "round-trip serialization" do
      event = ExecutionStartedEvent.new("exec-123", MyWorkflow, %{user_id: 1}, 0)

      {:ok, json} = Jason.encode(event)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["execution_id"] == "exec-123"
      assert decoded["version"] == 0
    end
  end

  describe "StepExecutedEvent" do
    test "creates event with all fields" do
      event = StepExecutedEvent.new("exec-123", :step1, 0, [%{}, "arg1"], "result", 100, 1)

      assert event.execution_id == "exec-123"
      assert event.step_name == :step1
      assert event.step_index == 0
      assert event.args == [%{}, "arg1"]
      assert event.result == "result"
      assert event.duration_ms == 100
      assert event.version == 1
    end

    test "serializes to JSON" do
      event = StepExecutedEvent.new("exec-123", :step1, 0, [], "result", 50, 1)

      {:ok, json} = Jason.encode(event)
      assert is_binary(json)
    end
  end

  describe "StepFailedEvent" do
    test "creates event with error details" do
      event =
        StepFailedEvent.new(
          "exec-123",
          :step1,
          0,
          :exception,
          %RuntimeError{message: "boom"},
          "Exception in step :step1",
          1
        )

      assert event.execution_id == "exec-123"
      assert event.step_name == :step1
      assert event.error_kind == :exception
      assert event.error_message == "Exception in step :step1"
    end

    test "serializes to JSON" do
      event =
        StepFailedEvent.new(
          "exec-123",
          :step1,
          0,
          :timeout,
          :timeout,
          "Step timed out",
          1
        )

      {:ok, json} = Jason.encode(event)
      assert is_binary(json)
    end
  end

  describe "DivergeTakenEvent" do
    test "creates event for retry action" do
      event = DivergeTakenEvent.new("exec-123", :fetch_data, :timeout, :retry, :fetch_data, 1)

      assert event.execution_id == "exec-123"
      assert event.step_name == :fetch_data
      assert event.matched_pattern == :timeout
      assert event.action == :retry
      assert event.target_step == :fetch_data
    end

    test "creates event for failed action" do
      event = DivergeTakenEvent.new("exec-123", :step1, {:error, :critical}, :failed, nil, 1)

      assert event.action == :failed
      assert event.target_step == nil
    end

    test "serializes to JSON" do
      event = DivergeTakenEvent.new("exec-123", :step1, :timeout, :retry, :step1, 1)

      {:ok, json} = Jason.encode(event)
      assert is_binary(json)
    end
  end

  describe "BranchTakenEvent" do
    test "creates event with branch path" do
      event = BranchTakenEvent.new("exec-123", :calculate_risk, "score > 0.8", :skip_to, :high_risk, 1)

      assert event.execution_id == "exec-123"
      assert event.step_name == :calculate_risk
      assert event.condition == "score > 0.8"
      assert event.action == :skip_to
      assert event.target_step == :high_risk
    end

    test "serializes to JSON" do
      event = BranchTakenEvent.new("exec-123", :step1, "x > 5", :continue, nil, 1)

      {:ok, json} = Jason.encode(event)
      assert is_binary(json)
    end
  end

  describe "JumpExecutedEvent" do
    test "creates event for back_to jump" do
      event = JumpExecutedEvent.new("exec-123", :back_to, :step3, 2, :step1, 0, 1, 1)

      assert event.execution_id == "exec-123"
      assert event.jump_type == :back_to
      assert event.from_step == :step3
      assert event.from_index == 2
      assert event.to_step == :step1
      assert event.to_index == 0
      assert event.iteration == 1
    end

    test "creates event for skip_to jump" do
      event = JumpExecutedEvent.new("exec-123", :skip_to, :step1, 0, :step5, 4, 0, 1)

      assert event.jump_type == :skip_to
      assert event.iteration == 0
    end

    test "serializes to JSON" do
      event = JumpExecutedEvent.new("exec-123", :back_to, :step2, 1, :step1, 0, 1, 1)

      {:ok, json} = Jason.encode(event)
      assert is_binary(json)
    end
  end

  describe "ExecutionCompletedEvent" do
    test "creates event with results and stats" do
      results = %{step1: {:ok, "r1"}, step2: {:ok, "r2"}}
      event = ExecutionCompletedEvent.new("exec-123", results, 2, 500, 0, 3)

      assert event.execution_id == "exec-123"
      assert event.results == results
      assert event.total_steps == 2
      assert event.total_duration_ms == 500
      assert event.iteration == 0
      assert event.version == 3
    end

    test "serializes to JSON" do
      event = ExecutionCompletedEvent.new("exec-123", %{}, 0, 0, 0, 1)

      {:ok, json} = Jason.encode(event)
      assert is_binary(json)
    end
  end

  describe "ExecutionFailedEvent" do
    test "creates event with error and partial results" do
      partial = %{step1: {:ok, "r1"}}

      event =
        ExecutionFailedEvent.new(
          "exec-123",
          :exception,
          %RuntimeError{message: "boom"},
          "Execution failed",
          :step2,
          partial,
          2
        )

      assert event.execution_id == "exec-123"
      assert event.error_kind == :exception
      assert event.error_message == "Execution failed"
      assert event.failed_step == :step2
      assert event.partial_results == partial
    end

    test "serializes to JSON" do
      event = ExecutionFailedEvent.new("exec-123", :timeout, :timeout, "Timed out", :step1, %{}, 1)

      {:ok, json} = Jason.encode(event)
      assert is_binary(json)
    end
  end

  describe "event_type/1" do
    test "returns event type name for each event" do
      assert Events.event_type(%ExecutionStartedEvent{}) == "ExecutionStartedEvent"
      assert Events.event_type(%StepExecutedEvent{}) == "StepExecutedEvent"
      assert Events.event_type(%StepFailedEvent{}) == "StepFailedEvent"
      assert Events.event_type(%DivergeTakenEvent{}) == "DivergeTakenEvent"
      assert Events.event_type(%BranchTakenEvent{}) == "BranchTakenEvent"
      assert Events.event_type(%JumpExecutedEvent{}) == "JumpExecutedEvent"
      assert Events.event_type(%ExecutionCompletedEvent{}) == "ExecutionCompletedEvent"
      assert Events.event_type(%ExecutionFailedEvent{}) == "ExecutionFailedEvent"
    end
  end

  describe "serialize/1" do
    test "converts event to map" do
      event = ExecutionStartedEvent.new("exec-123", MyWorkflow, %{}, 0)
      map = Events.serialize(event)

      assert is_map(map)
      assert map.execution_id == "exec-123"
      assert map.workflow_module == MyWorkflow
    end
  end

  describe "deserialize/2" do
    test "converts map to event struct" do
      data = %{
        "event_id" => "evt-123",
        "execution_id" => "exec-123",
        "workflow_module" => "MyWorkflow",
        "workflow_version" => "1.0.0",
        "inputs" => %{},
        "correlation_id" => nil,
        "tags" => [],
        "timestamp" => DateTime.utc_now(),
        "version" => 0
      }

      event = Events.deserialize("ExecutionStartedEvent", data)

      assert %ExecutionStartedEvent{} = event
      assert event.execution_id == "exec-123"
    end
  end

  describe "round-trip serialization for all events" do
    test "ExecutionStartedEvent" do
      original = ExecutionStartedEvent.new("exec-123", MyWorkflow, %{user: 1}, 0)

      {:ok, json} = Jason.encode(original)
      {:ok, decoded_map} = Jason.decode(json)

      # Can reconstruct basic data
      assert decoded_map["execution_id"] == original.execution_id
      assert decoded_map["version"] == original.version
    end

    test "StepExecutedEvent" do
      original = StepExecutedEvent.new("exec-123", :step1, 0, [], "result", 100, 1)

      {:ok, json} = Jason.encode(original)
      {:ok, decoded_map} = Jason.decode(json)

      assert decoded_map["execution_id"] == original.execution_id
      assert decoded_map["step_name"] == "step1"
      assert decoded_map["version"] == original.version
    end

    test "DivergeTakenEvent" do
      original = DivergeTakenEvent.new("exec-123", :step1, :timeout, :retry, :step1, 1)

      {:ok, json} = Jason.encode(original)
      {:ok, decoded_map} = Jason.decode(json)

      assert decoded_map["execution_id"] == original.execution_id
      assert decoded_map["action"] == "retry"
    end

    test "BranchTakenEvent" do
      original = BranchTakenEvent.new("exec-123", :step1, "x > 5", :skip_to, :step3, 1)

      {:ok, json} = Jason.encode(original)
      {:ok, decoded_map} = Jason.decode(json)

      assert decoded_map["execution_id"] == original.execution_id
      assert decoded_map["condition"] == "x > 5"
    end

    test "JumpExecutedEvent" do
      original = JumpExecutedEvent.new("exec-123", :back_to, :step3, 2, :step1, 0, 1, 1)

      {:ok, json} = Jason.encode(original)
      {:ok, decoded_map} = Jason.decode(json)

      assert decoded_map["execution_id"] == original.execution_id
      assert decoded_map["jump_type"] == "back_to"
    end

    test "ExecutionCompletedEvent" do
      original = ExecutionCompletedEvent.new("exec-123", %{step1: "r1"}, 1, 500, 0, 2)

      {:ok, json} = Jason.encode(original)
      {:ok, decoded_map} = Jason.decode(json)

      assert decoded_map["execution_id"] == original.execution_id
      assert decoded_map["total_steps"] == 1
    end

    test "ExecutionFailedEvent" do
      original =
        ExecutionFailedEvent.new("exec-123", :timeout, :timeout, "Timed out", :step1, %{}, 1)

      {:ok, json} = Jason.encode(original)
      {:ok, decoded_map} = Jason.decode(json)

      assert decoded_map["execution_id"] == original.execution_id
      assert decoded_map["error_kind"] == "timeout"
    end
  end
end
