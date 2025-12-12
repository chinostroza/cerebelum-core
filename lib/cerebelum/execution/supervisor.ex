defmodule Cerebelum.Execution.Supervisor do
  @moduledoc """
  Dynamic supervisor for workflow executions.

  This supervisor manages the lifecycle of workflow execution engines,
  allowing multiple workflows to run concurrently.

  ## Usage

      # Start an execution
      {:ok, pid} = Supervisor.start_execution(MyWorkflow, %{user_id: 123})

      # List all running executions
      pids = Supervisor.list_executions()
  """

  use DynamicSupervisor

  alias Cerebelum.Execution.Engine

  @doc """
  Starts the execution supervisor.

  This is typically called by the application supervision tree.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new workflow execution.

  ## Parameters

  - `workflow_module` - The workflow module to execute
  - `inputs` - Input data for the workflow (default: %{})
  - `opts` - Additional options passed to Engine.start_link/1

  ## Returns

  - `{:ok, pid}` - The execution engine PID
  - `{:error, reason}` - If the execution failed to start

  ## Examples

      {:ok, pid} = Supervisor.start_execution(MyWorkflow, %{order_id: "123"})
  """
  @spec start_execution(module(), map(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_execution(workflow_module, inputs \\ %{}, opts \\ []) do
    child_spec = {
      Engine,
      Keyword.merge([workflow_module: workflow_module, inputs: inputs], opts)
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Lists all currently running executions.

  Returns a list of PIDs for all active execution engines.

  ## Examples

      pids = Supervisor.list_executions()
      #=> [#PID<0.123.0>, #PID<0.124.0>]
  """
  @spec list_executions() :: [pid()]
  def list_executions do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end

  @doc """
  Counts the number of running executions.

  ## Examples

      count = Supervisor.count_executions()
      #=> 5
  """
  @spec count_executions() :: non_neg_integer()
  def count_executions do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc """
  Resumes a paused or crashed workflow execution from its event history.

  This function enables workflow resurrection after system restarts, crashes,
  or for resuming long-running workflows that were paused (sleeping/approval).

  ## Parameters

  - `execution_id` - The unique execution ID to resume

  ## Returns

  - `{:ok, pid}` - The execution engine PID
  - `{:error, :not_found}` - No events found for this execution
  - `{:error, :already_running}` - Execution is already running
  - `{:error, reason}` - Other errors during resurrection

  ## Examples

      # Resume a sleeping workflow after server restart
      {:ok, pid} = Supervisor.resume_execution("exec-abc-123")

      # Try to resume a non-existent execution
      {:error, :not_found} = Supervisor.resume_execution("unknown")

      # Try to resume an already running execution
      {:error, :already_running} = Supervisor.resume_execution("exec-running")

  ## How It Works

  1. Checks if execution is already running (via Registry)
  2. Reconstructs execution state from event history
  3. Validates state is resumable (not permanently completed/failed)
  4. Starts Engine with reconstructed state
  5. Engine determines resume state (sleeping, waiting, executing, etc.)
  6. Calculates remaining sleep/approval time if applicable

  ## Use Cases

  - Resurrect workflows after server restart
  - Resume multi-day workflows
  - Recover from crashes mid-execution
  - Continue approval workflows after system maintenance
  """
  @spec resume_execution(String.t()) :: {:ok, pid()} | {:error, term()}
  def resume_execution(execution_id) when is_binary(execution_id) do
    # Check if execution is already running
    case get_execution_pid(execution_id) do
      {:ok, _pid} ->
        {:error, :already_running}

      {:error, :not_found} ->
        # Reconstruct state from events
        case Cerebelum.Execution.StateReconstructor.reconstruct_to_engine_data(execution_id) do
          {:ok, engine_data} ->
            # Validate state is resumable
            if resumable?(engine_data) do
              # Start child with reconstructed data
              child_spec = {
                Engine,
                [resume_from: engine_data]
              }

              DynamicSupervisor.start_child(__MODULE__, child_spec)
            else
              {:error, :not_resumable}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Gets the PID for a running execution by its execution_id.

  ## Parameters

  - `execution_id` - The unique execution ID to look up

  ## Returns

  - `{:ok, pid}` - The execution engine PID
  - `{:error, :not_found}` - No execution is running with this ID

  ## Examples

      {:ok, pid} = Supervisor.get_execution_pid("exec-abc-123")
      {:error, :not_found} = Supervisor.get_execution_pid("unknown")
  """
  @spec get_execution_pid(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_execution_pid(execution_id) when is_binary(execution_id) do
    Cerebelum.Execution.Registry.lookup_execution(execution_id)
  end

  @doc """
  Terminates a specific execution.

  ## Parameters

  - `pid` - The PID of the execution engine to terminate

  ## Returns

  - `:ok` - The execution was terminated
  - `{:error, :not_found}` - The PID is not a child of this supervisor

  ## Examples

      Supervisor.terminate_execution(pid)
      #=> :ok
  """
  @spec terminate_execution(pid()) :: :ok | {:error, :not_found}
  def terminate_execution(pid) when is_pid(pid) do
    case DynamicSupervisor.terminate_child(__MODULE__, pid) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  ## Private Helpers

  # Checks if an execution state is resumable
  defp resumable?(engine_data) do
    cond do
      # Don't resume if already completed successfully
      engine_data.error == nil && Engine.Data.finished?(engine_data) ->
        false

      # Don't resume if permanently failed (non-transient errors)
      engine_data.error != nil && permanent_failure?(engine_data.error) ->
        false

      # All other states are resumable
      true ->
        true
    end
  end

  # Determines if an error is a permanent failure (not worth retrying)
  defp permanent_failure?(_error_info) do
    # For now, consider all failures as potentially resumable
    # In the future, we could check error.kind for specific permanent errors
    # like :validation_error, :authorization_error, etc.
    false
  end
end
