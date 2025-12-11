defmodule Cerebelum.Execution.Registry do
  @moduledoc """
  Registry for mapping execution_id to process PID.

  This module provides a centralized registry for tracking active workflow executions.
  It uses Elixir's built-in Registry with unique keys to ensure:
  - O(1) lookup performance
  - Automatic cleanup when processes die
  - Prevention of duplicate executions

  ## Usage

      # Register an execution
      {:ok, _} = Registry.register_execution(execution_id, self())

      # Look up an execution
      {:ok, pid} = Registry.lookup_execution(execution_id)

      # Unregister explicitly (optional - auto cleanup on process death)
      :ok = Registry.unregister_execution(execution_id)

  """

  @doc """
  Starts the execution registry.

  This is called automatically by the supervision tree.
  """
  def start_link(_opts) do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  @doc """
  Returns the child specification for use in a supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Registers an execution with its process PID.

  ## Parameters
    - execution_id: Unique identifier for the workflow execution
    - pid: Process ID of the execution engine

  ## Returns
    - `:ok` if registration succeeds
    - `{:error, :already_registered}` if execution_id is already registered

  ## Examples

      iex> Registry.register_execution("exec-123", self())
      :ok

      iex> Registry.register_execution("exec-123", self())
      {:error, :already_registered}

  """
  @spec register_execution(String.t(), pid()) :: :ok | {:error, :already_registered}
  def register_execution(execution_id, pid) when is_binary(execution_id) and is_pid(pid) do
    case Registry.register(__MODULE__, execution_id, nil) do
      {:ok, _owner} ->
        :ok

      {:error, {:already_registered, _existing_pid}} ->
        {:error, :already_registered}
    end
  end

  @doc """
  Looks up the PID for a given execution_id.

  ## Parameters
    - execution_id: Unique identifier for the workflow execution

  ## Returns
    - `{:ok, pid}` if the execution is registered
    - `{:error, :not_found}` if no execution is registered with this ID

  ## Examples

      iex> Registry.register_execution("exec-123", self())
      iex> Registry.lookup_execution("exec-123")
      {:ok, #PID<0.123.0>}

      iex> Registry.lookup_execution("unknown")
      {:error, :not_found}

  """
  @spec lookup_execution(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup_execution(execution_id) when is_binary(execution_id) do
    case Registry.lookup(__MODULE__, execution_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Unregisters an execution.

  Note: This is optional as the registry automatically cleans up when the
  registered process dies. Use this for explicit cleanup if needed.

  ## Parameters
    - execution_id: Unique identifier for the workflow execution

  ## Returns
    - `:ok` if unregistration succeeds or execution was not registered

  ## Examples

      iex> Registry.register_execution("exec-123", self())
      iex> Registry.unregister_execution("exec-123")
      :ok

  """
  @spec unregister_execution(String.t()) :: :ok
  def unregister_execution(execution_id) when is_binary(execution_id) do
    Registry.unregister(__MODULE__, execution_id)
    :ok
  end

  @doc """
  Lists all registered execution IDs and their PIDs.

  ## Returns
    - List of tuples `{execution_id, pid}`

  ## Examples

      iex> Registry.list_all()
      [{"exec-123", #PID<0.123.0>}, {"exec-456", #PID<0.456.0>}]

  """
  @spec list_all() :: [{String.t(), pid()}]
  def list_all do
    Registry.select(__MODULE__, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Returns the count of registered executions.

  ## Returns
    - Non-negative integer representing the number of active executions

  ## Examples

      iex> Registry.count()
      42

  """
  @spec count() :: non_neg_integer()
  def count do
    Registry.count(__MODULE__)
  end

  @doc """
  Checks if an execution is currently registered.

  ## Parameters
    - execution_id: Unique identifier for the workflow execution

  ## Returns
    - `true` if the execution is registered
    - `false` if the execution is not registered

  ## Examples

      iex> Registry.registered?("exec-123")
      true

      iex> Registry.registered?("unknown")
      false

  """
  @spec registered?(String.t()) :: boolean()
  def registered?(execution_id) when is_binary(execution_id) do
    case lookup_execution(execution_id) do
      {:ok, _pid} -> true
      {:error, :not_found} -> false
    end
  end
end
