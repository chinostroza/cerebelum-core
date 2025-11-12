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
end
