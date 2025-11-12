defmodule Cerebelum.FlowActionTest do
  use ExUnit.Case, async: true

  alias Cerebelum.FlowAction
  alias Cerebelum.FlowAction.{Continue, BackTo, SkipTo, Failed}

  describe "continue/0" do
    test "creates Continue action" do
      action = FlowAction.continue()

      assert %Continue{} = action
    end

    test "Continue action is recognized" do
      action = FlowAction.continue()

      assert FlowAction.continue?(action)
      refute FlowAction.back_to?(action)
      refute FlowAction.skip_to?(action)
      refute FlowAction.failed?(action)
    end
  end

  describe "back_to/1" do
    test "creates BackTo action with step" do
      action = FlowAction.back_to(:validate_order)

      assert %BackTo{step: :validate_order} = action
    end

    test "BackTo action is recognized" do
      action = FlowAction.back_to(:some_step)

      assert FlowAction.back_to?(action)
      refute FlowAction.continue?(action)
    end

    test "raises if step is not provided" do
      assert_raise ArgumentError, fn ->
        struct!(BackTo, %{})
      end
    end
  end

  describe "skip_to/1" do
    test "creates SkipTo action with step" do
      action = FlowAction.skip_to(:finalize)

      assert %SkipTo{step: :finalize} = action
    end

    test "SkipTo action is recognized" do
      action = FlowAction.skip_to(:some_step)

      assert FlowAction.skip_to?(action)
      refute FlowAction.continue?(action)
    end
  end

  describe "failed/1" do
    test "creates Failed action with reason" do
      action = FlowAction.failed(:timeout)

      assert %Failed{reason: :timeout} = action
    end

    test "Failed action with complex reason" do
      action = FlowAction.failed({:validation_error, "Invalid email"})

      assert %Failed{reason: {:validation_error, "Invalid email"}} = action
    end

    test "Failed action is recognized" do
      action = FlowAction.failed(:some_reason)

      assert FlowAction.failed?(action)
      refute FlowAction.continue?(action)
    end
  end

  describe "is_flow_action?/1" do
    test "returns true for all flow actions" do
      assert FlowAction.is_flow_action?(FlowAction.continue())
      assert FlowAction.is_flow_action?(FlowAction.back_to(:step))
      assert FlowAction.is_flow_action?(FlowAction.skip_to(:step))
      assert FlowAction.is_flow_action?(FlowAction.failed(:reason))
    end

    test "returns false for non-flow-actions" do
      refute FlowAction.is_flow_action?(%{})
      refute FlowAction.is_flow_action?(:atom)
      refute FlowAction.is_flow_action?("string")
      refute FlowAction.is_flow_action?(123)
    end
  end

  describe "pattern matching in functions" do
    test "can pattern match on Continue" do
      action = FlowAction.continue()

      result = case action do
        %Continue{} -> :matched_continue
        _ -> :no_match
      end

      assert result == :matched_continue
    end

    test "can pattern match on BackTo and extract step" do
      action = FlowAction.back_to(:validate)

      result = case action do
        %BackTo{step: step} -> {:back_to, step}
        _ -> :no_match
      end

      assert result == {:back_to, :validate}
    end

    test "can pattern match on SkipTo and extract step" do
      action = FlowAction.skip_to(:finalize)

      result = case action do
        %SkipTo{step: step} -> {:skip_to, step}
        _ -> :no_match
      end

      assert result == {:skip_to, :finalize}
    end

    test "can pattern match on Failed and extract reason" do
      action = FlowAction.failed(:timeout)

      result = case action do
        %Failed{reason: reason} -> {:failed, reason}
        _ -> :no_match
      end

      assert result == {:failed, :timeout}
    end
  end
end
