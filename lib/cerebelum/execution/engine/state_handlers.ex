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
  alias Cerebelum.Execution.{DivergeHandler, BranchHandler, JumpHandler, ParallelExecutor}
  alias Cerebelum.Execution.EventEmitter

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

    # Emit ExecutionStartedEvent (sync)
    {version, data} = Data.next_event_version(data)
    EventEmitter.emit_execution_started(data, version)

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

    # Emit ExecutionCompletedEvent (sync)
    {version, data} = Data.next_event_version(data)
    EventEmitter.emit_execution_completed(data, 0, version)

    {:keep_state, data}
  end

  def completed({:call, from}, :get_status, data) do
    {:keep_state, data, [{:reply, from, Data.build_status(data, :completed)}]}
  end

  # Ignore unexpected messages in completed state (e.g., delayed task completions)
  def completed(:info, _msg, data) do
    {:keep_state, data}
  end

  @doc """
  Handler for :failed state.

  Logs the error and keeps the process alive so status can be queried.
  """
  def failed(:enter, _old_state, data) do
    Logger.error("Execution failed: #{data.context.execution_id}, error: #{inspect(data.error)}")

    # Emit ExecutionFailedEvent (sync)
    {version, data} = Data.next_event_version(data)
    EventEmitter.emit_execution_failed(data, data.error, 0, version)

    {:keep_state, data}
  end

  def failed({:call, from}, :get_status, data) do
    {:keep_state, data, [{:reply, from, Data.build_status(data, :failed)}]}
  end

  ## Private Helpers

  defp handle_step_success(data, step_name, step_result) do
    # Check if step wants special execution (parallel, sleep, approval, etc.)
    case step_result do
      {:parallel, tasks} when is_list(tasks) ->
        handle_parallel_execution(data, step_name, tasks)

      {:parallel, tasks, _initial_state} when is_list(tasks) ->
        handle_parallel_execution(data, step_name, tasks)

      {:sleep, opts, result} when is_list(opts) ->
        handle_sleep_request(data, step_name, opts, result)

      {:sleep, opts} when is_list(opts) ->
        handle_sleep_request(data, step_name, opts, nil)

      {:wait_for_approval, opts, approval_data} when is_list(opts) ->
        handle_approval_request(data, step_name, opts, approval_data)

      {:wait_for_approval, opts} when is_list(opts) ->
        handle_approval_request(data, step_name, opts, %{})

      _ ->
        # Normal step execution - continue with regular flow
        handle_regular_step_success(data, step_name, step_result)
    end
  end

  defp handle_regular_step_success(data, step_name, step_result) do
    # Store result
    data = Data.store_result(data, step_name, step_result)

    # Emit StepExecutedEvent (async batched)
    {version, data} = Data.next_event_version(data)
    EventEmitter.emit_step_executed(data, step_name, step_result, 0, version)

    # Evaluate diverge (error handling)
    diverge_result = DivergeHandler.evaluate(data.workflow_metadata, step_name, step_result)

    case diverge_result do
      {:failed, reason} ->
        # Diverge says to fail
        {version, data} = Data.next_event_version(data)
        EventEmitter.emit_diverge_taken(data, step_name, :failed, nil, version)

        error_info = ErrorInfo.from_diverge_failed(step_name, reason, data.context.execution_id)
        data = Data.mark_failed(data, error_info)
        {:next_state, :failed, data}

      {:back_to, target_step} ->
        # Diverge says to retry/loop back
        {version, data} = Data.next_event_version(data)
        EventEmitter.emit_diverge_taken(data, step_name, :back_to, target_step, version)

        handle_jump(data, :back_to, target_step)

      {:skip_to, target_step} ->
        # Diverge says to skip (rare but supported)
        {version, data} = Data.next_event_version(data)
        EventEmitter.emit_diverge_taken(data, step_name, :skip_to, target_step, version)

        handle_jump(data, :skip_to, target_step)

      {:continue, _} ->
        # Diverge says continue, check branch
        {version, data} = Data.next_event_version(data)
        EventEmitter.emit_diverge_taken(data, step_name, :continue, nil, version)

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
        {version, data} = Data.next_event_version(data)
        EventEmitter.emit_branch_taken(data, step_name, "condition_met", target_step, version)

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
    from_step = Data.current_step_name(data)

    case JumpHandler.jump_to_step(data, jump_type, target_step) do
      {:ok, new_data} ->
        # Emit JumpExecutedEvent (async batched)
        {version, new_data} = Data.next_event_version(new_data)
        EventEmitter.emit_jump_executed(new_data, jump_type, from_step, target_step, version)

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

    # Emit StepFailedEvent (async batched)
    {version, data} = Data.next_event_version(data)
    EventEmitter.emit_step_failed(data, error_info, version)

    data = Data.mark_failed(data, error_info)
    {:next_state, :failed, data}
  end

  defp handle_parallel_execution(data, step_name, tasks) do
    Logger.info("Step #{step_name} requested parallel execution of #{length(tasks)} tasks")

    # Get current version for parallel events
    {version, data} = Data.next_event_version(data)

    # Execute tasks in parallel
    result =
      ParallelExecutor.execute_parallel(
        data.context.workflow_module,
        tasks,
        data.context,
        step_name,
        data.context.execution_id,
        initial_version: version
      )

    case result do
      {:ok, merged_results, final_version} ->
        # All tasks succeeded
        Logger.info("Parallel execution completed successfully")

        # Update data with new version
        data = %{data | event_version: final_version}

        # Store the merged results as the step result
        data = Data.store_result(data, step_name, {:ok, merged_results})

        # Continue with normal flow (check diverge, branch, etc.)
        handle_regular_step_success(data, step_name, {:ok, merged_results})

      {:error, reason, _partial_results, final_version} ->
        # Some tasks failed
        Logger.error("Parallel execution failed: #{inspect(reason)}")

        # Update data with new version
        data = %{data | event_version: final_version}

        # Create error info for the parallel execution failure
        error_info =
          ErrorInfo.from_exception(
            step_name,
            %RuntimeError{message: "Parallel execution failed: #{inspect(reason)}"},
            [],
            data.context.execution_id
          )

        data = Data.mark_failed(data, error_info)
        {:next_state, :failed, data}
    end
  end

  defp handle_sleep_request(data, step_name, opts, result) do
    # Extract sleep duration
    duration_ms =
      cond do
        Keyword.has_key?(opts, :milliseconds) ->
          Keyword.fetch!(opts, :milliseconds)

        Keyword.has_key?(opts, :seconds) ->
          Keyword.fetch!(opts, :seconds) * 1000

        Keyword.has_key?(opts, :minutes) ->
          Keyword.fetch!(opts, :minutes) * 60 * 1000

        true ->
          raise ArgumentError, "Sleep requires :milliseconds, :seconds, or :minutes option"
      end

    Logger.info("Step #{step_name} requested sleep for #{duration_ms}ms")

    # Store the step result if provided
    data = if result != nil do
      Data.store_result(data, step_name, result)
    else
      data
    end

    # Emit StepExecutedEvent with sleep result
    {version, data} = Data.next_event_version(data)
    EventEmitter.emit_step_executed(data, step_name, {:sleep, duration_ms, result}, 0, version)

    # Prepare data for sleeping state
    data = %{data |
      sleep_duration_ms: duration_ms,
      sleep_started_at: System.monotonic_time(:millisecond),
      sleep_step_name: step_name,
      sleep_result: result
    }

    # Transition to sleeping state
    {:next_state, :sleeping, data}
  end

  @doc """
  Handler for :sleeping state.

  Uses state_timeout to wake up without blocking the process.
  """
  def sleeping(:enter, _old_state, data) do
    Logger.info("Entering :sleeping state for #{data.sleep_duration_ms}ms")

    # Emit SleepStartedEvent
    {version, data} = Data.next_event_version(data)

    event =
      Cerebelum.Events.SleepStartedEvent.new(
        data.context.execution_id,
        data.sleep_step_name,
        data.sleep_duration_ms,
        version
      )

    Cerebelum.EventStore.append(data.context.execution_id, event, version)

    # Check if should hibernate (for long sleeps)
    should_hibernate = should_hibernate_workflow?(data)

    if should_hibernate do
      # Hibernate: persist state and terminate process
      Logger.info(
        "Hibernating workflow #{data.context.execution_id} for #{data.sleep_duration_ms}ms"
      )

      # Calculate resume_at time
      resume_at = DateTime.add(DateTime.utc_now(), data.sleep_duration_ms, :millisecond)

      # Create pause record in database
      :ok = record_hibernation_pause(data, resume_at)

      # Emit WorkflowHibernatedEvent
      {hibernate_version, data} = Data.next_event_version(data)

      hibernate_event =
        Cerebelum.Events.WorkflowHibernatedEvent.new(
          data.context.execution_id,
          data.sleep_step_name,
          "sleep",
          resume_at,
          hibernate_version
        )

      Cerebelum.EventStore.append_sync(data.context.execution_id, hibernate_event, hibernate_version)

      # Terminate process gracefully (will be resurrected by scheduler)
      {:stop, :normal, data}
    else
      # Normal in-memory sleep (current behavior)
      {:keep_state, data, [{:state_timeout, data.sleep_duration_ms, :wake_up}]}
    end
  end

  def sleeping(:state_timeout, :wake_up, data) do
    # Calculate actual sleep duration
    actual_duration = System.monotonic_time(:millisecond) - data.sleep_started_at

    Logger.info("Waking up from sleep (actual: #{actual_duration}ms)")

    # Emit SleepCompletedEvent
    {version, data} = Data.next_event_version(data)

    event =
      Cerebelum.Events.SleepCompletedEvent.new(
        data.context.execution_id,
        actual_duration,
        version
      )

    Cerebelum.EventStore.append(data.context.execution_id, event, version)

    # Clear sleep data
    data = %{data |
      sleep_duration_ms: nil,
      sleep_started_at: nil,
      sleep_step_name: nil,
      sleep_result: nil
    }

    # Advance to next step
    data = Data.advance_step(data)

    # Check if finished
    if Data.finished?(data) do
      Logger.info("Execution completed after sleep: #{data.context.execution_id}")
      {:next_state, :completed, data}
    else
      # Continue to next step
      next_step = Data.current_step_name(data)
      data = Data.update_context_step(data, next_step)
      {:next_state, :executing_step, data, [{:next_event, :internal, :execute}]}
    end
  end

  def sleeping({:call, from}, :get_status, data) do
    status = Data.build_status(data, :sleeping)

    # Add sleep info to status
    status_with_sleep =
      Map.merge(status, %{
        sleep_duration_ms: data.sleep_duration_ms,
        sleep_elapsed_ms: System.monotonic_time(:millisecond) - data.sleep_started_at,
        sleep_remaining_ms:
          data.sleep_duration_ms - (System.monotonic_time(:millisecond) - data.sleep_started_at)
      })

    {:keep_state, data, [{:reply, from, status_with_sleep}]}
  end

  @doc """
  Handler for :waiting_for_approval state.

  Handles entry, approval responses, timeout, and get_status calls.
  """
  def waiting_for_approval(:enter, _old_state, data) do
    Logger.info("Entering :waiting_for_approval state for step: #{data.approval_step_name}")

    # Emit ApprovalRequestedEvent
    {version, data} = Data.next_event_version(data)

    event =
      Cerebelum.Events.ApprovalRequestedEvent.new(
        data.context.execution_id,
        data.approval_step_name,
        data.approval_type,
        data.approval_data,
        data.approval_timeout_ms,
        version
      )

    Cerebelum.EventStore.append(data.context.execution_id, event, version)

    # Set state timeout if configured
    timeout_action =
      if data.approval_timeout_ms do
        [{:state_timeout, data.approval_timeout_ms, :approval_timeout}]
      else
        []
      end

    {:keep_state, data, timeout_action}
  end

  def waiting_for_approval({:call, from}, {:approve, approval_response}, data) do
    Logger.info("Approval received for step: #{data.approval_step_name}")

    # Calculate elapsed time
    elapsed_ms = System.monotonic_time(:millisecond) - data.approval_started_at

    # Emit ApprovalReceivedEvent
    {version, data} = Data.next_event_version(data)

    event =
      Cerebelum.Events.ApprovalReceivedEvent.new(
        data.context.execution_id,
        data.approval_step_name,
        approval_response,
        elapsed_ms,
        version
      )

    Cerebelum.EventStore.append(data.context.execution_id, event, version)

    # Clear approval data
    data = %{data |
      approval_type: nil,
      approval_data: nil,
      approval_step_name: nil,
      approval_timeout_ms: nil,
      approval_started_at: nil
    }

    # Advance to next step
    data = Data.advance_step(data)

    # Reply to caller
    reply_action = {:reply, from, {:ok, :approved}}

    # Check if finished
    if Data.finished?(data) do
      Logger.info("Execution completed after approval: #{data.context.execution_id}")
      {:next_state, :completed, data, [reply_action]}
    else
      # Continue to next step
      next_step = Data.current_step_name(data)
      data = Data.update_context_step(data, next_step)
      {:next_state, :executing_step, data, [reply_action, {:next_event, :internal, :execute}]}
    end
  end

  def waiting_for_approval({:call, from}, {:reject, rejection_reason}, data) do
    Logger.warning("Approval rejected for step: #{data.approval_step_name}, reason: #{inspect(rejection_reason)}")

    # Calculate elapsed time
    elapsed_ms = System.monotonic_time(:millisecond) - data.approval_started_at

    # Emit ApprovalRejectedEvent
    {version, data} = Data.next_event_version(data)

    event =
      Cerebelum.Events.ApprovalRejectedEvent.new(
        data.context.execution_id,
        data.approval_step_name,
        rejection_reason,
        elapsed_ms,
        version
      )

    Cerebelum.EventStore.append(data.context.execution_id, event, version)

    # Create error info for rejection
    error_info =
      ErrorInfo.from_approval_rejected(
        data.approval_step_name,
        rejection_reason,
        data.context.execution_id
      )

    data = Data.mark_failed(data, error_info)

    # Reply to caller
    reply_action = {:reply, from, {:ok, :rejected}}

    {:next_state, :failed, data, [reply_action]}
  end

  def waiting_for_approval(:state_timeout, :approval_timeout, data) do
    Logger.error("Approval timeout for step: #{data.approval_step_name} after #{data.approval_timeout_ms}ms")

    # Emit ApprovalTimeoutEvent
    {version, data} = Data.next_event_version(data)

    event =
      Cerebelum.Events.ApprovalTimeoutEvent.new(
        data.context.execution_id,
        data.approval_step_name,
        data.approval_timeout_ms,
        version
      )

    Cerebelum.EventStore.append(data.context.execution_id, event, version)

    # Create error info for timeout
    error_info =
      ErrorInfo.from_approval_timeout(
        data.approval_step_name,
        data.approval_timeout_ms,
        data.context.execution_id
      )

    data = Data.mark_failed(data, error_info)
    {:next_state, :failed, data}
  end

  def waiting_for_approval({:call, from}, :get_status, data) do
    status = Data.build_status(data, :waiting_for_approval)

    # Add approval info to status
    status_with_approval =
      Map.merge(status, %{
        approval_type: data.approval_type,
        approval_data: data.approval_data,
        approval_step_name: data.approval_step_name,
        approval_timeout_ms: data.approval_timeout_ms,
        approval_elapsed_ms: System.monotonic_time(:millisecond) - data.approval_started_at,
        approval_remaining_ms:
          if data.approval_timeout_ms do
            data.approval_timeout_ms - (System.monotonic_time(:millisecond) - data.approval_started_at)
          else
            nil
          end
      })

    {:keep_state, data, [{:reply, from, status_with_approval}]}
  end

  ## Private Helpers (continued)

  defp handle_approval_request(data, step_name, opts, approval_data) do
    # Extract approval options
    approval_type = Keyword.get(opts, :type, :manual)

    timeout_ms =
      cond do
        Keyword.has_key?(opts, :timeout_ms) ->
          Keyword.fetch!(opts, :timeout_ms)

        Keyword.has_key?(opts, :timeout_seconds) ->
          Keyword.fetch!(opts, :timeout_seconds) * 1000

        Keyword.has_key?(opts, :timeout_minutes) ->
          Keyword.fetch!(opts, :timeout_minutes) * 60 * 1000

        true ->
          nil
      end

    Logger.info("Step #{step_name} requested approval (type: #{approval_type})")

    # Store the approval_data as the step result (so next steps can access it)
    data = Data.store_result(data, step_name, {:waiting_for_approval, approval_data})

    # Emit StepExecutedEvent for consistency
    {version, data} = Data.next_event_version(data)
    EventEmitter.emit_step_executed(data, step_name, {:waiting_for_approval, approval_data}, 0, version)

    # Prepare data for waiting_for_approval state
    data = %{data |
      approval_type: approval_type,
      approval_data: approval_data,
      approval_step_name: step_name,
      approval_timeout_ms: timeout_ms,
      approval_started_at: System.monotonic_time(:millisecond)
    }

    # Transition to waiting_for_approval state
    {:next_state, :waiting_for_approval, data}
  end

  ## Private Helpers for Hibernation

  # Determines if a workflow should be hibernated based on configuration
  defp should_hibernate_workflow?(data) do
    enabled = Application.get_env(:cerebelum_core, :enable_workflow_hibernation, false)
    threshold = Application.get_env(:cerebelum_core, :hibernation_threshold_ms, 3_600_000)

    # Hibernate if:
    # 1. Hibernation is enabled in config
    # 2. Sleep duration exceeds threshold (default: 1 hour)
    enabled and data.sleep_duration_ms >= threshold
  end

  # Records hibernation pause in the database
  defp record_hibernation_pause(data, resume_at) do
    pause_attrs = %{
      execution_id: data.context.execution_id,
      workflow_module: to_string(data.context.workflow_module),
      pause_type: "sleep",
      resume_at: resume_at,
      hibernated: false,
      event_version: data.event_version,
      current_step_index: data.current_step_index,
      current_step_name: to_string(data.sleep_step_name),
      sleep_duration_ms: data.sleep_duration_ms,
      sleep_started_at: DateTime.utc_now()
    }

    case Cerebelum.Persistence.WorkflowPause.changeset(%Cerebelum.Persistence.WorkflowPause{}, pause_attrs)
         |> Cerebelum.Repo.insert() do
      {:ok, _pause} ->
        :ok

      {:error, changeset} ->
        Logger.error("Failed to create hibernation pause record: #{inspect(changeset)}")
        :ok  # Don't fail the workflow, just log
    end
  end
end
