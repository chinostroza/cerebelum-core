defmodule Cerebelum.Events do
  @moduledoc """
  Domain events for workflow execution.

  All events are JSON-serializable and represent state changes in workflow execution.
  Events are stored in an append-only event store for complete audit trail and time-travel debugging.

  ## Event Types

  - `ExecutionStartedEvent` - Workflow execution begins
  - `StepExecutedEvent` - Step completes successfully
  - `StepFailedEvent` - Step fails with error
  - `DivergeTakenEvent` - Diverge path is taken (retry, fail, etc)
  - `BranchTakenEvent` - Branch path is taken (business logic routing)
  - `JumpExecutedEvent` - Jump to different step (back_to, skip_to)
  - `ExecutionCompletedEvent` - Workflow completes successfully
  - `ExecutionFailedEvent` - Workflow fails

  ## Event Sourcing

  All events have:
  - `event_id` - Unique event ID (UUID)
  - `execution_id` - Workflow execution ID
  - `timestamp` - When event occurred
  - `version` - Event version number (for ordering)

  Events are immutable once stored.
  """

  defmodule ExecutionStartedEvent do
    @moduledoc """
    Event fired when a workflow execution begins.

    Contains initial execution context and workflow metadata.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            workflow_module: module(),
            workflow_version: String.t(),
            inputs: map(),
            correlation_id: String.t() | nil,
            tags: [String.t()],
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :workflow_module,
      :workflow_version,
      :inputs,
      :correlation_id,
      :tags,
      :timestamp,
      :version
    ]

    @doc """
    Creates a new ExecutionStartedEvent.

    ## Examples

        iex> event = ExecutionStartedEvent.new("exec-123", MyWorkflow, %{user_id: 1}, 0)
        iex> event.execution_id
        "exec-123"
    """
    @spec new(String.t(), module(), map(), non_neg_integer(), keyword()) :: t()
    def new(execution_id, workflow_module, inputs, version, opts \\ []) do
      %__MODULE__{
        event_id: generate_event_id(),
        execution_id: execution_id,
        workflow_module: workflow_module,
        workflow_version: Keyword.get(opts, :workflow_version, "unknown"),
        inputs: inputs,
        correlation_id: Keyword.get(opts, :correlation_id),
        tags: Keyword.get(opts, :tags, []),
        timestamp: DateTime.utc_now(),
        version: version
      }
    end

    defp generate_event_id, do: Ecto.UUID.generate()
  end

  defmodule StepExecutedEvent do
    @moduledoc """
    Event fired when a step executes successfully.

    Contains step name, arguments, result, and execution duration.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            step_index: non_neg_integer(),
            args: list(),
            result: term(),
            duration_ms: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :step_index,
      :args,
      :result,
      :duration_ms,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), non_neg_integer(), list(), term(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, step_name, step_index, args, result, duration_ms, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        step_index: step_index,
        args: args,
        result: result,
        duration_ms: duration_ms,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule StepFailedEvent do
    @moduledoc """
    Event fired when a step fails with an error.

    Contains error information from ErrorInfo.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            step_index: non_neg_integer(),
            error_kind: atom(),
            error_reason: term(),
            error_message: String.t(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :step_index,
      :error_kind,
      :error_reason,
      :error_message,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), non_neg_integer(), atom(), term(), String.t(), non_neg_integer()) :: t()
    def new(execution_id, step_name, step_index, error_kind, error_reason, error_message, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        step_index: step_index,
        error_kind: error_kind,
        error_reason: error_reason,
        error_message: error_message,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule DivergeTakenEvent do
    @moduledoc """
    Event fired when a diverge path is taken.

    Diverges handle error conditions (retry, fail, etc).
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            matched_pattern: term(),
            action: atom(),
            target_step: atom() | nil,
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :matched_pattern,
      :action,
      :target_step,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), term(), atom(), atom() | nil, non_neg_integer()) :: t()
    def new(execution_id, step_name, matched_pattern, action, target_step, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        matched_pattern: matched_pattern,
        action: action,
        target_step: target_step,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule BranchTakenEvent do
    @moduledoc """
    Event fired when a branch path is taken.

    Branches handle business logic routing.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            condition: String.t(),
            action: atom(),
            target_step: atom() | nil,
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :condition,
      :action,
      :target_step,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), String.t(), atom(), atom() | nil, non_neg_integer()) :: t()
    def new(execution_id, step_name, condition, action, target_step, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        condition: condition,
        action: action,
        target_step: target_step,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule JumpExecutedEvent do
    @moduledoc """
    Event fired when a jump is executed (back_to or skip_to).

    Contains jump type, source, target, and iteration count.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            jump_type: :back_to | :skip_to,
            from_step: atom(),
            from_index: non_neg_integer(),
            to_step: atom(),
            to_index: non_neg_integer(),
            iteration: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :jump_type,
      :from_step,
      :from_index,
      :to_step,
      :to_index,
      :iteration,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), atom(), non_neg_integer(), atom(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
            t()
    def new(execution_id, jump_type, from_step, from_index, to_step, to_index, iteration, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        jump_type: jump_type,
        from_step: from_step,
        from_index: from_index,
        to_step: to_step,
        to_index: to_index,
        iteration: iteration,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ExecutionCompletedEvent do
    @moduledoc """
    Event fired when a workflow execution completes successfully.

    Contains final results and execution statistics.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            results: map(),
            total_steps: non_neg_integer(),
            total_duration_ms: non_neg_integer(),
            iteration: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :results,
      :total_steps,
      :total_duration_ms,
      :iteration,
      :timestamp,
      :version
    ]

    @spec new(String.t(), map(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, results, total_steps, total_duration_ms, iteration, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        results: results,
        total_steps: total_steps,
        total_duration_ms: total_duration_ms,
        iteration: iteration,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ExecutionFailedEvent do
    @moduledoc """
    Event fired when a workflow execution fails.

    Contains error information and partial results.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            error_kind: atom(),
            error_reason: term(),
            error_message: String.t(),
            failed_step: atom() | nil,
            partial_results: map(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :error_kind,
      :error_reason,
      :error_message,
      :failed_step,
      :partial_results,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), term(), String.t(), atom() | nil, map(), non_neg_integer()) :: t()
    def new(execution_id, error_kind, error_reason, error_message, failed_step, partial_results, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        error_kind: error_kind,
        error_reason: error_reason,
        error_message: error_message,
        failed_step: failed_step,
        partial_results: partial_results,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  @doc """
  Returns the event type name as a string.

  ## Examples

      iex> Cerebelum.Events.event_type(%ExecutionStartedEvent{})
      "ExecutionStartedEvent"
  """
  @spec event_type(struct()) :: String.t()
  def event_type(%module{}), do: module |> to_string() |> String.split(".") |> List.last()

  @doc """
  Serializes an event to a JSON-compatible map.

  ## Examples

      iex> event = ExecutionStartedEvent.new("exec-1", MyWorkflow, %{}, 0)
      iex> map = Cerebelum.Events.serialize(event)
      iex> is_map(map)
      true
  """
  @spec serialize(struct()) :: map()
  def serialize(event), do: Map.from_struct(event)

  @doc """
  Deserializes a map to an event struct.
  """
  @spec deserialize(String.t(), map()) :: struct()
  def deserialize(event_type, data) do
    module = Module.concat([__MODULE__, event_type])
    struct(module, atomize_keys(data))
  end

  # Helper to convert string keys to atoms
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {String.to_existing_atom(to_string(k)), v}
    end)
  end
end
