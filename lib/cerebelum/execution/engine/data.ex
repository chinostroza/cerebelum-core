defmodule Cerebelum.Execution.Engine.Data do
  @moduledoc """
  Data structure and helpers for execution engine state.

  This module defines the execution data structure and provides
  helper functions for manipulating it during workflow execution.
  """

  alias Cerebelum.Context
  alias Cerebelum.Workflow.Metadata
  alias Cerebelum.Execution.ResultsCache

  @type t :: %__MODULE__{
          context: Context.t(),
          workflow_metadata: map(),
          results: ResultsCache.t(),
          current_step_index: non_neg_integer(),
          error: term() | nil
        }

  defstruct [
    :context,
    :workflow_metadata,
    results: %{},
    current_step_index: 0,
    error: nil
  ]

  @doc """
  Creates initial execution data.

  ## Parameters

  - `workflow_module` - The workflow module to execute
  - `inputs` - User inputs for the workflow
  - `context_opts` - Options for context creation

  ## Examples

      data = Data.new(MyWorkflow, %{user_id: 123}, [])
  """
  @spec new(module(), map(), keyword()) :: t()
  def new(workflow_module, inputs, context_opts) do
    workflow_metadata = Metadata.extract(workflow_module)
    context = Context.new(workflow_module, inputs, context_opts)

    %__MODULE__{
      context: context,
      workflow_metadata: workflow_metadata,
      results: %{},
      current_step_index: 0
    }
  end

  @doc """
  Gets the name of the current step based on the step index.

  ## Examples

      iex> data = %Data{workflow_metadata: %{timeline: [:a, :b, :c]}, current_step_index: 1}
      iex> Data.current_step_name(data)
      :b
  """
  @spec current_step_name(t()) :: atom() | nil
  def current_step_name(data) do
    Enum.at(data.workflow_metadata.timeline, data.current_step_index)
  end

  @doc """
  Stores the result of a step execution.

  ## Examples

      iex> data = %Data{results: %{}}
      iex> data = Data.store_result(data, :step1, {:ok, "result"})
      iex> data.results
      %{step1: {:ok, "result"}}
  """
  @spec store_result(t(), atom(), term()) :: t()
  def store_result(data, step_name, result) do
    %{data | results: ResultsCache.put(data.results, step_name, result)}
  end

  @doc """
  Advances to the next step in the timeline.

  ## Examples

      iex> data = %Data{current_step_index: 0}
      iex> data = Data.advance_step(data)
      iex> data.current_step_index
      1
  """
  @spec advance_step(t()) :: t()
  def advance_step(data) do
    %{data | current_step_index: data.current_step_index + 1}
  end

  @doc """
  Updates the current step in the context.

  ## Examples

      iex> data = %Data{context: ctx}
      iex> data = Data.update_context_step(data, :new_step)
      iex> data.context.current_step
      :new_step
  """
  @spec update_context_step(t(), atom()) :: t()
  def update_context_step(data, step_name) do
    updated_context = Context.update_step(data.context, step_name)
    %{data | context: updated_context}
  end

  @doc """
  Marks the execution as failed with an ErrorInfo struct.

  ## Examples

      alias Cerebelum.Execution.ErrorInfo

      iex> data = %Data{error: nil}
      iex> error_info = ErrorInfo.from_timeout(:step1, "exec-123")
      iex> data = Data.mark_failed(data, error_info)
      iex> data.error.kind
      :timeout
  """
  @spec mark_failed(t(), Cerebelum.Execution.ErrorInfo.t()) :: t()
  def mark_failed(data, %Cerebelum.Execution.ErrorInfo{} = error_info) do
    %{data | error: error_info}
  end

  @doc """
  Checks if the workflow execution has finished (all steps executed).

  ## Examples

      iex> data = %Data{workflow_metadata: %{timeline: [:a, :b]}, current_step_index: 2}
      iex> Data.finished?(data)
      true

      iex> data = %Data{workflow_metadata: %{timeline: [:a, :b]}, current_step_index: 1}
      iex> Data.finished?(data)
      false
  """
  @spec finished?(t()) :: boolean()
  def finished?(data) do
    data.current_step_index >= length(data.workflow_metadata.timeline)
  end

  @doc """
  Builds a status map for the current execution state.

  ## Examples

      data = Data.new(MyWorkflow, %{}, [])
      status = Data.build_status(data, :executing_step)
  """
  @spec build_status(t(), atom()) :: map()
  def build_status(data, state) do
    timeline_length = length(data.workflow_metadata.timeline)

    error_info =
      if data.error do
        %{
          error: Cerebelum.Execution.ErrorInfo.to_map(data.error),
          error_message: Cerebelum.Execution.ErrorInfo.format(data.error)
        }
      else
        %{error: nil, error_message: nil}
      end

    Map.merge(
      %{
        state: state,
        execution_id: data.context.execution_id,
        workflow_module: data.context.workflow_module,
        current_step: current_step_name(data),
        timeline_progress: "#{data.current_step_index}/#{timeline_length}",
        completed_steps: data.current_step_index,
        total_steps: timeline_length,
        results: data.results,
        context: data.context
      },
      error_info
    )
  end
end
