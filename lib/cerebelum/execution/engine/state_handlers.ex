defmodule Cerebelum.Execution.Engine.StateHandlers do
  @moduledoc """
  State handler functions for the execution engine.

  This module contains all the gen_statem state functions that handle
  different execution states and their transitions.
  """

  require Logger

  alias Cerebelum.Execution.Engine.Data
  alias Cerebelum.Execution.StepExecutor
  alias Cerebelum.Execution.ErrorInfo
  alias Cerebelum.Execution.{DivergeHandler, BranchHandler, JumpHandler}

  @doc """
  Handler for :initializing state.

  Handles entry, start event, and get_status calls.
  """
  def initializing(:enter, _old_state, data) do
    Logger.debug("Entering :initializing state")
    {:keep_state, data}
  end

  def initializing(:internal, :start, data) do
    Logger.info("Starting execution: #{data.context.execution_id}")

    # Update context to first step
    first_step = Data.current_step_name(data)
    data = Data.update_context_step(data, first_step)

    # Transition to executing first step
    {:next_state, :executing_step, data, [{:next_event, :internal, :execute}]}
  end

  def initializing({:call, from}, :get_status, data) do
    {:keep_state, data, [{:reply, from, Data.build_status(data, :initializing)}]}
  end

  @doc """
  Handler for :executing_step state.

  Handles entry, execute event, timeout, and get_status calls.
  Sets a 5-minute timeout for step execution.
  """
  def executing_step(:enter, _old_state, data) do
    step_name = Data.current_step_name(data)
    Logger.debug("Entering :executing_step state for step: #{step_name}")

    # Set timeout for step execution (5 minutes)
    {:keep_state, data, [{:state_timeout, 5 * 60 * 1000, :step_timeout}]}
  end

  def executing_step(:internal, :execute, data) do
    step_name = Data.current_step_name(data)
    Logger.info("Executing step: #{step_name}")

    # Delegate execution to StepExecutor
    result =
      StepExecutor.execute_step(
        data.context.workflow_module,
        step_name,
        data.current_step_index,
        data.context,
        data.workflow_metadata.timeline,
        data.results
      )

    case result do
      {:ok, step_result} ->
        handle_step_success(data, step_name, step_result)

      {:error, reason} ->
        handle_step_error(data, step_name, reason)
    end
  end

  def executing_step(:state_timeout, :step_timeout, data) do
    step_name = Data.current_step_name(data)
    error_info = ErrorInfo.from_timeout(step_name, data.context.execution_id)

    Logger.error("Step #{step_name} timed out after 5 minutes")
    Logger.error(ErrorInfo.format(error_info))

    data = Data.mark_failed(data, error_info)
    {:next_state, :failed, data}
  end

  def executing_step({:call, from}, :get_status, data) do
    {:keep_state, data, [{:reply, from, Data.build_status(data, :executing_step)}]}
  end

  @doc """
  Handler for :completed state.

  Handles entry and get_status calls.
  """
  def completed(:enter, _old_state, data) do
    Logger.info("Execution completed: #{data.context.execution_id}")
    {:keep_state, data}
  end

  def completed({:call, from}, :get_status, data) do
    {:keep_state, data, [{:reply, from, Data.build_status(data, :completed)}]}
  end

  @doc """
  Handler for :failed state.

  Logs the error and keeps the process alive so status can be queried.
  """
  def failed(:enter, _old_state, data) do
    Logger.error("Execution failed: #{data.context.execution_id}, error: #{inspect(data.error)}")
    {:keep_state, data}
  end

  def failed({:call, from}, :get_status, data) do
    {:keep_state, data, [{:reply, from, Data.build_status(data, :failed)}]}
  end

  ## Private Helpers

  defp handle_step_success(data, step_name, step_result) do
    # Store result
    data = Data.store_result(data, step_name, step_result)

    # Evaluate diverge (error handling)
    diverge_result = DivergeHandler.evaluate(data.workflow_metadata, step_name, step_result)

    case diverge_result do
      {:failed, reason} ->
        # Diverge says to fail
        error_info = ErrorInfo.from_diverge_failed(step_name, reason, data.context.execution_id)
        data = Data.mark_failed(data, error_info)
        {:next_state, :failed, data}

      {:back_to, target_step} ->
        # Diverge says to retry/loop back
        handle_jump(data, :back_to, target_step)

      {:skip_to, target_step} ->
        # Diverge says to skip (rare but supported)
        handle_jump(data, :skip_to, target_step)

      {:continue, _} ->
        # Diverge says continue, check branch
        handle_after_diverge(data, step_name, step_result)

      :no_diverge ->
        # No diverge defined, check branch
        handle_after_diverge(data, step_name, step_result)
    end
  end

  # Handle logic after diverge evaluation (branch or normal flow)
  defp handle_after_diverge(data, step_name, step_result) do
    # Evaluate branch (business logic routing)
    branch_result = BranchHandler.evaluate(data.workflow_metadata, step_name, step_result)

    case branch_result do
      {:skip_to, target_step} ->
        # Branch says to take a different path
        handle_jump(data, :skip_to, target_step)

      {:continue, _} ->
        # Branch says continue normally
        handle_normal_flow(data)

      :no_branch ->
        # No branch defined, continue normally
        handle_normal_flow(data)
    end
  end

  # Handle normal flow (advance to next step)
  defp handle_normal_flow(data) do
    # Advance to next step
    data = Data.advance_step(data)

    # Check if finished
    if Data.finished?(data) do
      Logger.info("Execution completed: #{data.context.execution_id}")
      {:next_state, :completed, data}
    else
      # Continue to next step
      next_step = Data.current_step_name(data)
      data = Data.update_context_step(data, next_step)

      {:next_state, :executing_step, data, [{:next_event, :internal, :execute}]}
    end
  end

  # Handle jumps (back_to, skip_to)
  defp handle_jump(data, jump_type, target_step) do
    case JumpHandler.jump_to_step(data, jump_type, target_step) do
      {:ok, new_data} ->
        # Update context to new step
        next_step = Data.current_step_name(new_data)
        new_data = Data.update_context_step(new_data, next_step)

        # Continue execution at new step
        {:next_state, :executing_step, new_data, [{:next_event, :internal, :execute}]}

      {:error, :step_not_found} ->
        # Target step doesn't exist
        error_info =
          ErrorInfo.from_invalid_jump(target_step, data.context.execution_id, "step_not_found")

        data = Data.mark_failed(data, error_info)
        {:next_state, :failed, data}

      {:error, :infinite_loop} ->
        # Too many iterations
        error_info =
          ErrorInfo.from_infinite_loop(data.current_step_index, data.context.execution_id)

        data = Data.mark_failed(data, error_info)
        {:next_state, :failed, data}
    end
  end

  defp handle_step_error(data, step_name, error_info) do
    Logger.error("Step #{step_name} failed: #{ErrorInfo.format(error_info)}")
    data = Data.mark_failed(data, error_info)
    {:next_state, :failed, data}
  end
end
