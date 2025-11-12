defmodule Cerebelum.Workflow.Registry do
  @moduledoc """
  Registry para almacenar y consultar workflows registrados.

  El Registry mantiene metadata de todos los workflows registrados,
  permitiendo:
  - Lookup por módulo
  - Lookup por versión
  - Listar todos los workflows
  - Almacenar múltiples versiones del mismo workflow

  ## Uso

      # Iniciar el registry
      {:ok, _pid} = Registry.start_link([])

      # Registrar un workflow
      Registry.register(MyWorkflow)

      # Buscar por módulo
      {:ok, metadata} = Registry.lookup(MyWorkflow)

      # Buscar por versión
      {:ok, metadata} = Registry.lookup_by_version("abc123...")

      # Listar todos
      workflows = Registry.list_all()
  """

  use GenServer

  alias Cerebelum.Workflow.Metadata

  @type state :: %{
          by_module: %{module() => [map()]},
          by_version: %{String.t() => map()}
        }

  ## Client API

  @doc """
  Inicia el Registry.

  ## Opciones

  - `:name` - Nombre del proceso (default: `__MODULE__`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, [], name: name)
  end

  @doc """
  Registra un workflow en el registry.

  Extrae la metadata del workflow y la almacena indexada por
  módulo y versión.

  ## Parámetros

  - `module` - El módulo del workflow
  - `opts` - Keyword list de opciones:
    - `:registry` - Nombre del proceso registry (default: `__MODULE__`)

  ## Retorna

  - `{:ok, metadata}` - Si el registro fue exitoso
  - `{:error, reason}` - Si hubo un error

  ## Ejemplos

      iex> Registry.register(MyWorkflow)
      {:ok, %{module: MyWorkflow, version: "abc123...", ...}}
  """
  @spec register(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def register(module, opts \\ []) do
    registry = Keyword.get(opts, :registry, __MODULE__)

    try do
      metadata = Metadata.extract(module)
      GenServer.call(registry, {:register, metadata})
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Busca un workflow por su módulo.

  Retorna la versión más reciente del workflow.

  ## Parámetros

  - `module` - El módulo del workflow
  - `opts` - Keyword list de opciones:
    - `:registry` - Nombre del proceso registry (default: `__MODULE__`)

  ## Retorna

  - `{:ok, metadata}` - Si se encontró el workflow
  - `{:error, :not_found}` - Si no existe

  ## Ejemplos

      iex> Registry.lookup(MyWorkflow)
      {:ok, %{module: MyWorkflow, version: "abc123...", ...}}
  """
  @spec lookup(module(), keyword()) :: {:ok, map()} | {:error, :not_found}
  def lookup(module, opts \\ []) do
    registry = Keyword.get(opts, :registry, __MODULE__)
    GenServer.call(registry, {:lookup, module})
  end

  @doc """
  Busca un workflow por su versión.

  ## Parámetros

  - `version` - La versión del workflow (string hash)
  - `opts` - Keyword list de opciones:
    - `:registry` - Nombre del proceso registry (default: `__MODULE__`)

  ## Retorna

  - `{:ok, metadata}` - Si se encontró la versión
  - `{:error, :not_found}` - Si no existe

  ## Ejemplos

      iex> Registry.lookup_by_version("abc123...")
      {:ok, %{module: MyWorkflow, version: "abc123...", ...}}
  """
  @spec lookup_by_version(String.t(), keyword()) :: {:ok, map()} | {:error, :not_found}
  def lookup_by_version(version, opts \\ []) do
    registry = Keyword.get(opts, :registry, __MODULE__)
    GenServer.call(registry, {:lookup_version, version})
  end

  @doc """
  Lista todos los workflows registrados.

  ## Parámetros

  - `opts` - Keyword list de opciones:
    - `:registry` - Nombre del proceso registry (default: `__MODULE__`)

  ## Retorna

  Lista de metadata de todos los workflows (versión más reciente de cada uno).

  ## Ejemplos

      iex> Registry.list_all()
      [
        %{module: Workflow1, version: "abc...", ...},
        %{module: Workflow2, version: "def...", ...}
      ]
  """
  @spec list_all(keyword()) :: [map()]
  def list_all(opts \\ []) do
    registry = Keyword.get(opts, :registry, __MODULE__)
    GenServer.call(registry, :list_all)
  end

  @doc """
  Lista todas las versiones de un workflow específico.

  ## Parámetros

  - `module` - El módulo del workflow
  - `opts` - Keyword list de opciones:
    - `:registry` - Nombre del proceso registry (default: `__MODULE__`)

  ## Retorna

  Lista de metadata de todas las versiones registradas.

  ## Ejemplos

      iex> Registry.list_versions(MyWorkflow)
      [
        %{module: MyWorkflow, version: "abc...", ...},
        %{module: MyWorkflow, version: "def...", ...}
      ]
  """
  @spec list_versions(module(), keyword()) :: [map()]
  def list_versions(module, opts \\ []) do
    registry = Keyword.get(opts, :registry, __MODULE__)
    GenServer.call(registry, {:list_versions, module})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %{
      by_module: %{},
      by_version: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register, metadata}, _from, state) do
    module = metadata.module
    version = metadata.version

    # Añadir a índice por módulo
    module_versions = Map.get(state.by_module, module, [])

    # Verificar si esta versión ya existe
    already_registered? = Enum.any?(module_versions, fn m -> m.version == version end)

    if already_registered? do
      # Ya existe esta versión, retornar la existente
      existing = Enum.find(module_versions, fn m -> m.version == version end)
      {:reply, {:ok, existing}, state}
    else
      # Nueva versión, añadir
      updated_versions = [metadata | module_versions]

      new_state = %{
        state
        | by_module: Map.put(state.by_module, module, updated_versions),
          by_version: Map.put(state.by_version, version, metadata)
      }

      {:reply, {:ok, metadata}, new_state}
    end
  end

  @impl true
  def handle_call({:lookup, module}, _from, state) do
    case Map.get(state.by_module, module) do
      nil ->
        {:reply, {:error, :not_found}, state}

      [latest | _rest] ->
        {:reply, {:ok, latest}, state}
    end
  end

  @impl true
  def handle_call({:lookup_version, version}, _from, state) do
    case Map.get(state.by_version, version) do
      nil -> {:reply, {:error, :not_found}, state}
      metadata -> {:reply, {:ok, metadata}, state}
    end
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    # Retornar la versión más reciente de cada workflow
    all_workflows =
      state.by_module
      |> Map.values()
      |> Enum.map(fn [latest | _rest] -> latest end)

    {:reply, all_workflows, state}
  end

  @impl true
  def handle_call({:list_versions, module}, _from, state) do
    versions = Map.get(state.by_module, module, [])
    {:reply, versions, state}
  end
end
