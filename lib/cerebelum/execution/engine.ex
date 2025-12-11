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
      restart: :transient,  # Changed from :temporary to enable resurrection
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
  Gets the execution_id from the engine process.

  ## Examples

      {:ok, pid} = Engine.start_link(workflow_module: MyWorkflow, inputs: %{})
      execution_id = Engine.get_execution_id(pid)
      #=> "exec_1234..."
  """
  @spec get_execution_id(pid()) :: String.t()
  def get_execution_id(pid) do
    %{context: context} = get_status(pid)
    context.execution_id
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
    case Keyword.get(opts, :resume_from) do
      nil ->
        # Normal startup - create new execution
        workflow_module = Keyword.fetch!(opts, :workflow_module)
        inputs = Keyword.get(opts, :inputs, %{})
        context_opts = Keyword.get(opts, :context_opts, [])

        data = Data.new(workflow_module, inputs, context_opts)

        Logger.info("Initializing execution: #{data.context.execution_id}")

        # Register with execution registry
        Cerebelum.Execution.Registry.register_execution(data.context.execution_id, self())

        # Start in :initializing state, then transition to :executing_step
        {:ok, :initializing, data, [{:next_event, :internal, :start}]}

      %Data{} = resumed_data ->
        # Resume mode - reconstruct from events
        Logger.info("Resuming execution: #{resumed_data.context.execution_id}")

        # Register with execution registry
        case Cerebelum.Execution.Registry.register_execution(resumed_data.context.execution_id, self()) do
          :ok ->
            # Determine resume state and prepare actions
            {resume_state, resume_data, actions} = prepare_resume(resumed_data)

            Logger.info(
              "Resuming in state #{resume_state} for execution #{resume_data.context.execution_id}"
            )

            {:ok, resume_state, resume_data, actions}

          {:error, :already_registered} ->
            # Execution is already running - prevent duplicate
            Logger.warning("Execution #{resumed_data.context.execution_id} already running")
            {:stop, :already_running}
        end
    end
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

  @doc false
  def sleeping(event_type, event_content, data) do
    StateHandlers.sleeping(event_type, event_content, data)
  end

  @doc false
  def waiting_for_approval(event_type, event_content, data) do
    StateHandlers.waiting_for_approval(event_type, event_content, data)
  end

  ## Private Helpers for Resurrection

  # Prepares the resume state and actions based on reconstructed data
  defp prepare_resume(data) do
    cond do
      # If there's an error, resume in failed state
      data.error != nil ->
        {:failed, data, []}

      # If workflow is finished, resume in completed state
      Data.finished?(data) ->
        {:completed, data, []}

      # If sleeping, calculate remaining time and resume in sleeping state
      data.sleep_duration_ms != nil && data.sleep_started_at != nil ->
        prepare_sleep_resume(data)

      # If waiting for approval, calculate remaining time and resume in waiting state
      data.approval_type != nil && data.approval_started_at != nil ->
        prepare_approval_resume(data)

      # Otherwise, resume execution at current step
      true ->
        {:executing_step, data, [{:next_event, :internal, :execute}]}
    end
  end

  # Prepares resume for sleeping state
  defp prepare_sleep_resume(data) do
    now_wall_ms = System.system_time(:millisecond)
    elapsed_wall_ms = now_wall_ms - data.sleep_started_at
    remaining_ms = data.sleep_duration_ms - elapsed_wall_ms

    if remaining_ms <= 0 do
      # Sleep time has already elapsed - wake up immediately and advance
      Logger.info(
        "Sleep already elapsed for #{data.context.execution_id}, waking immediately"
      )

      # Clear sleep state and advance step
      resumed_data = %{data |
        sleep_duration_ms: nil,
        sleep_started_at: nil,
        sleep_step_name: nil,
        sleep_result: nil
      }
      |> Data.advance_step()

      # Continue execution
      {:executing_step, resumed_data, [{:next_event, :internal, :execute}]}
    else
      # Resume sleeping with remaining time
      Logger.info(
        "Resuming sleep for #{data.context.execution_id}, #{remaining_ms}ms remaining"
      )

      # Use state_timeout to wake up after remaining time
      {:sleeping, data, [{:state_timeout, remaining_ms, :wake_up}]}
    end
  end

  # Prepares resume for approval waiting state
  defp prepare_approval_resume(data) do
    case data.approval_timeout_ms do
      nil ->
        # No timeout - just wait indefinitely
        Logger.info(
          "Resuming approval wait for #{data.context.execution_id} (no timeout)"
        )

        {:waiting_for_approval, data, []}

      timeout_ms when is_integer(timeout_ms) ->
        # Calculate remaining timeout
        now_wall_ms = System.system_time(:millisecond)
        elapsed_wall_ms = now_wall_ms - data.approval_started_at
        remaining_ms = timeout_ms - elapsed_wall_ms

        if remaining_ms <= 0 do
          # Approval has already timed out - fail immediately
          Logger.warning(
            "Approval timeout already elapsed for #{data.context.execution_id}"
          )

          error_info = %Cerebelum.Execution.ErrorInfo{
            kind: :approval_timeout,
            reason: :timeout,
            step_name: data.approval_step_name,
            execution_id: data.context.execution_id
          }

          failed_data = Data.mark_failed(data, error_info)
          {:failed, failed_data, []}
        else
          # Resume waiting with remaining timeout
          Logger.info(
            "Resuming approval wait for #{data.context.execution_id}, #{remaining_ms}ms timeout remaining"
          )

          {:waiting_for_approval, data, [{:state_timeout, remaining_ms, :approval_timeout}]}
        end
    end
  end
end
