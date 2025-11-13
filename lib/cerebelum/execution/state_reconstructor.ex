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

  # Private Helpers

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
