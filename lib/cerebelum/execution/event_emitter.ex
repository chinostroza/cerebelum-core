defmodule Cerebelum.Execution.EventEmitter do
  @moduledoc """
  Emits domain events to the EventStore during workflow execution.

  This module is responsible for creating and persisting events that
  capture the complete history of a workflow execution. Events are
  emitted at key points in the execution lifecycle.

  ## Event Types

  - `ExecutionStartedEvent` - When execution begins (sync)
  - `StepExecutedEvent` - When a step completes successfully (async)
  - `StepFailedEvent` - When a step fails (async)
  - `DivergeTakenEvent` - When a diverge path is taken (async)
  - `BranchTakenEvent` - When a branch path is taken (async)
  - `JumpExecutedEvent` - When a jump is executed (async)
  - `ExecutionCompletedEvent` - When execution completes (sync)
  - `ExecutionFailedEvent` - When execution fails (sync)

  ## Sync vs Async

  Critical lifecycle events (started, completed, failed) are persisted
  synchronously to ensure they are immediately durable. Intermediate
  events (steps, diverge, branch, jump) are batched for performance.
  """

  alias Cerebelum.EventStore
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
  alias Cerebelum.Execution.Engine.Data

  @doc """
  Emits an ExecutionStartedEvent synchronously.

  ## Parameters

  - `data` - Execution data
  - `version` - Event version number

  ## Returns

  `:ok` if event was persisted successfully, `{:error, reason}` otherwise.
  """
  @spec emit_execution_started(Data.t(), non_neg_integer()) :: :ok | {:error, term()}
  def emit_execution_started(data, version) do
    if event_store_available?() do
      event = ExecutionStartedEvent.new(
        data.context.execution_id,
        data.context.workflow_module,
        data.context.inputs,
        version,
        correlation_id: data.context.correlation_id,
        tags: data.context.tags,
        workflow_version: data.workflow_metadata.version
      )

      case EventStore.append_sync(data.context.execution_id, event, version) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  rescue
    # If EventStore crashes during operation, silently ignore
    _ -> :ok
  end

  @doc """
  Emits a StepExecutedEvent asynchronously (batched).

  ## Parameters

  - `data` - Execution data
  - `step_name` - Name of the executed step
  - `step_result` - Result of the step execution
  - `duration_ms` - Execution duration in milliseconds
  - `version` - Event version number

  ## Returns

  `:ok`
  """
  @spec emit_step_executed(Data.t(), atom(), term(), non_neg_integer(), non_neg_integer()) :: :ok
  def emit_step_executed(data, step_name, step_result, duration_ms, version) do
    step_index = Enum.find_index(data.timeline, &(&1 == step_name)) || 0

    # Get step arguments from workflow metadata (functions have arity, not explicit args list)
    # For now we use empty args list
    args = []

    event = StepExecutedEvent.new(
      data.context.execution_id,
      step_name,
      step_index,
      args,
      step_result,
      duration_ms,
      version
    )

    EventStore.append(data.context.execution_id, event, version)
  end

  @doc """
  Emits a StepFailedEvent asynchronously (batched).

  ## Parameters

  - `data` - Execution data
  - `error_info` - ErrorInfo struct with failure details
  - `version` - Event version number

  ## Returns

  `:ok`
  """
  @spec emit_step_failed(Data.t(), Cerebelum.Execution.ErrorInfo.t(), non_neg_integer()) :: :ok
  def emit_step_failed(data, error_info, version) do
    step_index = Enum.find_index(data.timeline, &(&1 == error_info.step_name)) || 0

    event = StepFailedEvent.new(
      data.context.execution_id,
      error_info.step_name,
      step_index,
      error_info.kind,
      error_info.reason,
      Cerebelum.Execution.ErrorInfo.format(error_info),
      version
    )

    EventStore.append(data.context.execution_id, event, version)
  end

  @doc """
  Emits a DivergeTakenEvent asynchronously (batched).

  ## Parameters

  - `data` - Execution data
  - `from_step` - Step where diverge originated
  - `diverge_action` - Action taken (:retry, :continue, :failed, :back_to, :skip_to)
  - `target_step` - Target step for jump actions (if applicable)
  - `version` - Event version number

  ## Returns

  `:ok`
  """
  @spec emit_diverge_taken(Data.t(), atom(), atom(), atom() | nil, non_neg_integer()) :: :ok
  def emit_diverge_taken(data, from_step, diverge_action, target_step, version) do
    # matched_pattern is a placeholder - in a real scenario this would be the actual pattern that matched
    matched_pattern = :unknown

    event = DivergeTakenEvent.new(
      data.context.execution_id,
      from_step,
      matched_pattern,
      diverge_action,
      target_step,
      version
    )

    EventStore.append(data.context.execution_id, event, version)
  end

  @doc """
  Emits a BranchTakenEvent asynchronously (batched).

  ## Parameters

  - `data` - Execution data
  - `from_step` - Step where branch originated
  - `condition` - Condition that was evaluated
  - `target_step` - Target step to branch to
  - `version` - Event version number

  ## Returns

  `:ok`
  """
  @spec emit_branch_taken(Data.t(), atom(), String.t(), atom(), non_neg_integer()) :: :ok
  def emit_branch_taken(data, from_step, condition, target_step, version) do
    # action is :skip_to for branches
    action = :skip_to

    event = BranchTakenEvent.new(
      data.context.execution_id,
      from_step,
      condition,
      action,
      target_step,
      version
    )

    EventStore.append(data.context.execution_id, event, version)
  end

  @doc """
  Emits a JumpExecutedEvent asynchronously (batched).

  ## Parameters

  - `data` - Execution data
  - `jump_type` - Type of jump (:back_to or :skip_to)
  - `from_step` - Step where jump originated
  - `target_step` - Target step to jump to
  - `version` - Event version number

  ## Returns

  `:ok`
  """
  @spec emit_jump_executed(Data.t(), atom(), atom(), atom(), non_neg_integer()) :: :ok
  def emit_jump_executed(data, jump_type, from_step, target_step, version) do
    from_index = Enum.find_index(data.timeline, &(&1 == from_step)) || 0
    target_index = Enum.find_index(data.timeline, &(&1 == target_step)) || 0

    event = JumpExecutedEvent.new(
      data.context.execution_id,
      jump_type,
      from_step,
      from_index,
      target_step,
      target_index,
      data.iteration,
      version
    )

    EventStore.append(data.context.execution_id, event, version)
  end

  @doc """
  Emits an ExecutionCompletedEvent synchronously.

  ## Parameters

  - `data` - Execution data
  - `total_duration_ms` - Total execution duration in milliseconds
  - `version` - Event version number

  ## Returns

  `:ok` if event was persisted successfully, `{:error, reason}` otherwise.
  """
  @spec emit_execution_completed(Data.t(), non_neg_integer(), non_neg_integer()) :: :ok | {:error, term()}
  def emit_execution_completed(data, total_duration_ms, version) do
    if event_store_available?() do
      total_steps = length(data.timeline)

      event = ExecutionCompletedEvent.new(
        data.context.execution_id,
        data.results,
        total_steps,
        total_duration_ms,
        data.iteration,
        version
      )

      case EventStore.append_sync(data.context.execution_id, event, version) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  rescue
    # If EventStore crashes during operation, silently ignore
    _ -> :ok
  end

  @doc """
  Emits an ExecutionFailedEvent synchronously.

  ## Parameters

  - `data` - Execution data
  - `error_info` - ErrorInfo struct with failure details
  - `total_duration_ms` - Total execution duration before failure
  - `version` - Event version number

  ## Returns

  `:ok` if event was persisted successfully, `{:error, reason}` otherwise.
  """
  @spec emit_execution_failed(Data.t(), Cerebelum.Execution.ErrorInfo.t(), non_neg_integer(), non_neg_integer()) :: :ok | {:error, term()}
  def emit_execution_failed(data, error_info, total_duration_ms, version) do
    if event_store_available?() do
      event = ExecutionFailedEvent.new(
        data.context.execution_id,
        error_info.kind,
        error_info.reason,
        Cerebelum.Execution.ErrorInfo.format(error_info),
        error_info.step_name,
        total_duration_ms,
        version
      )

      case EventStore.append_sync(data.context.execution_id, event, version) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  rescue
    # If EventStore crashes during operation, silently ignore
    _ -> :ok
  end

  # Private Helpers

  defp event_store_available? do
    # Check if EventStore process is registered and alive
    case Process.whereis(EventStore) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end
end
