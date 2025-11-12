defmodule Cerebelum.Execution.Engine do
  @moduledoc """
  Execution engine implemented as a state machine using :gen_statem.

  The engine orchestrates workflow execution by managing execution state
  and coordinating step execution through StepExecutor.

  ## States (Phase 2)

  - `:initializing` - Setting up execution
  - `:executing_step` - Running current step function
  - `:completed` - Successfully finished
  - `:failed` - Failed with error

  Future states (Phase 3+):
  - `:evaluating_diverge` - Checking diverge conditions
  - `:evaluating_branch` - Checking branch conditions
  - `:sleeping` - Paused (sleep)
  - `:waiting_for_approval` - Paused (HITL)

  ## State Transitions (Phase 2)

  ```
  :initializing -> :executing_step (on start)
  :executing_step -> :executing_step (next step)
  :executing_step -> :completed (timeline finished)
  :executing_step -> :failed (on error)
  ```

  ## Usage

      {:ok, pid} = Engine.start_link(
        workflow_module: MyWorkflow,
        inputs: %{user_id: 123}
      )

      Engine.get_status(pid)
      #=> %{state: :executing_step, context: %Context{}, ...}

  ## Architecture

  The engine is split into focused modules:
  - `Engine` - Public API and gen_statem callbacks
  - `Engine.Data` - Execution data structure and helpers
  - `Engine.StateHandlers` - State functions for gen_statem
  - `StepExecutor` - Step execution logic
  """

  @behaviour :gen_statem

  require Logger

  alias Cerebelum.Execution.Engine.{Data, StateHandlers}

  @type state :: :initializing | :executing_step | :completed | :failed

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  ## Public API

  @doc """
  Starts the execution engine.

  ## Options

  - `:workflow_module` - The workflow module to execute (required)
  - `:inputs` - Input data for the workflow (default: %{})
  - `:context_opts` - Options passed to Context.new/3 (default: [])
  - `:name` - Optional name for the process

  ## Examples

      {:ok, pid} = Engine.start_link(
        workflow_module: MyWorkflow,
        inputs: %{order_id: "123"}
      )

      {:ok, pid} = Engine.start_link(
        workflow_module: MyWorkflow,
        inputs: %{},
        name: :my_execution
      )
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      :gen_statem.start_link({:local, name}, __MODULE__, opts, [])
    else
      :gen_statem.start_link(__MODULE__, opts, [])
    end
  end

  @doc """
  Gets the current status of the execution.

  Returns a map with:
  - `:state` - Current state machine state
  - `:execution_id` - Unique execution ID
  - `:workflow_module` - The workflow module being executed
  - `:current_step` - Current step name
  - `:timeline_progress` - "completed/total" format
  - `:completed_steps` - Number of completed steps
  - `:total_steps` - Total steps in timeline
  - `:results` - Map of step results
  - `:error` - Error information (if failed)
  - `:context` - Current execution context

  ## Examples

      status = Engine.get_status(pid)
      #=> %{
      #     state: :completed,
      #     execution_id: "abc-123",
      #     current_step: nil,
      #     timeline_progress: "4/4",
      #     ...
      #   }
  """
  @spec get_status(pid()) :: map()
  def get_status(pid) do
    :gen_statem.call(pid, :get_status)
  end

  @doc """
  Stops the execution engine.

  ## Examples

      Engine.stop(pid)
      #=> :ok
  """
  @spec stop(pid()) :: :ok
  def stop(pid) do
    :gen_statem.stop(pid)
  end

  ## gen_statem callbacks

  @impl true
  def callback_mode, do: [:state_functions, :state_enter]

  @impl true
  def init(opts) do
    workflow_module = Keyword.fetch!(opts, :workflow_module)
    inputs = Keyword.get(opts, :inputs, %{})
    context_opts = Keyword.get(opts, :context_opts, [])

    data = Data.new(workflow_module, inputs, context_opts)

    Logger.info("Initializing execution: #{data.context.execution_id}")

    # Start in :initializing state, then transition to :executing_step
    {:ok, :initializing, data, [{:next_event, :internal, :start}]}
  end

  @impl true
  def terminate(reason, _state, data) do
    Logger.info("Execution #{data.context.execution_id} terminated: #{inspect(reason)}")
    :ok
  end

  ## State Functions - Delegate to StateHandlers

  @doc false
  def initializing(event_type, event_content, data) do
    StateHandlers.initializing(event_type, event_content, data)
  end

  @doc false
  def executing_step(event_type, event_content, data) do
    StateHandlers.executing_step(event_type, event_content, data)
  end

  @doc false
  def completed(event_type, event_content, data) do
    StateHandlers.completed(event_type, event_content, data)
  end

  @doc false
  def failed(event_type, event_content, data) do
    StateHandlers.failed(event_type, event_content, data)
  end
end
