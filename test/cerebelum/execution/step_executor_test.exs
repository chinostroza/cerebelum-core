defmodule Cerebelum.Execution.StepExecutorTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Execution.StepExecutor
  alias Cerebelum.Context

  defmodule TestWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        step1() |> step2() |> step3()
      end
    end

    def step1(context) do
      {:ok, "result1_#{context.inputs[:id]}"}
    end

    def step2(_context, step1_result) do
      {:ok, "result2_with_#{inspect(step1_result)}"}
    end

    def step3(_context, step1_result, step2_result) do
      {:ok, "result3_with_#{inspect(step1_result)}_and_#{inspect(step2_result)}"}
    end
  end

  defmodule FailingWorkflow do
    use Cerebelum.Workflow

    workflow do
      timeline do
        good_step() |> failing_step()
      end
    end

    def good_step(_context) do
      {:ok, "success"}
    end

    def failing_step(_context, _prev) do
      raise "Intentional failure"
    end
  end

  describe "build_arguments/4" do
    setup do
      context = Context.new(TestWorkflow, %{user_id: 123})
      timeline = [:step1, :step2, :step3]
      {:ok, context: context, timeline: timeline}
    end

    test "builds args for first step (index 0)", %{context: context, timeline: timeline} do
      args = StepExecutor.build_arguments(context, 0, timeline, %{})

      assert length(args) == 1
      assert List.first(args) == context
    end

    test "builds args for second step (index 1)", %{context: context, timeline: timeline} do
      results = %{step1: {:ok, "result1"}}
      args = StepExecutor.build_arguments(context, 1, timeline, results)

      assert length(args) == 2
      assert Enum.at(args, 0) == context
      assert Enum.at(args, 1) == {:ok, "result1"}
    end

    test "builds args for third step (index 2)", %{context: context, timeline: timeline} do
      results = %{
        step1: {:ok, "result1"},
        step2: {:ok, "result2"}
      }
      args = StepExecutor.build_arguments(context, 2, timeline, results)

      assert length(args) == 3
      assert Enum.at(args, 0) == context
      assert Enum.at(args, 1) == {:ok, "result1"}
      assert Enum.at(args, 2) == {:ok, "result2"}
    end

    test "handles missing results gracefully", %{context: context, timeline: timeline} do
      # If a result is missing, it will be nil
      results = %{step1: {:ok, "result1"}}
      args = StepExecutor.build_arguments(context, 2, timeline, results)

      assert length(args) == 3
      assert Enum.at(args, 0) == context
      assert Enum.at(args, 1) == {:ok, "result1"}
      assert Enum.at(args, 2) == nil
    end
  end

  describe "execute_step/6" do
    setup do
      context = Context.new(TestWorkflow, %{id: "test123"})
      timeline = [:step1, :step2, :step3]
      {:ok, context: context, timeline: timeline}
    end

    test "executes first step successfully", %{context: context, timeline: timeline} do
      result = StepExecutor.execute_step(
        TestWorkflow,
        :step1,
        0,
        context,
        timeline,
        %{}
      )

      assert {:ok, {:ok, "result1_test123"}} = result
    end

    test "executes second step with previous result", %{context: context, timeline: timeline} do
      results = %{step1: {:ok, "previous"}}

      result = StepExecutor.execute_step(
        TestWorkflow,
        :step2,
        1,
        context,
        timeline,
        results
      )

      assert {:ok, {:ok, "result2_with_{:ok, \"previous\"}"}} = result
    end

    test "executes third step with all previous results", %{context: context, timeline: timeline} do
      results = %{
        step1: {:ok, "result1"},
        step2: {:ok, "result2"}
      }

      result = StepExecutor.execute_step(
        TestWorkflow,
        :step3,
        2,
        context,
        timeline,
        results
      )

      assert {:ok, {:ok, final_result}} = result
      assert is_binary(final_result)
      assert String.contains?(final_result, "result3")
    end

    test "catches exceptions and returns error", %{timeline: timeline} do
      alias Cerebelum.Execution.ErrorInfo

      context = Context.new(FailingWorkflow, %{})
      results = %{good_step: {:ok, "success"}}

      result = StepExecutor.execute_step(
        FailingWorkflow,
        :failing_step,
        1,
        context,
        timeline,
        results
      )

      assert {:error, %ErrorInfo{} = error} = result
      assert error.kind == :exception
      assert error.step_name == :failing_step
      assert %RuntimeError{} = error.reason
      assert is_list(error.stacktrace)
      assert error.execution_id == context.execution_id
    end

    test "passes context with inputs to step", %{timeline: timeline} do
      context = Context.new(TestWorkflow, %{id: "abc"})

      result = StepExecutor.execute_step(
        TestWorkflow,
        :step1,
        0,
        context,
        timeline,
        %{}
      )

      assert {:ok, {:ok, "result1_abc"}} = result
    end
  end

  describe "validate_step_function/3" do
    test "validates existing function with correct arity" do
      result = StepExecutor.validate_step_function(TestWorkflow, :step1, 1)
      assert result == :ok
    end

    test "validates function with multiple arguments" do
      result = StepExecutor.validate_step_function(TestWorkflow, :step2, 2)
      assert result == :ok
    end

    test "returns error for non-existent function" do
      result = StepExecutor.validate_step_function(TestWorkflow, :nonexistent, 1)
      assert {:error, {:function_not_found, {:nonexistent, 1}}} = result
    end

    test "returns error for wrong arity" do
      result = StepExecutor.validate_step_function(TestWorkflow, :step1, 2)
      assert {:error, {:function_not_found, {:step1, 2}}} = result
    end
  end

  describe "integration with real workflows" do
    test "can execute steps from CounterWorkflow" do
      alias Cerebelum.Examples.CounterWorkflow

      context = Context.new(CounterWorkflow, %{})
      timeline = [:initialize, :increment, :double, :finalize]

      # Execute initialize
      {:ok, result1} = StepExecutor.execute_step(CounterWorkflow, :initialize, 0, context, timeline, %{})
      assert result1 == {:ok, 0}

      # Execute increment
      results = %{initialize: result1}
      {:ok, result2} = StepExecutor.execute_step(CounterWorkflow, :increment, 1, context, timeline, results)
      assert result2 == {:ok, 1}

      # Execute double
      results = %{initialize: result1, increment: result2}
      {:ok, result3} = StepExecutor.execute_step(CounterWorkflow, :double, 2, context, timeline, results)
      assert result3 == {:ok, 2}

      # Execute finalize
      results = %{initialize: result1, increment: result2, double: result3}
      {:ok, result4} = StepExecutor.execute_step(CounterWorkflow, :finalize, 3, context, timeline, results)
      assert result4 == {:ok, 2}
    end
  end
end
