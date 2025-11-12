defmodule Cerebelum.Context do
  @moduledoc """
  Execution context for workflows.

  The Context is an immutable struct that flows through workflow execution.
  It contains:
  - Execution identity (execution_id, workflow info)
  - User inputs
  - Execution state (current step, retry count)
  - Timestamps for deterministic behavior
  - Metadata and tags for observability

  ## Example

      context = Context.new(MyWorkflow, %{user_id: 123})
      context = Context.update_step(context, :validate_user)
      context = Context.increment_retry(context)
  """

  @enforce_keys [:execution_id, :workflow_module, :workflow_version, :started_at]
  defstruct [
    # Identity
    :execution_id,
    :workflow_module,
    :workflow_version,
    :correlation_id,

    # Timestamps (deterministic)
    :started_at,
    :updated_at,

    # User inputs (from execute_workflow call)
    inputs: %{},

    # Workflow state
    retry_count: 0,
    iteration: 0,
    current_step: nil,

    # Metadata
    tags: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          workflow_module: module(),
          workflow_version: String.t(),
          correlation_id: String.t() | nil,
          started_at: DateTime.t(),
          updated_at: DateTime.t() | nil,
          inputs: map(),
          retry_count: non_neg_integer(),
          iteration: non_neg_integer(),
          current_step: atom() | nil,
          tags: [String.t()],
          metadata: map()
        }

  @doc """
  Creates a new execution context.

  ## Parameters

  - `workflow_module` - The workflow module to execute
  - `inputs` - User inputs for the workflow (default: %{})
  - `opts` - Additional options (default: [])
    - `:execution_id` - Custom execution ID (default: generated UUID)
    - `:correlation_id` - For distributed tracing
    - `:tags` - Initial tags
    - `:metadata` - Initial metadata

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow, %{user_id: 123})
      iex> context.workflow_module
      MyWorkflow

      iex> context = Cerebelum.Context.new(MyWorkflow, %{}, correlation_id: "trace-123")
      iex> context.correlation_id
      "trace-123"
  """
  @spec new(module(), map(), keyword()) :: t()
  def new(workflow_module, inputs \\ %{}, opts \\ []) do
    execution_id = Keyword.get(opts, :execution_id, generate_uuid())
    correlation_id = Keyword.get(opts, :correlation_id)
    tags = Keyword.get(opts, :tags, [])
    metadata = Keyword.get(opts, :metadata, %{})

    workflow_version = get_workflow_version(workflow_module)
    now = DateTime.utc_now()

    %__MODULE__{
      execution_id: execution_id,
      workflow_module: workflow_module,
      workflow_version: workflow_version,
      correlation_id: correlation_id,
      started_at: now,
      updated_at: now,
      inputs: inputs,
      tags: tags,
      metadata: metadata
    }
  end

  @doc """
  Validates that a context has all required fields and valid values.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> Cerebelum.Context.valid?(context)
      true

      iex> Cerebelum.Context.valid?(%{})
      false
  """
  @spec valid?(any()) :: boolean()
  def valid?(%__MODULE__{} = context) do
    is_binary(context.execution_id) and
      is_atom(context.workflow_module) and
      is_binary(context.workflow_version) and
      match?(%DateTime{}, context.started_at) and
      is_map(context.inputs) and
      is_integer(context.retry_count) and context.retry_count >= 0 and
      is_integer(context.iteration) and context.iteration >= 0 and
      is_list(context.tags) and
      is_map(context.metadata)
  rescue
    _ -> false
  end

  def valid?(_), do: false

  @doc """
  Increments the retry count for the current step.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = Cerebelum.Context.increment_retry(context)
      iex> context.retry_count
      1
  """
  @spec increment_retry(t()) :: t()
  def increment_retry(%__MODULE__{} = context) do
    %{context | retry_count: context.retry_count + 1, updated_at: DateTime.utc_now()}
  end

  @doc """
  Resets the retry count to 0.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = context |> Cerebelum.Context.increment_retry() |> Cerebelum.Context.reset_retry()
      iex> context.retry_count
      0
  """
  @spec reset_retry(t()) :: t()
  def reset_retry(%__MODULE__{} = context) do
    %{context | retry_count: 0, updated_at: DateTime.utc_now()}
  end

  @doc """
  Increments the iteration count.

  Used for tracking workflow iterations in loops or diverge backs.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = Cerebelum.Context.increment_iteration(context)
      iex> context.iteration
      1
  """
  @spec increment_iteration(t()) :: t()
  def increment_iteration(%__MODULE__{} = context) do
    %{context | iteration: context.iteration + 1, updated_at: DateTime.utc_now()}
  end

  @doc """
  Updates the current step being executed.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = Cerebelum.Context.update_step(context, :validate_user)
      iex> context.current_step
      :validate_user
  """
  @spec update_step(t(), atom()) :: t()
  def update_step(%__MODULE__{} = context, step) when is_atom(step) do
    %{context | current_step: step, updated_at: DateTime.utc_now()}
  end

  @doc """
  Alias for update_step/2 for backward compatibility.
  """
  @spec advance_to_step(t(), atom()) :: t()
  def advance_to_step(context, step), do: update_step(context, step)

  @doc """
  Adds a tag to the context.

  Tags are useful for categorization and filtering in observability.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = Cerebelum.Context.add_tag(context, "priority:high")
      iex> "priority:high" in context.tags
      true
  """
  @spec add_tag(t(), String.t()) :: t()
  def add_tag(%__MODULE__{} = context, tag) when is_binary(tag) do
    if tag in context.tags do
      context
    else
      %{context | tags: [tag | context.tags], updated_at: DateTime.utc_now()}
    end
  end

  @doc """
  Adds multiple tags to the context.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = Cerebelum.Context.add_tags(context, ["priority:high", "user:admin"])
      iex> length(context.tags)
      2
  """
  @spec add_tags(t(), [String.t()]) :: t()
  def add_tags(%__MODULE__{} = context, tags) when is_list(tags) do
    Enum.reduce(tags, context, &add_tag(&2, &1))
  end

  @doc """
  Removes a tag from the context.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = context |> Cerebelum.Context.add_tag("temp") |> Cerebelum.Context.remove_tag("temp")
      iex> "temp" in context.tags
      false
  """
  @spec remove_tag(t(), String.t()) :: t()
  def remove_tag(%__MODULE__{} = context, tag) when is_binary(tag) do
    %{context | tags: List.delete(context.tags, tag), updated_at: DateTime.utc_now()}
  end

  @doc """
  Puts a value in the metadata map.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = Cerebelum.Context.put_metadata(context, :user_id, 123)
      iex> context.metadata.user_id
      123
  """
  @spec put_metadata(t(), atom() | String.t(), any()) :: t()
  def put_metadata(%__MODULE__{} = context, key, value) do
    %{context | metadata: Map.put(context.metadata, key, value), updated_at: DateTime.utc_now()}
  end

  @doc """
  Gets a value from the metadata map.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = Cerebelum.Context.put_metadata(context, :user_id, 123)
      iex> Cerebelum.Context.get_metadata(context, :user_id)
      123

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> Cerebelum.Context.get_metadata(context, :missing, :default)
      :default
  """
  @spec get_metadata(t(), atom() | String.t(), any()) :: any()
  def get_metadata(%__MODULE__{} = context, key, default \\ nil) do
    Map.get(context.metadata, key, default)
  end

  @doc """
  Merges metadata into the context.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> context = Cerebelum.Context.merge_metadata(context, %{user_id: 123, org_id: 456})
      iex> context.metadata.user_id
      123
  """
  @spec merge_metadata(t(), map()) :: t()
  def merge_metadata(%__MODULE__{} = context, metadata) when is_map(metadata) do
    %{context | metadata: Map.merge(context.metadata, metadata), updated_at: DateTime.utc_now()}
  end

  @doc """
  Converts the context to a map for serialization.

  ## Examples

      iex> context = Cerebelum.Context.new(MyWorkflow)
      iex> map = Cerebelum.Context.to_map(context)
      iex> is_map(map)
      true
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = context) do
    context
    |> Map.from_struct()
    |> Map.update(:started_at, nil, &DateTime.to_iso8601/1)
    |> Map.update(:updated_at, nil, fn
      nil -> nil
      dt -> DateTime.to_iso8601(dt)
    end)
  end

  @doc """
  Creates a context from a map.

  ## Examples

      iex> map = %{
      ...>   execution_id: "test-123",
      ...>   workflow_module: MyWorkflow,
      ...>   workflow_version: "abc123",
      ...>   started_at: "2025-01-01T00:00:00Z"
      ...> }
      iex> {:ok, context} = Cerebelum.Context.from_map(map)
      iex> context.execution_id
      "test-123"
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, started_at} <- parse_datetime(map[:started_at] || map["started_at"]),
         {:ok, updated_at} <- parse_optional_datetime(map[:updated_at] || map["updated_at"]) do
      context = %__MODULE__{
        execution_id: map[:execution_id] || map["execution_id"],
        workflow_module: map[:workflow_module] || map["workflow_module"],
        workflow_version: map[:workflow_version] || map["workflow_version"],
        correlation_id: map[:correlation_id] || map["correlation_id"],
        started_at: started_at,
        updated_at: updated_at,
        inputs: map[:inputs] || map["inputs"] || %{},
        retry_count: map[:retry_count] || map["retry_count"] || 0,
        iteration: map[:iteration] || map["iteration"] || 0,
        current_step: map[:current_step] || map["current_step"],
        tags: map[:tags] || map["tags"] || [],
        metadata: map[:metadata] || map["metadata"] || %{}
      }

      if valid?(context) do
        {:ok, context}
      else
        {:error, "Invalid context data"}
      end
    end
  end

  ## Private Functions

  defp generate_uuid do
    # Simple UUID v4 generator
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  defp format_uuid(<<a::64, b::32, c::32, d::32, e::96>>) do
    <<a::64, ?-, b::32, ?-, c::32, ?-, d::32, ?-, e::96>>
  end

  defp get_workflow_version(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__workflow_metadata__, 0) do
      metadata = module.__workflow_metadata__()
      metadata.version
    else
      "unknown"
    end
  end

  defp parse_datetime(nil), do: {:error, "Missing datetime"}
  defp parse_datetime(%DateTime{} = dt), do: {:ok, dt}

  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, "Invalid datetime format"}
    end
  end

  defp parse_optional_datetime(nil), do: {:ok, nil}
  defp parse_optional_datetime(dt), do: parse_datetime(dt)
end
