defmodule Cerebelum.Infrastructure.BlueprintRegistry do
  @moduledoc """
  In-memory registry for workflow blueprints submitted via gRPC.

  Stores blueprint definitions so they can be used during workflow execution.
  Uses ETS for fast concurrent access.
  """

  use GenServer
  require Logger

  @table_name :blueprint_registry

  # Client API

  @doc """
  Start the BlueprintRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Store a blueprint definition.

  ## Parameters
  - workflow_module: Workflow module name (string)
  - blueprint: Blueprint definition map

  ## Returns
  - :ok
  """
  def store_blueprint(workflow_module, blueprint) do
    GenServer.call(__MODULE__, {:store, workflow_module, blueprint})
  end

  @doc """
  Get a blueprint definition.

  ## Parameters
  - workflow_module: Workflow module name (string)

  ## Returns
  - {:ok, blueprint} if found
  - {:error, :not_found} if not found
  """
  def get_blueprint(workflow_module) do
    case :ets.lookup(@table_name, workflow_module) do
      [{^workflow_module, blueprint}] ->
        {:ok, blueprint}
      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Delete a blueprint definition.

  ## Parameters
  - workflow_module: Workflow module name (string)

  ## Returns
  - :ok
  """
  def delete_blueprint(workflow_module) do
    GenServer.call(__MODULE__, {:delete, workflow_module})
  end

  @doc """
  List all stored blueprints.

  ## Returns
  - [workflow_module]
  """
  def list_blueprints do
    :ets.match(@table_name, {:"$1", :_})
    |> Enum.map(fn [module] -> module end)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for blueprint storage
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    Logger.info("BlueprintRegistry started")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:store, workflow_module, blueprint}, _from, state) do
    :ets.insert(@table_name, {workflow_module, blueprint})
    Logger.debug("Blueprint stored: #{workflow_module}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, workflow_module}, _from, state) do
    :ets.delete(@table_name, workflow_module)
    Logger.debug("Blueprint deleted: #{workflow_module}")
    {:reply, :ok, state}
  end
end
