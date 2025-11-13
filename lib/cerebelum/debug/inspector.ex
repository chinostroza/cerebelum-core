defmodule Cerebelum.Debug.Inspector do
  @moduledoc """
  State inspection API for debugging workflow executions.

  Provides programmatic access to execution state at any point in time,
  without needing the interactive debugger.

  ## Usage

      # Get state at specific step
      {:ok, state} = Cerebelum.Debug.Inspector.state_at_step("exec-123", :step2)

      # Get state at specific event version
      {:ok, state} = Cerebelum.Debug.Inspector.state_at_version("exec-123", 5)

      # Get diff between two states
      {:ok, diff} = Cerebelum.Debug.Inspector.diff_versions("exec-123", 3, 7)

      # List all steps in execution
      {:ok, steps} = Cerebelum.Debug.Inspector.list_steps("exec-123")

      # Get execution timeline
      {:ok, timeline} = Cerebelum.Debug.Inspector.timeline("exec-123")
  """

  alias Cerebelum.EventStore
  alias Cerebelum.Execution.StateReconstructor
  alias Cerebelum.Persistence.Event

  @doc """
  Reconstructs state at a specific step.

  Returns the state immediately after the step was executed.

  ## Examples

      iex> Inspector.state_at_step("exec-123", :step2)
      {:ok, %{
        execution_id: "exec-123",
        status: :running,
        current_step: :step2,
        results: %{step1: {:ok, 1}, step2: {:ok, 2}},
        ...
      }}
  """
  @spec state_at_step(String.t(), atom()) ::
          {:ok, StateReconstructor.reconstructed_state()} | {:error, term()}
  def state_at_step(execution_id, step_name) do
    with {:ok, events} <- EventStore.get_events(execution_id),
         {:ok, version} <- find_version_for_step(events, step_name) do
      StateReconstructor.reconstruct_to_version(execution_id, version)
    end
  end

  @doc """
  Reconstructs state at a specific event version.

  ## Examples

      iex> Inspector.state_at_version("exec-123", 5)
      {:ok, %{execution_id: "exec-123", ...}}
  """
  @spec state_at_version(String.t(), non_neg_integer()) ::
          {:ok, StateReconstructor.reconstructed_state()} | {:error, term()}
  def state_at_version(execution_id, version) do
    StateReconstructor.reconstruct_to_version(execution_id, version)
  end

  @doc """
  Gets the current (final) state of an execution.

  ## Examples

      iex> Inspector.current_state("exec-123")
      {:ok, %{status: :completed, ...}}
  """
  @spec current_state(String.t()) ::
          {:ok, StateReconstructor.reconstructed_state()} | {:error, term()}
  def current_state(execution_id) do
    StateReconstructor.reconstruct(execution_id)
  end

  @doc """
  Compares states between two versions and returns the differences.

  ## Examples

      iex> Inspector.diff_versions("exec-123", 3, 7)
      {:ok, %{
        results_added: [:step2, :step3, :step4],
        results_changed: [],
        current_step_changed: {:step1, :step4},
        iteration_changed: {0, 1}
      }}
  """
  @spec diff_versions(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def diff_versions(execution_id, from_version, to_version) do
    with {:ok, state1} <- state_at_version(execution_id, from_version),
         {:ok, state2} <- state_at_version(execution_id, to_version) do
      diff = compute_diff(state1, state2)
      {:ok, diff}
    end
  end

  @doc """
  Compares states before and after a step execution.

  ## Examples

      iex> Inspector.diff_at_step("exec-123", :step2)
      {:ok, %{
        results_added: [:step2],
        current_step_changed: {:step1, :step2}
      }}
  """
  @spec diff_at_step(String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def diff_at_step(execution_id, step_name) do
    with {:ok, events} <- EventStore.get_events(execution_id),
         {:ok, step_version} <- find_version_for_step(events, step_name) do
      # State before step
      before_version = step_version - 1

      if before_version < 0 do
        {:error, :step_is_first}
      else
        diff_versions(execution_id, before_version, step_version)
      end
    end
  end

  @doc """
  Lists all steps that were executed in order.

  ## Examples

      iex> Inspector.list_steps("exec-123")
      {:ok, [:step1, :step2, :step3]}
  """
  @spec list_steps(String.t()) :: {:ok, [atom()]} | {:error, term()}
  def list_steps(execution_id) do
    with {:ok, state} <- current_state(execution_id) do
      steps =
        state.results
        |> Map.keys()
        |> Enum.sort()

      {:ok, steps}
    end
  end

  @doc """
  Gets the execution timeline with timestamps and durations.

  Returns a list of events in chronological order with metadata.

  ## Examples

      iex> Inspector.timeline("exec-123")
      {:ok, [
        %{
          version: 0,
          type: "ExecutionStartedEvent",
          timestamp: ~U[2025-01-01 00:00:00Z],
          step: nil
        },
        %{
          version: 1,
          type: "StepExecutedEvent",
          timestamp: ~U[2025-01-01 00:00:01Z],
          step: :step1,
          duration_ms: 10
        },
        ...
      ]}
  """
  @spec timeline(String.t()) :: {:ok, [map()]} | {:error, term()}
  def timeline(execution_id) do
    case EventStore.get_events(execution_id) do
      {:ok, events} ->
        timeline_entries =
          Enum.map(events, fn event ->
            domain_event = Event.to_domain_event(event)

            base = %{
              version: event.version,
              type: event.event_type,
              timestamp: domain_event.timestamp
            }

            # Add step-specific info
            case domain_event do
              %{step_name: step_name, duration_ms: duration} ->
                Map.merge(base, %{step: step_name, duration_ms: duration})

              %{step_name: step_name} ->
                Map.put(base, :step, step_name)

              _ ->
                Map.put(base, :step, nil)
            end
          end)

        {:ok, timeline_entries}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets summary statistics for an execution.

  ## Examples

      iex> Inspector.stats("exec-123")
      {:ok, %{
        total_events: 10,
        total_steps: 3,
        status: :completed,
        duration_ms: 150,
        iterations: 0,
        errors: 0
      }}
  """
  @spec stats(String.t()) :: {:ok, map()} | {:error, term()}
  def stats(execution_id) do
    with {:ok, events} <- EventStore.get_events(execution_id),
         {:ok, state} <- current_state(execution_id) do
      stats = %{
        total_events: length(events),
        total_steps: map_size(state.results),
        status: state.status,
        iterations: state.iteration,
        events_applied: state.events_applied,
        has_error: state.error != nil
      }

      # Calculate duration if we have timestamps
      duration_stats =
        case {List.first(events), List.last(events)} do
          {%{inserted_at: start_time}, %{inserted_at: end_time}} ->
            duration_us = DateTime.diff(end_time, start_time, :microsecond)
            %{duration_ms: div(duration_us, 1000)}

          _ ->
            %{}
        end

      {:ok, Map.merge(stats, duration_stats)}
    end
  end

  @doc """
  Finds the event that caused an error, if any.

  Returns error details including kind, step, and message.
  Note: kind is returned as a string (e.g., "exception") because
  events store atoms as strings during serialization.

  ## Examples

      iex> Inspector.find_error("exec-123")
      {:ok, %{
        version: 5,
        step: :step3,
        kind: "exception",
        message: "Something went wrong"
      }}

      iex> Inspector.find_error("exec-no-error")
      {:ok, nil}
  """
  @spec find_error(String.t()) :: {:ok, map() | nil} | {:error, term()}
  def find_error(execution_id) do
    case EventStore.get_events(execution_id) do
      {:ok, events} ->
        error_event =
          Enum.find(events, fn event ->
            event.event_type in ["StepFailedEvent", "ExecutionFailedEvent"]
          end)

        case error_event do
          nil ->
            {:ok, nil}

          event ->
            domain_event = Event.to_domain_event(event)

            error_info = %{
              version: event.version,
              type: event.event_type,
              timestamp: domain_event.timestamp
            }

            # Add step and error details
            error_details =
              case domain_event do
                %{step_name: step, error_kind: kind, error_message: msg} ->
                  %{step: step, kind: kind, message: msg}

                %{failed_step: step, error_kind: kind, error_message: msg} ->
                  %{step: step, kind: kind, message: msg}

                _ ->
                  %{}
              end

            {:ok, Map.merge(error_info, error_details)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Helpers

  defp find_version_for_step(events, step_name) do
    # Convert step_name to string for comparison (events store atoms as strings)
    step_name_str = to_string(step_name)

    event =
      Enum.find(events, fn event ->
        domain_event = Event.to_domain_event(event)

        case domain_event do
          %{step_name: ^step_name_str} -> true
          _ -> false
        end
      end)

    case event do
      nil -> {:error, :step_not_found}
      event -> {:ok, event.version}
    end
  end

  defp compute_diff(state1, state2) do
    # Results diff
    keys1 = MapSet.new(Map.keys(state1.results))
    keys2 = MapSet.new(Map.keys(state2.results))

    results_added = MapSet.difference(keys2, keys1) |> MapSet.to_list() |> Enum.sort()
    results_removed = MapSet.difference(keys1, keys2) |> MapSet.to_list() |> Enum.sort()

    results_changed =
      MapSet.intersection(keys1, keys2)
      |> Enum.filter(fn key ->
        state1.results[key] != state2.results[key]
      end)
      |> Enum.sort()

    diff = %{
      results_added: results_added,
      results_removed: results_removed,
      results_changed: results_changed
    }

    # Add other field changes
    diff =
      if state1.current_step != state2.current_step do
        Map.put(diff, :current_step_changed, {state1.current_step, state2.current_step})
      else
        diff
      end

    diff =
      if state1.iteration != state2.iteration do
        Map.put(diff, :iteration_changed, {state1.iteration, state2.iteration})
      else
        diff
      end

    diff =
      if state1.status != state2.status do
        Map.put(diff, :status_changed, {state1.status, state2.status})
      else
        diff
      end

    diff
  end
end
