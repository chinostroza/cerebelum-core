defmodule Cerebelum.EventTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Event
  alias Cerebelum.Event.{
    ExecutionStarted,
    StepStarted,
    StepCompleted,
    StepFailed,
    ExecutionCompleted,
    ExecutionFailed,
    CheckpointCreated
  }

  describe "execution_started/3" do
    test "creates ExecutionStarted event" do
      event = Event.execution_started("exec-123", MyWorkflow, %{order_id: "123"})

      assert %ExecutionStarted{} = event
      assert event.execution_id == "exec-123"
      assert event.workflow_module == MyWorkflow
      assert event.inputs == %{order_id: "123"}
      assert %DateTime{} = event.occurred_at
    end

    test "sets occurred_at to current time" do
      before = DateTime.utc_now()
      event = Event.execution_started("exec-123", MyWorkflow, %{})
      after_time = DateTime.utc_now()

      assert DateTime.compare(event.occurred_at, before) in [:gt, :eq]
      assert DateTime.compare(event.occurred_at, after_time) in [:lt, :eq]
    end
  end

  describe "step_started/2" do
    test "creates StepStarted event" do
      event = Event.step_started("exec-123", :validate_order)

      assert %StepStarted{} = event
      assert event.execution_id == "exec-123"
      assert event.step_name == :validate_order
      assert %DateTime{} = event.occurred_at
    end
  end

  describe "step_completed/3" do
    test "creates StepCompleted event with result" do
      result = %{valid: true, order_id: "123"}
      event = Event.step_completed("exec-123", :validate_order, result)

      assert %StepCompleted{} = event
      assert event.execution_id == "exec-123"
      assert event.step_name == :validate_order
      assert event.result == result
      assert %DateTime{} = event.occurred_at
    end

    test "accepts any result type" do
      event1 = Event.step_completed("exec-123", :step1, "string result")
      event2 = Event.step_completed("exec-123", :step2, 123)
      event3 = Event.step_completed("exec-123", :step3, [:list, :of, :atoms])

      assert event1.result == "string result"
      assert event2.result == 123
      assert event3.result == [:list, :of, :atoms]
    end
  end

  describe "step_failed/3 and step_failed/4" do
    test "creates StepFailed event with error" do
      event = Event.step_failed("exec-123", :charge_payment, :payment_declined)

      assert %StepFailed{} = event
      assert event.execution_id == "exec-123"
      assert event.step_name == :charge_payment
      assert event.error == :payment_declined
      assert event.stacktrace == nil
      assert %DateTime{} = event.occurred_at
    end

    test "accepts stacktrace as 4th argument" do
      stacktrace = [{Module, :func, 2, [file: "file.ex", line: 10]}]
      event = Event.step_failed("exec-123", :step, :error, stacktrace)

      assert event.stacktrace == stacktrace
    end
  end

  describe "execution_completed/2" do
    test "creates ExecutionCompleted event" do
      final_result = %{order_id: "123", status: :confirmed}
      event = Event.execution_completed("exec-123", final_result)

      assert %ExecutionCompleted{} = event
      assert event.execution_id == "exec-123"
      assert event.final_result == final_result
      assert %DateTime{} = event.occurred_at
    end
  end

  describe "execution_failed/3" do
    test "creates ExecutionFailed event" do
      event = Event.execution_failed("exec-123", :payment_declined, :charge_payment)

      assert %ExecutionFailed{} = event
      assert event.execution_id == "exec-123"
      assert event.reason == :payment_declined
      assert event.failed_step == :charge_payment
      assert %DateTime{} = event.occurred_at
    end
  end

  describe "checkpoint_created/4" do
    test "creates CheckpointCreated event" do
      context = %{workflow_module: MyWorkflow, execution_id: "exec-123"}
      results_cache = %{validate: %{valid: true}}

      event = Event.checkpoint_created("exec-123", :validate, context, results_cache)

      assert %CheckpointCreated{} = event
      assert event.execution_id == "exec-123"
      assert event.step_name == :validate
      assert event.context == context
      assert event.results_cache == results_cache
      assert %DateTime{} = event.occurred_at
    end
  end

  describe "execution_event?/1" do
    test "returns true for execution events" do
      assert Event.execution_event?(Event.execution_started("id", Mod, %{}))
      assert Event.execution_event?(Event.execution_completed("id", %{}))
      assert Event.execution_event?(Event.execution_failed("id", :reason, :step))
    end

    test "returns false for step events" do
      refute Event.execution_event?(Event.step_started("id", :step))
      refute Event.execution_event?(Event.step_completed("id", :step, %{}))
      refute Event.execution_event?(Event.step_failed("id", :step, :error))
    end

    test "returns false for checkpoint events" do
      refute Event.execution_event?(Event.checkpoint_created("id", :step, %{}, %{}))
    end

    test "returns false for non-events" do
      refute Event.execution_event?(%{})
      refute Event.execution_event?(:atom)
      refute Event.execution_event?("string")
    end
  end

  describe "step_event?/1" do
    test "returns true for step events" do
      assert Event.step_event?(Event.step_started("id", :step))
      assert Event.step_event?(Event.step_completed("id", :step, %{}))
      assert Event.step_event?(Event.step_failed("id", :step, :error))
    end

    test "returns false for execution events" do
      refute Event.step_event?(Event.execution_started("id", Mod, %{}))
      refute Event.step_event?(Event.execution_completed("id", %{}))
      refute Event.step_event?(Event.execution_failed("id", :reason, :step))
    end

    test "returns false for checkpoint events" do
      refute Event.step_event?(Event.checkpoint_created("id", :step, %{}, %{}))
    end
  end

  describe "pattern matching" do
    test "can match on ExecutionStarted" do
      event = Event.execution_started("id", MyMod, %{data: 1})

      result = case event do
        %ExecutionStarted{workflow_module: mod, inputs: inputs} ->
          {mod, inputs}
        _ ->
          :no_match
      end

      assert result == {MyMod, %{data: 1}}
    end

    test "can match on StepCompleted and extract result" do
      event = Event.step_completed("id", :validate, %{valid: true})

      result = case event do
        %StepCompleted{step_name: name, result: res} ->
          {name, res}
        _ ->
          :no_match
      end

      assert result == {:validate, %{valid: true}}
    end

    test "can distinguish between step outcomes" do
      completed = Event.step_completed("id", :step, %{})
      failed = Event.step_failed("id", :step, :error)

      completed_result = case completed do
        %StepCompleted{} -> :success
        %StepFailed{} -> :failure
        _ -> :unknown
      end

      failed_result = case failed do
        %StepCompleted{} -> :success
        %StepFailed{} -> :failure
        _ -> :unknown
      end

      assert completed_result == :success
      assert failed_result == :failure
    end
  end
end
