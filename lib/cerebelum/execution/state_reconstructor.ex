defmodule Cerebelum.Execution.StateReconstructor do
  @moduledoc """
  Reconstructs execution state from event history.

  This module implements event sourcing's core principle: state can be
  completely reconstructed by replaying events in order. This enables:

  - Debugging past executions by replaying their history
  - Time-travel debugging (state at any point in time)
  - Audit trails and compliance reporting
  - Recovery after crashes or data loss

  ## Usage

      # Reconstruct current state
      {:ok, state} = StateReconstructor.reconstruct(execution_id)

      # Reconstruct state up to a specific version
      {:ok, state} = StateReconstructor.reconstruct_to_version(execution_id, 10)

  ## Reconstructed State

  The reconstructed state includes:

  - `:execution_id` - Execution identifier
  - `:workflow_module` - Workflow module name
  - `:status` - Execution status (:running, :completed, :failed)
  - `:results` - Map of step results
  - `:current_step` - Current step name
  - `:timeline_progress` - Progress through timeline
  - `:iteration` - Loop iteration counter
  - `:error` - Error information (if failed)
  - `:events_applied` - Number of events replayed
  """

  require Logger
  alias Cerebelum.EventStore
  alias Cerebelum.Execution.Engine
  alias Cerebelum.Events.{
    ExecutionStartedEvent,
    StepExecutedEvent,
    StepFailedEvent,
    DivergeTakenEvent,
    BranchTakenEvent,
    JumpExecutedEvent,
    ExecutionCompletedEvent,
    ExecutionFailedEvent,
    SleepStartedEvent,
    SleepCompletedEvent,
    ApprovalRequestedEvent,
    ApprovalReceivedEvent,
    ApprovalRejectedEvent,
    ApprovalTimeoutEvent
  }

  @type reconstructed_state :: %{
          execution_id: String.t(),
          workflow_module: module() | String.t(),
          status: :running | :completed | :failed,
          results: map(),
          current_step: atom() | nil,
          current_step_index: non_neg_integer(),
          timeline_progress: String.t(),
          iteration: non_neg_integer(),
          error: map() | nil,
          events_applied: non_neg_integer(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil
        }

  @doc """
  Reconstructs the full execution state from all events.

  ## Parameters

  - `execution_id` - The execution ID to reconstruct

  ## Returns

  - `{:ok, state}` - Successfully reconstructed state
  - `{:error, :not_found}` - No events found for this execution
  - `{:error, reason}` - Other errors

  ## Examples

      iex> {:ok, state} = StateReconstructor.reconstruct("exec-123")
      iex> state.status
      :completed
      iex> state.results
      %{step1: {:ok, 1}, step2: {:ok, 2}}
  """
  @spec reconstruct(String.t()) :: {:ok, reconstructed_state()} | {:error, term()}
  def reconstruct(execution_id) do
    case EventStore.get_events(execution_id) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, events} ->
        domain_events = Enum.map(events, &Cerebelum.Persistence.Event.to_domain_event/1)
        state = apply_events(%{}, domain_events)
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reconstructs execution state up to a specific version.

  Useful for time-travel debugging or understanding state at a specific point.

  ## Parameters

  - `execution_id` - The execution ID to reconstruct
  - `to_version` - Version number to reconstruct up to (inclusive)

  ## Examples

      # See state after first 5 events
      {:ok, state} = StateReconstructor.reconstruct_to_version("exec-123", 4)
  """
  @spec reconstruct_to_version(String.t(), non_neg_integer()) ::
          {:ok, reconstructed_state()} | {:error, term()}
  def reconstruct_to_version(execution_id, to_version) do
    case EventStore.get_events(execution_id) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, events} ->
        filtered_events =
          events
          |> Enum.filter(&(&1.version <= to_version))
          |> Enum.map(&Cerebelum.Persistence.Event.to_domain_event/1)

        state = apply_events(%{}, filtered_events)
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reconstructs the full execution state as an Engine.Data struct for resumption.

  This function rebuilds the complete Engine.Data structure from events, including
  all state necessary for workflow resurrection after system restarts.

  ## Parameters

  - `execution_id` - The execution ID to reconstruct

  ## Returns

  - `{:ok, %Engine.Data{}}` - Successfully reconstructed engine data
  - `{:error, :not_found}` - No events found for this execution
  - `{:error, reason}` - Other errors

  ## Examples

      iex> {:ok, engine_data} = StateReconstructor.reconstruct_to_engine_data("exec-123")
      iex> engine_data.context.execution_id
      "exec-123"
      iex> engine_data.current_step_index
      5

  ## State Reconstruction

  The reconstructed Engine.Data includes:
  - Context with execution_id, workflow_module, inputs
  - Workflow metadata and timeline
  - Results cache with all step results
  - Current step index and iteration
  - Event version counter
  - Error state (if failed)
  - Sleep state (if sleeping): duration_ms, started_at, step_name, result
  - Approval state (if waiting): type, data, step_name, timeout_ms, started_at

  This enables seamless resumption of workflows after crashes or restarts.
  """
  @spec reconstruct_to_engine_data(String.t()) :: {:ok, Engine.Data.t()} | {:error, term()}
  def reconstruct_to_engine_data(execution_id) do
    case EventStore.get_events(execution_id) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, events} ->
        domain_events = Enum.map(events, &Cerebelum.Persistence.Event.to_domain_event/1)

        # Find the ExecutionStartedEvent to initialize
        case Enum.find(domain_events, &match?(%ExecutionStartedEvent{}, &1)) do
          nil ->
            {:error, :no_started_event}

          started_event ->
            # Initialize Engine.Data from the started event
            initial_data = initialize_engine_data(started_event)

            # Apply all events to reconstruct state
            reconstructed_data = apply_events_to_engine_data(initial_data, domain_events)

            {:ok, reconstructed_data}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Helpers

  # Initialize Engine.Data from ExecutionStartedEvent
  defp initialize_engine_data(%ExecutionStartedEvent{} = event) do
    # Load workflow metadata
    workflow_module =
      if is_binary(event.workflow_module) do
        # Handle both "MyModule" and "Elixir.MyModule" formats
        module_string =
          if String.starts_with?(event.workflow_module, "Elixir.") do
            event.workflow_module
          else
            "Elixir." <> event.workflow_module
          end

        String.to_existing_atom(module_string)
      else
        event.workflow_module
      end

    workflow_metadata = Cerebelum.Workflow.Metadata.extract(workflow_module)

    # Create context
    context = %Cerebelum.Context{
      execution_id: event.execution_id,
      workflow_module: workflow_module,
      workflow_version: event.workflow_version,
      inputs: event.inputs,
      started_at: event.timestamp,
      updated_at: event.timestamp,
      current_step: nil,
      correlation_id: event.correlation_id,
      tags: event.tags || []
    }

    # Initialize Engine.Data
    %Engine.Data{
      context: context,
      workflow_metadata: workflow_metadata,
      timeline: workflow_metadata.timeline,
      results: %{},
      current_step_index: 0,
      iteration: 0,
      event_version: 1,  # Started event is version 0, so we're at 1
      error: nil,
      sleep_duration_ms: nil,
      sleep_started_at: nil,
      sleep_step_name: nil,
      sleep_result: nil,
      approval_type: nil,
      approval_data: nil,
      approval_step_name: nil,
      approval_timeout_ms: nil,
      approval_started_at: nil
    }
  end

  # Apply events sequentially to reconstruct Engine.Data
  defp apply_events_to_engine_data(initial_data, events) do
    # Skip the ExecutionStartedEvent since we already processed it
    events
    |> Enum.reject(&match?(%ExecutionStartedEvent{}, &1))
    |> Enum.reduce(initial_data, &apply_event_to_engine_data/2)
  end

  # Apply individual events to Engine.Data
  defp apply_event_to_engine_data(%StepExecutedEvent{} = event, data) do
    step_name = atomize(event.step_name)
    result = reconstruct_result(event.result)

    data
    |> Engine.Data.store_result(step_name, result)
    |> Engine.Data.update_context_step(step_name)
    |> Engine.Data.update_current_step_index(event.step_index + 1)
    |> increment_event_version()
  end

  defp apply_event_to_engine_data(%StepFailedEvent{} = event, data) do
    error_info = %Cerebelum.Execution.ErrorInfo{
      kind: event.error_kind,
      reason: event.error_reason,
      step_name: atomize(event.step_name),
      execution_id: event.execution_id
    }

    data
    |> Engine.Data.mark_failed(error_info)
    |> Engine.Data.update_context_step(atomize(event.step_name))
    |> increment_event_version()
  end

  defp apply_event_to_engine_data(%JumpExecutedEvent{} = event, data) do
    data
    |> Engine.Data.update_current_step_index(event.to_index)
    |> Engine.Data.update_context_step(atomize(event.to_step))
    |> Map.put(:iteration, event.iteration)
    |> increment_event_version()
  end

  defp apply_event_to_engine_data(%SleepStartedEvent{} = event, data) do
    # Convert DateTime to milliseconds since epoch (wall clock time)
    started_at_ms = DateTime.to_unix(event.timestamp, :millisecond)

    %{data |
      sleep_duration_ms: event.duration_ms,
      sleep_started_at: started_at_ms,
      sleep_step_name: atomize(event.step_name),
      event_version: data.event_version + 1
    }
  end

  defp apply_event_to_engine_data(%SleepCompletedEvent{} = _event, data) do
    # Clear sleep state and advance step
    %{data |
      sleep_duration_ms: nil,
      sleep_started_at: nil,
      sleep_step_name: nil,
      sleep_result: nil,
      event_version: data.event_version + 1
    }
    |> Engine.Data.advance_step()
  end

  defp apply_event_to_engine_data(%ApprovalRequestedEvent{} = event, data) do
    # Convert DateTime to milliseconds since epoch (wall clock time)
    started_at_ms = DateTime.to_unix(event.timestamp, :millisecond)

    %{data |
      approval_type: event.approval_type,
      approval_data: event.approval_data,
      approval_step_name: atomize(event.step_name),
      approval_timeout_ms: event.timeout_ms,
      approval_started_at: started_at_ms,
      event_version: data.event_version + 1
    }
  end

  defp apply_event_to_engine_data(%ApprovalReceivedEvent{} = _event, data) do
    # Clear approval state and advance step
    %{data |
      approval_type: nil,
      approval_data: nil,
      approval_step_name: nil,
      approval_timeout_ms: nil,
      approval_started_at: nil,
      event_version: data.event_version + 1
    }
    |> Engine.Data.advance_step()
  end

  defp apply_event_to_engine_data(%ApprovalRejectedEvent{} = event, data) do
    # Approval rejected - mark as failed
    error_info = %Cerebelum.Execution.ErrorInfo{
      kind: :approval_rejected,
      reason: event.rejection_reason,
      step_name: atomize(event.step_name),
      execution_id: data.context.execution_id
    }

    %{data |
      approval_type: nil,
      approval_data: nil,
      approval_step_name: nil,
      approval_timeout_ms: nil,
      approval_started_at: nil,
      event_version: data.event_version + 1
    }
    |> Engine.Data.mark_failed(error_info)
  end

  defp apply_event_to_engine_data(%ApprovalTimeoutEvent{} = event, data) do
    # Approval timed out - mark as failed
    error_info = %Cerebelum.Execution.ErrorInfo{
      kind: :approval_timeout,
      reason: :timeout,
      step_name: atomize(event.step_name),
      execution_id: data.context.execution_id
    }

    %{data |
      approval_type: nil,
      approval_data: nil,
      approval_step_name: nil,
      approval_timeout_ms: nil,
      approval_started_at: nil,
      event_version: data.event_version + 1
    }
    |> Engine.Data.mark_failed(error_info)
  end

  defp apply_event_to_engine_data(%ExecutionCompletedEvent{} = event, data) do
    data
    |> Map.put(:iteration, event.iteration)
    |> increment_event_version()
  end

  defp apply_event_to_engine_data(%ExecutionFailedEvent{} = event, data) do
    error_info = %Cerebelum.Execution.ErrorInfo{
      kind: event.error_kind,
      reason: event.error_reason,
      step_name: if(event.failed_step, do: atomize(event.failed_step), else: nil),
      execution_id: event.execution_id
    }

    data
    |> Engine.Data.mark_failed(error_info)
    |> increment_event_version()
  end

  # Ignore other event types (DivergeTakenEvent, BranchTakenEvent, etc.)
  defp apply_event_to_engine_data(_event, data) do
    increment_event_version(data)
  end

  # Helper to increment event version
  defp increment_event_version(data) do
    %{data | event_version: data.event_version + 1}
  end

  # Private Helpers (existing)

  # Apply events in order to reconstruct state
  defp apply_events(initial_state, events) do
    Enum.reduce(events, initial_state, &apply_event/2)
  end

  # ExecutionStartedEvent - Initialize state
  defp apply_event(%ExecutionStartedEvent{} = event, _state) do
    %{
      execution_id: event.execution_id,
      workflow_module: event.workflow_module,
      status: :running,
      results: %{},
      current_step: nil,
      current_step_index: 0,
      timeline_progress: "0/?",
      iteration: 0,
      error: nil,
      events_applied: 1,
      started_at: event.timestamp,
      completed_at: nil,
      inputs: event.inputs,
      correlation_id: event.correlation_id,
      tags: event.tags
    }
  end

  # StepExecutedEvent - Store result and advance
  defp apply_event(%StepExecutedEvent{} = event, state) do
    # Ensure step_name is an atom (might be string after deserialization)
    step_name = atomize(event.step_name)
    # Reconstruct result tuple if it was serialized as list
    result = reconstruct_result(event.result)

    %{
      state
      | results: Map.put(state.results, step_name, result),
        current_step: step_name,
        current_step_index: event.step_index + 1,
        events_applied: state.events_applied + 1
    }
  end

  # StepFailedEvent - Mark failure
  defp apply_event(%StepFailedEvent{} = event, state) do
    error_info = %{
      kind: event.error_kind,
      step_name: event.step_name,
      reason: event.error_reason,
      message: event.error_message
    }

    %{
      state
      | status: :failed,
        error: error_info,
        current_step: event.step_name,
        events_applied: state.events_applied + 1
    }
  end

  # DivergeTakenEvent - Track diverge path
  defp apply_event(%DivergeTakenEvent{} = event, state) do
    # Diverge doesn't change step index, just tracks the path taken
    state = %{state | events_applied: state.events_applied + 1}

    case event.action do
      :failed ->
        # If diverge says to fail, mark as failed
        error_info = %{
          kind: :diverge_failed,
          step_name: event.step_name,
          reason: event.matched_pattern,
          message: "Diverge triggered failure at #{event.step_name}"
        }

        %{state | status: :failed, error: error_info}

      _ ->
        # For retry, continue, back_to, skip_to - just track
        state
    end
  end

  # BranchTakenEvent - Track branch path (doesn't change index yet)
  defp apply_event(%BranchTakenEvent{} = _event, state) do
    %{state | events_applied: state.events_applied + 1}
  end

  # JumpExecutedEvent - Update position and iteration
  defp apply_event(%JumpExecutedEvent{} = event, state) do
    %{
      state
      | current_step: event.to_step,
        current_step_index: event.to_index,
        iteration: event.iteration,
        events_applied: state.events_applied + 1
    }
  end

  # ExecutionCompletedEvent - Mark complete
  defp apply_event(%ExecutionCompletedEvent{} = event, state) do
    %{
      state
      | status: :completed,
        iteration: event.iteration,
        timeline_progress: "#{event.total_steps}/#{event.total_steps}",
        events_applied: state.events_applied + 1,
        completed_at: event.timestamp
    }
  end

  # ExecutionFailedEvent - Mark failed
  defp apply_event(%ExecutionFailedEvent{} = event, state) do
    error_info = %{
      kind: event.error_kind,
      step_name: event.failed_step,
      reason: event.error_reason,
      message: event.error_message
    }

    %{
      state
      | status: :failed,
        error: error_info,
        events_applied: state.events_applied + 1,
        completed_at: event.timestamp
    }
  end

  # Fallback for unknown events
  defp apply_event(_event, state) do
    Logger.warning("Unknown event type encountered during reconstruction")
    %{state | events_applied: state.events_applied + 1}
  end

  # Helper to safely convert to atom
  defp atomize(value) when is_atom(value), do: value
  defp atomize(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> value  # Keep as string if atom doesn't exist
    end
  end
  defp atomize(value), do: value

  # Helper to reconstruct tuples that were serialized as lists
  defp reconstruct_result(["ok" | rest]), do: {:ok, reconstruct_value(rest)}
  defp reconstruct_result(["error" | rest]), do: {:error, reconstruct_value(rest)}
  defp reconstruct_result(value) when is_list(value) do
    # If it's a list with exactly 2 elements and first is a string, might be a tuple
    case value do
      [first, second] when is_binary(first) ->
        # Try to convert to atom and make tuple
        try do
          {String.to_existing_atom(first), reconstruct_value(second)}
        rescue
          ArgumentError -> value  # Keep as list if not a valid atom
        end
      _ -> value
    end
  end
  defp reconstruct_result(value), do: value

  # Helper to recursively reconstruct nested values
  defp reconstruct_value([single]), do: single
  defp reconstruct_value(value) when is_list(value), do: Enum.map(value, &reconstruct_value/1)
  defp reconstruct_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {atomize(k), reconstruct_value(v)} end)
  end
  defp reconstruct_value(value), do: value
end
