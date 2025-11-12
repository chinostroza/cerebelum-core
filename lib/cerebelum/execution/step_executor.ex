defmodule Cerebelum.Execution.StepExecutor do
  @moduledoc """
  Executes individual workflow steps.

  This module handles:
  - Building function arguments (context + previous results)
  - Executing step functions via apply/3
  - Error handling and exception catching
  - Result validation
  """

  require Logger

  alias Cerebelum.Execution.ErrorInfo

  @doc """
  Executes a specific step in the workflow.

  ## Parameters

  - `workflow_module` - The workflow module
  - `step_name` - The step function to execute
  - `step_index` - Index in the timeline (for argument building)
  - `context` - Current execution context
  - `timeline` - Full timeline list
  - `results` - Map of previous step results

  ## Returns

  - `{:ok, result}` - Step executed successfully
  - `{:error, reason}` - Step failed
  """
  @spec execute_step(module(), atom(), non_neg_integer(), map(), list(atom()), map()) ::
          {:ok, term()} | {:error, term()}
  def execute_step(workflow_module, step_name, step_index, context, timeline, results) do
    Logger.debug("Executing step: #{step_name} (index: #{step_index})")

    # Build arguments for this step
    args = build_arguments(context, step_index, timeline, results)

    # Execute the step function
    try do
      result = apply(workflow_module, step_name, args)
      Logger.debug("Step #{step_name} completed with result: #{inspect(result)}")
      {:ok, result}
    rescue
      exception ->
        error_info = ErrorInfo.from_exception(step_name, exception, __STACKTRACE__, context.execution_id)
        Logger.error("Step #{step_name} raised exception: #{Exception.message(exception)}")
        Logger.debug("Stacktrace: #{Exception.format_stacktrace(error_info.stacktrace)}")
        {:error, error_info}
    catch
      :exit, reason ->
        error_info = ErrorInfo.from_exit(step_name, reason, context.execution_id)
        Logger.error("Step #{step_name} caught exit: #{inspect(reason)}")
        {:error, error_info}

      :throw, value ->
        error_info = ErrorInfo.from_throw(step_name, value, context.execution_id)
        Logger.error("Step #{step_name} caught throw: #{inspect(value)}")
        {:error, error_info}
    end
  end

  @doc """
  Builds the argument list for a step function.

  The first argument is always the context.
  Subsequent arguments are the results of previous steps in order.

  ## Examples

      # For step at index 0 (first step):
      build_arguments(ctx, 0, [:step1, :step2], %{})
      #=> [ctx]

      # For step at index 1 (second step):
      build_arguments(ctx, 1, [:step1, :step2], %{step1: {:ok, 1}})
      #=> [ctx, {:ok, 1}]

      # For step at index 2 (third step):
      build_arguments(ctx, 2, [:a, :b, :c], %{a: 1, b: 2})
      #=> [ctx, 1, 2]
  """
  @spec build_arguments(map(), non_neg_integer(), list(atom()), map()) :: list()
  def build_arguments(context, step_index, timeline, results) do
    # First argument is always the context
    context_arg = context

    # Get previous step names (all steps before current index)
    previous_step_names = Enum.take(timeline, step_index)

    # Get their results in order
    previous_results =
      Enum.map(previous_step_names, fn step_name ->
        Map.get(results, step_name)
      end)

    [context_arg | previous_results]
  end

  @doc """
  Validates that a step function exists with the correct arity.

  ## Parameters

  - `workflow_module` - The workflow module
  - `step_name` - The step function name
  - `expected_arity` - Expected number of arguments

  ## Returns

  - `:ok` - Function exists with correct arity
  - `{:error, reason}` - Function missing or wrong arity
  """
  @spec validate_step_function(module(), atom(), non_neg_integer()) ::
          :ok | {:error, term()}
  def validate_step_function(workflow_module, step_name, expected_arity) do
    cond do
      not function_exported?(workflow_module, step_name, expected_arity) ->
        {:error, {:function_not_found, {step_name, expected_arity}}}

      true ->
        :ok
    end
  end
end
