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
  - `ParallelStartedEvent` - Parallel task execution begins
  - `ParallelTaskCompletedEvent` - Single parallel task completes
  - `ParallelTaskFailedEvent` - Single parallel task fails
  - `ParallelCompletedEvent` - All parallel tasks complete
  - `SleepStartedEvent` - Execution enters sleep state
  - `SleepCompletedEvent` - Execution wakes up from sleep
  - `ApprovalRequestedEvent` - Human approval requested
  - `ApprovalReceivedEvent` - Approval granted
  - `ApprovalRejectedEvent` - Approval rejected
  - `ApprovalTimeoutEvent` - Approval request timed out
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

  defmodule ParallelStartedEvent do
    @moduledoc """
    Event fired when parallel task execution begins.

    Contains the step name that initiated parallel execution and list of tasks.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            task_specs: [{atom(), list()}],
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :task_specs,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), [{atom(), list()}], non_neg_integer()) :: t()
    def new(execution_id, step_name, task_specs, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        task_specs: task_specs,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ParallelTaskCompletedEvent do
    @moduledoc """
    Event fired when a single parallel task completes successfully.

    Contains task function name, result, and execution duration.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            parent_step: atom(),
            task_name: atom(),
            result: term(),
            duration_ms: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :parent_step,
      :task_name,
      :result,
      :duration_ms,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), atom(), term(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, parent_step, task_name, result, duration_ms, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        parent_step: parent_step,
        task_name: task_name,
        result: result,
        duration_ms: duration_ms,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ParallelTaskFailedEvent do
    @moduledoc """
    Event fired when a single parallel task fails.

    Contains error information for the failed task.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            parent_step: atom(),
            task_name: atom(),
            error_kind: atom(),
            error_message: String.t(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :parent_step,
      :task_name,
      :error_kind,
      :error_message,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), atom(), atom(), String.t(), non_neg_integer()) :: t()
    def new(execution_id, parent_step, task_name, error_kind, error_message, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        parent_step: parent_step,
        task_name: task_name,
        error_kind: error_kind,
        error_message: error_message,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ParallelCompletedEvent do
    @moduledoc """
    Event fired when all parallel tasks complete.

    Contains merged results from all tasks.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            parent_step: atom(),
            merged_result: map(),
            total_duration_ms: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :parent_step,
      :merged_result,
      :total_duration_ms,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), map(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, parent_step, merged_result, total_duration_ms, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        parent_step: parent_step,
        merged_result: merged_result,
        total_duration_ms: total_duration_ms,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule SleepStartedEvent do
    @moduledoc """
    Event fired when execution enters sleep state.

    Contains duration and the step that initiated the sleep.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            duration_ms: non_neg_integer(),
            resume_at: DateTime.t(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :duration_ms,
      :resume_at,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, step_name, duration_ms, version) do
      resume_at = DateTime.add(DateTime.utc_now(), duration_ms, :millisecond)

      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        duration_ms: duration_ms,
        resume_at: resume_at,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule SleepCompletedEvent do
    @moduledoc """
    Event fired when execution wakes up from sleep.

    Contains actual sleep duration.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            actual_duration_ms: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :actual_duration_ms,
      :timestamp,
      :version
    ]

    @spec new(String.t(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, actual_duration_ms, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        actual_duration_ms: actual_duration_ms,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ApprovalRequestedEvent do
    @moduledoc """
    Event fired when execution pauses waiting for human approval.

    Contains approval type and contextual data.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            approval_type: atom(),
            approval_data: map(),
            timeout_ms: non_neg_integer() | nil,
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :approval_type,
      :approval_data,
      :timeout_ms,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), atom(), map(), non_neg_integer() | nil, non_neg_integer()) :: t()
    def new(execution_id, step_name, approval_type, approval_data, timeout_ms, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        approval_type: approval_type,
        approval_data: approval_data,
        timeout_ms: timeout_ms,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ApprovalReceivedEvent do
    @moduledoc """
    Event fired when approval is granted.

    Contains decision and approver data.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            approval_response: map(),
            elapsed_ms: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :approval_response,
      :elapsed_ms,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), map(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, step_name, approval_response, elapsed_ms, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        approval_response: approval_response,
        elapsed_ms: elapsed_ms,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ApprovalRejectedEvent do
    @moduledoc """
    Event fired when approval is rejected.

    Contains rejection reason.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            rejection_reason: term(),
            elapsed_ms: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :rejection_reason,
      :elapsed_ms,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), term(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, step_name, rejection_reason, elapsed_ms, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        rejection_reason: rejection_reason,
        elapsed_ms: elapsed_ms,
        timestamp: DateTime.utc_now(),
        version: version
      }
    end
  end

  defmodule ApprovalTimeoutEvent do
    @moduledoc """
    Event fired when approval request times out.

    Contains timeout duration.
    """

    @derive Jason.Encoder
    @type t :: %__MODULE__{
            event_id: String.t(),
            execution_id: String.t(),
            step_name: atom(),
            timeout_ms: non_neg_integer(),
            timestamp: DateTime.t(),
            version: non_neg_integer()
          }

    defstruct [
      :event_id,
      :execution_id,
      :step_name,
      :timeout_ms,
      :timestamp,
      :version
    ]

    @spec new(String.t(), atom(), non_neg_integer(), non_neg_integer()) :: t()
    def new(execution_id, step_name, timeout_ms, version) do
      %__MODULE__{
        event_id: Ecto.UUID.generate(),
        execution_id: execution_id,
        step_name: step_name,
        timeout_ms: timeout_ms,
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
