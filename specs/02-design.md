# Design Document - Cerebelum Core

**Module:** cerebelum-core
**Version:** 0.1.0
**Status:** Draft

## Overview

Cerebelum Core is the foundational workflow orchestration engine built on Clean Architecture principles. This document provides the complete technical design for implementation.

**Key Design Principles:**
- Clean Architecture with strict layer separation
- SOLID principles throughout
- OTP supervision trees for fault tolerance
- Event sourcing as source of truth
- Deterministic execution via transparent interception

---

## System Architecture

### High-Level Architecture

```mermaid
graph TB
    subgraph "Presentation Layer (Optional - via cerebelum-web)"
        HTTP[HTTP API]
    end

    subgraph "Application Layer"
        UC_CREATE[CreateWorkflow]
        UC_EXECUTE[ExecuteWorkflow]
        UC_REPLAY[ReplayExecution]
        UC_STATUS[GetExecutionStatus]
    end

    subgraph "Domain Layer (Pure Business Logic)"
        WORKFLOW[Workflow Entity]
        EXECUTION[Execution Entity]
        NODE[Node Entity]
        SERVICES[Domain Services]
        PORTS[Ports/Behaviours]
    end

    subgraph "Infrastructure Layer"
        REPO[Ecto Repositories]
        EVENTSTORE[Event Store GenServer]
        TIMEMGR[TimeManager GenServer]
        RANDMGR[RandomnessManager GenServer]
        MEMOMGR[MemoizationManager GenServer]
        REPLAYENG[ReplayEngine GenServer]
    end

    subgraph "External"
        DB[(PostgreSQL)]
    end

    HTTP --> UC_CREATE
    HTTP --> UC_EXECUTE

    UC_CREATE --> SERVICES
    UC_EXECUTE --> SERVICES
    UC_REPLAY --> REPLAYENG

    SERVICES --> WORKFLOW
    SERVICES --> EXECUTION
    SERVICES --> PORTS

    PORTS -.implements.-> REPO
    PORTS -.implements.-> EVENTSTORE
    PORTS -.implements.-> TIMEMGR

    REPO --> DB
    EVENTSTORE --> DB
```

---

## Clean Architecture Layers

### Layer 1: Domain Layer (Pure Business Logic)

**Location:** `lib/cerebelum/domain/`

**Rules:**
- NO external dependencies (no Ecto, no Phoenix, no HTTP)
- Only depends on Elixir stdlib
- Defines Ports (behaviours) for external dependencies
- Contains ALL business logic

#### Entities

```elixir
# lib/cerebelum/domain/entities/workflow.ex
defmodule Cerebelum.Domain.Entities.Workflow do
  @moduledoc """
  Workflow aggregate root.
  """

  @enforce_keys [:id, :name, :definition, :entrypoint, :version]
  defstruct [
    :id,           # UUID
    :name,         # String
    :definition,   # Map (workflow DSL)
    :entrypoint,   # String (node ID)
    :version,      # Integer
    :nodes,        # Map of node_id => Node
    :edges,        # List of {from, to, condition}
    :created_at,   # DateTime
    :updated_at    # DateTime
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    definition: map(),
    entrypoint: String.t(),
    version: integer(),
    nodes: %{String.t() => Node.t()},
    edges: list({String.t(), String.t(), function()}),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  @doc """
  Creates a new workflow from definition.
  Validates structure and returns {:ok, workflow} or {:error, reason}.
  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(definition) do
    # Validation logic here
  end

  @doc "Validates workflow structure"
  @spec validate(t()) :: :ok | {:error, list(String.t())}
  def validate(%__MODULE__{} = workflow) do
    # Validate nodes, edges, cycles, entrypoint
  end
end
```

```elixir
# lib/cerebelum/domain/entities/execution.ex
defmodule Cerebelum.Domain.Entities.Execution do
  @moduledoc """
  Workflow execution aggregate.
  """

  alias Cerebelum.Domain.ValueObjects.{ExecutionId, ExecutionStatus}

  @enforce_keys [:id, :workflow_id, :status]
  defstruct [
    :id,              # ExecutionId
    :workflow_id,     # UUID
    :status,          # ExecutionStatus
    :input,           # Map
    :output,          # Map
    :context,         # Map (execution state)
    :started_at,      # DateTime
    :completed_at,    # DateTime
    :error           # Map (if failed)
  ]

  @type t :: %__MODULE__{
    id: ExecutionId.t(),
    workflow_id: String.t(),
    status: ExecutionStatus.t(),
    input: map(),
    output: map() | nil,
    context: map(),
    started_at: DateTime.t() | nil,
    completed_at: DateTime.t() | nil,
    error: map() | nil
  }

  @doc "Creates new execution in pending status"
  @spec new(workflow_id :: String.t(), input :: map()) :: t()
  def new(workflow_id, input) do
    %__MODULE__{
      id: ExecutionId.generate(),
      workflow_id: workflow_id,
      status: ExecutionStatus.pending(),
      input: input,
      context: %{}
    }
  end

  @doc "Transitions execution to running"
  @spec start(t()) :: {:ok, t()} | {:error, String.t()}
  def start(%__MODULE__{status: status} = execution) do
    case ExecutionStatus.can_transition?(status, :running) do
      true ->
        {:ok, %{execution |
          status: ExecutionStatus.running(),
          started_at: DateTime.utc_now()
        }}
      false ->
        {:error, "Cannot start execution in #{status} state"}
    end
  end

  @doc "Marks execution as completed"
  @spec complete(t(), output :: map()) :: {:ok, t()}
  def complete(execution, output) do
    {:ok, %{execution |
      status: ExecutionStatus.completed(),
      output: output,
      completed_at: DateTime.utc_now()
    }}
  end

  @doc "Marks execution as failed"
  @spec fail(t(), error :: map()) :: {:ok, t()}
  def fail(execution, error) do
    {:ok, %{execution |
      status: ExecutionStatus.failed(),
      error: error,
      completed_at: DateTime.utc_now()
    }}
  end
end
```

```elixir
# lib/cerebelum/domain/entities/node.ex
defmodule Cerebelum.Domain.Entities.Node do
  @moduledoc """
  Workflow node entity.
  """

  @enforce_keys [:id, :type, :config]
  defstruct [:id, :type, :config, :next_nodes]

  @type node_type :: :function | :map | :conditional | :parallel | :sequential | :delay

  @type t :: %__MODULE__{
    id: String.t(),
    type: node_type(),
    config: map(),
    next_nodes: list(String.t())
  }

  @doc "Validates node configuration"
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{type: type, config: config}) do
    # Type-specific validation
  end
end
```

#### Value Objects

```elixir
# lib/cerebelum/domain/value_objects/execution_id.ex
defmodule Cerebelum.Domain.ValueObjects.ExecutionId do
  @moduledoc """
  Execution ID value object.
  """

  @type t :: String.t()

  @spec generate() :: t()
  def generate, do: "exec-" <> UUID.uuid4()

  @spec valid?(t()) :: boolean()
  def valid?(id) when is_binary(id), do: String.starts_with?(id, "exec-")
  def valid?(_), do: false
end
```

```elixir
# lib/cerebelum/domain/value_objects/execution_status.ex
defmodule Cerebelum.Domain.ValueObjects.ExecutionStatus do
  @moduledoc """
  Execution status value object with state machine.
  """

  @type t :: :pending | :running | :completed | :failed | :paused

  @valid_statuses [:pending, :running, :completed, :failed, :paused]

  @transitions %{
    pending: [:running],
    running: [:completed, :failed, :paused],
    paused: [:running, :failed],
    completed: [],
    failed: []
  }

  def pending, do: :pending
  def running, do: :running
  def completed, do: :completed
  def failed, do: :failed
  def paused, do: :paused

  @spec valid?(t()) :: boolean()
  def valid?(status), do: status in @valid_statuses

  @spec can_transition?(t(), t()) :: boolean()
  def can_transition?(from, to) do
    to in Map.get(@transitions, from, [])
  end
end
```

#### Domain Services

```elixir
# lib/cerebelum/domain/services/workflow_validator.ex
defmodule Cerebelum.Domain.Services.WorkflowValidator do
  @moduledoc """
  Domain service for validating workflow definitions.
  """

  alias Cerebelum.Domain.Entities.{Workflow, Node}

  @spec validate(Workflow.t()) :: :ok | {:error, list(String.t())}
  def validate(workflow) do
    errors = []
    |> validate_entrypoint(workflow)
    |> validate_nodes(workflow)
    |> validate_edges(workflow)
    |> detect_cycles(workflow)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_entrypoint(errors, %{entrypoint: ep, nodes: nodes}) do
    if Map.has_key?(nodes, ep) do
      errors
    else
      ["Entrypoint '#{ep}' not found in nodes" | errors]
    end
  end

  defp validate_nodes(errors, %{nodes: nodes}) do
    Enum.reduce(nodes, errors, fn {_id, node}, acc ->
      case Node.validate(node) do
        :ok -> acc
        {:error, reason} -> [reason | acc]
      end
    end)
  end

  defp validate_edges(errors, %{edges: edges, nodes: nodes}) do
    Enum.reduce(edges, errors, fn {from, to, _condition}, acc ->
      cond do
        not Map.has_key?(nodes, from) ->
          ["Edge references unknown node: #{from}" | acc]
        not Map.has_key?(nodes, to) ->
          ["Edge references unknown node: #{to}" | acc]
        true ->
          acc
      end
    end)
  end

  defp detect_cycles(errors, workflow) do
    case has_cycle?(workflow) do
      false -> errors
      true -> ["Workflow contains cycles without max_iterations" | errors]
    end
  end

  defp has_cycle?(%{edges: edges, nodes: nodes}) do
    # Implement cycle detection using DFS
    # Allow cycles only if max_iterations is set
  end
end
```

```elixir
# lib/cerebelum/domain/services/execution_orchestrator.ex
defmodule Cerebelum.Domain.Services.ExecutionOrchestrator do
  @moduledoc """
  Domain service for orchestrating workflow execution.
  Coordinates node execution following graph edges.
  """

  alias Cerebelum.Domain.Entities.{Workflow, Execution, Node}
  alias Cerebelum.Domain.Ports.{TimeProvider, EventStore}

  @type execution_context :: %{
    workflow: Workflow.t(),
    execution: Execution.t(),
    current_node: String.t(),
    iteration: integer()
  }

  @doc "Executes workflow from entrypoint"
  @spec execute(Workflow.t(), Execution.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(workflow, execution, opts) do
    time_provider = Keyword.get(opts, :time_provider)
    event_store = Keyword.get(opts, :event_store)

    context = %{
      workflow: workflow,
      execution: execution,
      current_node: workflow.entrypoint,
      iteration: 0,
      time_provider: time_provider,
      event_store: event_store
    }

    execute_node(context)
  end

  defp execute_node(context) do
    # Node execution logic
    # 1. Get current node
    # 2. Execute based on type
    # 3. Emit events
    # 4. Evaluate edges
    # 5. Continue to next node(s)
  end
end
```

#### Domain Ports (Behaviours)

```elixir
# lib/cerebelum/domain/ports/workflow_repository.ex
defmodule Cerebelum.Domain.Ports.WorkflowRepository do
  @moduledoc """
  Port for workflow persistence.
  """

  alias Cerebelum.Domain.Entities.Workflow

  @callback create(Workflow.t()) :: {:ok, Workflow.t()} | {:error, term()}
  @callback get(id :: String.t()) :: {:ok, Workflow.t()} | {:error, :not_found}
  @callback update(Workflow.t()) :: {:ok, Workflow.t()} | {:error, term()}
  @callback list(filters :: map()) :: {:ok, list(Workflow.t())}
  @callback delete(id :: String.t()) :: :ok | {:error, term()}
end
```

```elixir
# lib/cerebelum/domain/ports/execution_repository.ex
defmodule Cerebelum.Domain.Ports.ExecutionRepository do
  @moduledoc """
  Port for execution persistence.
  """

  alias Cerebelum.Domain.Entities.Execution

  @callback create(Execution.t()) :: {:ok, Execution.t()} | {:error, term()}
  @callback get(id :: String.t()) :: {:ok, Execution.t()} | {:error, :not_found}
  @callback update(Execution.t()) :: {:ok, Execution.t()} | {:error, term()}
  @callback list(filters :: map()) :: {:ok, list(Execution.t())}
end
```

```elixir
# lib/cerebelum/domain/ports/event_store.ex
defmodule Cerebelum.Domain.Ports.EventStore do
  @moduledoc """
  Port for event sourcing.
  """

  alias Cerebelum.Domain.Events.WorkflowEvent

  @callback append(execution_id :: String.t(), events :: list(WorkflowEvent.t())) ::
    :ok | {:error, term()}

  @callback get_events(execution_id :: String.t()) ::
    {:ok, list(WorkflowEvent.t())} | {:error, term()}

  @callback get_events(execution_id :: String.t(), from :: integer(), to :: integer()) ::
    {:ok, list(WorkflowEvent.t())} | {:error, term()}

  @callback subscribe(execution_id :: String.t(), pid()) :: :ok
  @callback unsubscribe(execution_id :: String.t(), pid()) :: :ok
end
```

```elixir
# lib/cerebelum/domain/ports/time_provider.ex
defmodule Cerebelum.Domain.Ports.TimeProvider do
  @moduledoc """
  Port for time operations (deterministic or real).
  """

  @callback now() :: DateTime.t()
  @callback now(execution_id :: String.t()) :: DateTime.t()
  @callback sleep(ms :: integer()) :: :ok
  @callback sleep(execution_id :: String.t(), ms :: integer()) :: :ok
  @callback schedule(execution_id :: String.t(), delay :: integer(), callback :: function()) :: :ok
end
```

```elixir
# lib/cerebelum/domain/ports/random_provider.ex
defmodule Cerebelum.Domain.Ports.RandomProvider do
  @moduledoc """
  Port for random operations (deterministic or real).
  """

  @callback uniform() :: float()
  @callback uniform(execution_id :: String.t()) :: float()
  @callback uniform(n :: pos_integer()) :: pos_integer()
  @callback uniform(execution_id :: String.t(), n :: pos_integer()) :: pos_integer()
  @callback seed(execution_id :: String.t(), seed :: integer()) :: :ok
  @callback generate_uuid(execution_id :: String.t()) :: String.t()
end
```

#### Domain Events

```elixir
# lib/cerebelum/domain/events/workflow_event.ex
defmodule Cerebelum.Domain.Events.WorkflowEvent do
  @moduledoc """
  Base module for workflow events.
  """

  @type event_type ::
    :execution_started |
    :node_started |
    :node_completed |
    :node_failed |
    :execution_completed |
    :execution_failed |
    :checkpoint_created

  @type t :: %{
    id: String.t(),
    execution_id: String.t(),
    type: event_type(),
    payload: map(),
    timestamp: DateTime.t(),
    sequence: integer()
  }

  @spec new(event_type(), String.t(), map()) :: t()
  def new(type, execution_id, payload) do
    %{
      id: UUID.uuid4(),
      execution_id: execution_id,
      type: type,
      payload: payload,
      timestamp: DateTime.utc_now(),
      sequence: nil  # Set by event store
    }
  end
end
```

---

### Layer 2: Application Layer (Use Cases)

**Location:** `lib/cerebelum/application/`

**Rules:**
- Orchestrates domain objects
- Calls domain services
- Uses ports (not concrete implementations)
- No business logic (that's in domain)

#### Use Cases

```elixir
# lib/cerebelum/application/use_cases/create_workflow.ex
defmodule Cerebelum.Application.UseCases.CreateWorkflow do
  @moduledoc """
  Use case: Create a new workflow.
  """

  alias Cerebelum.Domain.Entities.Workflow
  alias Cerebelum.Domain.Services.WorkflowValidator
  alias Cerebelum.Domain.Ports.WorkflowRepository

  @type params :: %{
    name: String.t(),
    definition: map()
  }

  @spec execute(params(), WorkflowRepository.t()) ::
    {:ok, Workflow.t()} | {:error, term()}
  def execute(params, repository) do
    with {:ok, workflow} <- Workflow.new(params),
         :ok <- WorkflowValidator.validate(workflow),
         {:ok, persisted} <- repository.create(workflow) do
      {:ok, persisted}
    end
  end
end
```

```elixir
# lib/cerebelum/application/use_cases/execute_workflow.ex
defmodule Cerebelum.Application.UseCases.ExecuteWorkflow do
  @moduledoc """
  Use case: Execute a workflow (async via worker).
  """

  alias Cerebelum.Domain.Entities.Execution
  alias Cerebelum.Domain.Ports.{WorkflowRepository, ExecutionRepository}

  @type params :: %{
    workflow_id: String.t(),
    input: map()
  }

  @spec execute(params(), keyword()) :: {:ok, Execution.t()} | {:error, term()}
  def execute(%{workflow_id: workflow_id, input: input}, opts) do
    workflow_repo = Keyword.fetch!(opts, :workflow_repository)
    execution_repo = Keyword.fetch!(opts, :execution_repository)
    worker_pool = Keyword.fetch!(opts, :worker_pool)

    with {:ok, _workflow} <- workflow_repo.get(workflow_id),
         execution <- Execution.new(workflow_id, input),
         {:ok, persisted} <- execution_repo.create(execution),
         :ok <- enqueue_execution(worker_pool, persisted.id) do
      {:ok, persisted}
    end
  end

  defp enqueue_execution(worker_pool, execution_id) do
    # Enqueue to worker pool (Infrastructure concern)
    GenServer.cast(worker_pool, {:execute, execution_id})
    :ok
  end
end
```

```elixir
# lib/cerebelum/application/use_cases/replay_execution.ex
defmodule Cerebelum.Application.UseCases.ReplayExecution do
  @moduledoc """
  Use case: Replay a workflow execution.
  """

  alias Cerebelum.Domain.Ports.{ExecutionRepository, EventStore}

  @spec execute(execution_id :: String.t(), keyword()) ::
    {:ok, map()} | {:error, term()}
  def execute(execution_id, opts) do
    execution_repo = Keyword.fetch!(opts, :execution_repository)
    event_store = Keyword.fetch!(opts, :event_store)
    replay_engine = Keyword.fetch!(opts, :replay_engine)

    with {:ok, execution} <- execution_repo.get(execution_id),
         {:ok, events} <- event_store.get_events(execution_id),
         {:ok, result} <- replay_engine.replay(execution, events) do
      {:ok, result}
    end
  end
end
```

---

### Layer 3: Infrastructure Layer

**Location:** `lib/cerebelum/infrastructure/`

**Rules:**
- Implements domain ports
- Contains all external dependencies (Ecto, HTTP, etc.)
- GenServers for stateful components
- Database access

#### Repositories (Ecto)

```elixir
# lib/cerebelum/infrastructure/repositories/ecto_workflow_repository.ex
defmodule Cerebelum.Infrastructure.Repositories.EctoWorkflowRepository do
  @moduledoc """
  Ecto implementation of WorkflowRepository port.
  """

  @behaviour Cerebelum.Domain.Ports.WorkflowRepository

  alias Cerebelum.Infrastructure.Persistence.Schemas.WorkflowSchema
  alias Cerebelum.Domain.Entities.Workflow
  alias Cerebelum.Repo

  @impl true
  def create(workflow) do
    workflow
    |> to_schema()
    |> Repo.insert()
    |> case do
      {:ok, schema} -> {:ok, to_entity(schema)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def get(id) do
    case Repo.get(WorkflowSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def update(workflow) do
    # Implementation
  end

  @impl true
  def list(filters) do
    # Implementation with Ecto queries
  end

  @impl true
  def delete(id) do
    # Soft delete implementation
  end

  # Mappers
  defp to_schema(%Workflow{} = workflow) do
    %WorkflowSchema{
      id: workflow.id,
      name: workflow.name,
      definition: workflow.definition,
      version: workflow.version,
      # ... more fields
    }
  end

  defp to_entity(%WorkflowSchema{} = schema) do
    %Workflow{
      id: schema.id,
      name: schema.name,
      definition: schema.definition,
      version: schema.version,
      # ... more fields
    }
  end
end
```

#### Event Store (GenServer)

```elixir
# lib/cerebelum/infrastructure/event_store/postgres_event_store.ex
defmodule Cerebelum.Infrastructure.EventStore.PostgresEventStore do
  @moduledoc """
  Event store implementation using PostgreSQL + Phoenix PubSub.
  """

  use GenServer

  @behaviour Cerebelum.Domain.Ports.EventStore

  alias Cerebelum.Infrastructure.Persistence.Schemas.EventSchema
  alias Cerebelum.Domain.Events.WorkflowEvent
  alias Cerebelum.Repo

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def append(execution_id, events) do
    GenServer.call(__MODULE__, {:append, execution_id, events})
  end

  @impl true
  def get_events(execution_id) do
    GenServer.call(__MODULE__, {:get_events, execution_id})
  end

  @impl true
  def get_events(execution_id, from, to) do
    GenServer.call(__MODULE__, {:get_events, execution_id, from, to})
  end

  @impl true
  def subscribe(execution_id, pid) do
    Phoenix.PubSub.subscribe(Cerebelum.PubSub, "execution:#{execution_id}")
  end

  @impl true
  def unsubscribe(execution_id, pid) do
    Phoenix.PubSub.unsubscribe(Cerebelum.PubSub, "execution:#{execution_id}")
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:append, execution_id, events}, _from, state) do
    result =
      events
      |> Enum.with_index()
      |> Enum.map(fn {event, idx} ->
        %EventSchema{
          id: UUID.uuid4(),
          execution_id: execution_id,
          event_type: Atom.to_string(event.type),
          payload: event.payload,
          sequence: get_next_sequence(execution_id) + idx,
          timestamp: event.timestamp
        }
      end)
      |> Enum.map(&Repo.insert!/1)

    # Broadcast via PubSub
    Enum.each(result, fn event ->
      Phoenix.PubSub.broadcast(
        Cerebelum.PubSub,
        "execution:#{execution_id}",
        {:event, to_domain_event(event)}
      )
    end)

    {:reply, :ok, state}
  end

  defp get_next_sequence(execution_id) do
    # Get max sequence for this execution
    from(e in EventSchema,
      where: e.execution_id == ^execution_id,
      select: max(e.sequence)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end
end
```

#### Deterministic System

```elixir
# lib/cerebelum/infrastructure/deterministic/time_manager.ex
defmodule Cerebelum.Infrastructure.Deterministic.TimeManager do
  @moduledoc """
  Deterministic time management using virtual clocks.
  """

  use GenServer

  @behaviour Cerebelum.Domain.Ports.TimeProvider

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def now do
    DateTime.utc_now()  # Real time
  end

  @impl true
  def now(execution_id) do
    GenServer.call(__MODULE__, {:now, execution_id})
  end

  @impl true
  def sleep(ms), do: Process.sleep(ms)

  @impl true
  def sleep(execution_id, ms) do
    GenServer.call(__MODULE__, {:sleep, execution_id, ms})
  end

  @impl true
  def schedule(execution_id, delay, callback) do
    GenServer.cast(__MODULE__, {:schedule, execution_id, delay, callback})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # State: execution_id => %{current_time: DateTime, scheduled: []}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:now, execution_id}, _from, state) do
    virtual_time = get_virtual_time(state, execution_id)
    {:reply, virtual_time, state}
  end

  @impl true
  def handle_call({:sleep, execution_id, ms}, _from, state) do
    # Advance virtual time WITHOUT actual sleeping
    new_state = advance_time(state, execution_id, ms)
    {:reply, :ok, new_state}
  end

  defp get_virtual_time(state, execution_id) do
    case Map.get(state, execution_id) do
      nil ->
        # Initialize virtual clock
        DateTime.utc_now()
      %{current_time: time} ->
        time
    end
  end

  defp advance_time(state, execution_id, ms) do
    current = get_virtual_time(state, execution_id)
    new_time = DateTime.add(current, ms, :millisecond)

    Map.put(state, execution_id, %{
      current_time: new_time,
      scheduled: Map.get(state, execution_id, %{})[:scheduled] || []
    })
  end
end
```

```elixir
# lib/cerebelum/infrastructure/deterministic/randomness_manager.ex
defmodule Cerebelum.Infrastructure.Deterministic.RandomnessManager do
  @moduledoc """
  Deterministic randomness using seeded RNG per execution.
  """

  use GenServer

  @behaviour Cerebelum.Domain.Ports.RandomProvider

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def uniform do
    :rand.uniform()  # Real random
  end

  @impl true
  def uniform(execution_id) do
    GenServer.call(__MODULE__, {:uniform, execution_id})
  end

  @impl true
  def uniform(n) when is_integer(n) do
    :rand.uniform(n)  # Real random
  end

  @impl true
  def uniform(execution_id, n) when is_integer(n) do
    GenServer.call(__MODULE__, {:uniform_n, execution_id, n})
  end

  @impl true
  def seed(execution_id, seed) do
    GenServer.cast(__MODULE__, {:seed, execution_id, seed})
  end

  @impl true
  def generate_uuid(execution_id) do
    GenServer.call(__MODULE__, {:generate_uuid, execution_id})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # State: execution_id => rand_state
    {:ok, %{}}
  end

  @impl true
  def handle_call({:uniform, execution_id}, _from, state) do
    {value, new_rand_state} =
      state
      |> get_rand_state(execution_id)
      |> :rand.uniform_s()

    new_state = Map.put(state, execution_id, new_rand_state)
    {:reply, value, new_state}
  end

  defp get_rand_state(state, execution_id) do
    case Map.get(state, execution_id) do
      nil ->
        # Initialize with seed derived from execution_id
        seed = :erlang.phash2(execution_id)
        :rand.seed(:exsplus, {seed, seed, seed})
      rand_state ->
        rand_state
    end
  end
end
```

---

## Database Schema (Ecto)

### Schemas

```elixir
# lib/cerebelum/infrastructure/persistence/schemas/workflow_schema.ex
defmodule Cerebelum.Infrastructure.Persistence.Schemas.WorkflowSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "workflows" do
    field :name, :string
    field :version, :integer
    field :definition, :map
    field :entrypoint, :string

    has_many :executions, Cerebelum.Infrastructure.Persistence.Schemas.ExecutionSchema

    timestamps()
  end

  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:name, :version, :definition, :entrypoint])
    |> validate_required([:name, :definition, :entrypoint])
    |> unique_constraint([:name, :version])
  end
end
```

```elixir
# lib/cerebelum/infrastructure/persistence/schemas/execution_schema.ex
defmodule Cerebelum.Infrastructure.Persistence.Schemas.ExecutionSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "executions" do
    field :workflow_id, :binary_id
    field :status, Ecto.Enum, values: [:pending, :running, :completed, :failed, :paused]
    field :input, :map
    field :output, :map
    field :context, :map
    field :error, :map
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :workflow, Cerebelum.Infrastructure.Persistence.Schemas.WorkflowSchema,
      define_field: false

    timestamps()
  end
end
```

### Migrations

```elixir
# priv/repo/migrations/20241031_create_workflows.exs
defmodule Cerebelum.Repo.Migrations.CreateWorkflows do
  use Ecto.Migration

  def change do
    create table(:workflows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :version, :integer, null: false, default: 1
      add :definition, :map, null: false
      add :entrypoint, :string, null: false

      timestamps()
    end

    create unique_index(:workflows, [:name, :version])
    create index(:workflows, [:name])
  end
end
```

```elixir
# priv/repo/migrations/20241031_create_executions.exs
defmodule Cerebelum.Repo.Migrations.CreateExecutions do
  use Ecto.Migration

  def change do
    create table(:executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workflow_id, references(:workflows, type: :binary_id, on_delete: :restrict)
      add :status, :string, null: false, default: "pending"
      add :input, :map
      add :output, :map
      add :context, :map, default: %{}
      add :error, :map
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:executions, [:workflow_id])
    create index(:executions, [:status])
    create index(:executions, [:started_at])
  end
end
```

```elixir
# priv/repo/migrations/20241031_create_events.exs
defmodule Cerebelum.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:executions, type: :binary_id, on_delete: :delete_all)
      add :event_type, :string, null: false
      add :payload, :map
      add :sequence, :integer, null: false
      add :timestamp, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create index(:events, [:execution_id, :sequence])
    create unique_index(:events, [:execution_id, :sequence])
  end
end
```

---

## Directory Structure

```
lib/cerebelum/
├── domain/                                    # Pure business logic
│   ├── entities/
│   │   ├── workflow.ex
│   │   ├── execution.ex
│   │   └── node.ex
│   ├── value_objects/
│   │   ├── execution_id.ex
│   │   ├── execution_status.ex
│   │   └── node_config.ex
│   ├── services/
│   │   ├── workflow_validator.ex
│   │   ├── execution_orchestrator.ex
│   │   └── node_executor.ex
│   ├── ports/
│   │   ├── workflow_repository.ex
│   │   ├── execution_repository.ex
│   │   ├── event_store.ex
│   │   ├── time_provider.ex
│   │   └── random_provider.ex
│   └── events/
│       └── workflow_event.ex
│
├── application/                               # Use cases
│   └── use_cases/
│       ├── create_workflow.ex
│       ├── execute_workflow.ex
│       ├── replay_execution.ex
│       ├── get_execution_status.ex
│       └── pause_execution.ex
│
├── infrastructure/                            # External dependencies
│   ├── repositories/
│   │   ├── ecto_workflow_repository.ex
│   │   └── ecto_execution_repository.ex
│   ├── event_store/
│   │   └── postgres_event_store.ex
│   ├── deterministic/
│   │   ├── time_manager.ex
│   │   ├── randomness_manager.ex
│   │   ├── memoization_manager.ex
│   │   └── replay_engine.ex
│   ├── persistence/
│   │   └── schemas/
│   │       ├── workflow_schema.ex
│   │       ├── execution_schema.ex
│   │       └── event_schema.ex
│   └── workers/
│       ├── workflow_worker.ex
│       └── worker_supervisor.ex
│
├── repo.ex                                    # Ecto Repo
└── application.ex                             # OTP Application

test/cerebelum/
├── domain/
│   ├── entities/
│   ├── value_objects/
│   └── services/
├── application/
│   └── use_cases/
└── infrastructure/
    ├── repositories/
    └── deterministic/
```

---

## Supervision Tree

```elixir
# lib/cerebelum/application.ex
defmodule Cerebelum.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Database
      Cerebelum.Repo,

      # PubSub
      {Phoenix.PubSub, name: Cerebelum.PubSub},

      # Event Store
      Cerebelum.Infrastructure.EventStore.PostgresEventStore,

      # Deterministic System
      {Cerebelum.Infrastructure.Deterministic.Supervisor, []},

      # Worker Pool
      {Cerebelum.Infrastructure.Workers.WorkerSupervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Cerebelum.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

```elixir
# lib/cerebelum/infrastructure/deterministic/supervisor.ex
defmodule Cerebelum.Infrastructure.Deterministic.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      Cerebelum.Infrastructure.Deterministic.TimeManager,
      Cerebelum.Infrastructure.Deterministic.RandomnessManager,
      Cerebelum.Infrastructure.Deterministic.MemoizationManager,
      Cerebelum.Infrastructure.Deterministic.ReplayEngine
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

---

## Sequence Diagrams

### Workflow Execution Flow

```mermaid
sequenceDiagram
    participant Client
    participant UC as ExecuteWorkflow UseCase
    participant WR as WorkflowRepository
    participant ER as ExecutionRepository
    participant WP as WorkerPool
    participant Worker
    participant ES as EventStore

    Client->>UC: execute(workflow_id, input)
    UC->>WR: get(workflow_id)
    WR-->>UC: {:ok, workflow}
    UC->>ER: create(execution)
    ER-->>UC: {:ok, execution}
    UC->>WP: enqueue(execution_id)
    WP-->>UC: :ok
    UC-->>Client: {:ok, execution}

    WP->>Worker: assign(execution_id)
    Worker->>ER: get(execution_id)
    Worker->>WR: get(workflow_id)
    Worker->>ES: emit(ExecutionStarted)
    Worker->>Worker: execute nodes
    Worker->>ES: emit(NodeStarted)
    Worker->>ES: emit(NodeCompleted)
    Worker->>ES: emit(ExecutionCompleted)
    Worker->>ER: update(execution)
```

### Deterministic Time Flow

```mermaid
sequenceDiagram
    participant Node as Workflow Node
    participant TM as TimeManager
    participant ES as EventStore

    Node->>TM: now(execution_id)
    TM->>TM: get virtual_time
    TM-->>Node: virtual_time
    TM->>ES: emit(TimeOperation)

    Node->>TM: sleep(execution_id, 1000ms)
    TM->>TM: advance virtual_time by 1000ms
    TM-->>Node: :ok (instant!)
    TM->>ES: emit(SleepOperation)
```

---

## State Machines

### Execution Status State Machine

```mermaid
stateDiagram-v2
    [*] --> Pending
    Pending --> Running: start()
    Running --> Completed: complete()
    Running --> Failed: fail()
    Running --> Paused: pause()
    Paused --> Running: resume()
    Paused --> Failed: cancel()
    Completed --> [*]
    Failed --> [*]
```

---

## Testing Strategy

### Unit Tests (Domain)
```elixir
# test/cerebelum/domain/entities/workflow_test.exs
defmodule Cerebelum.Domain.Entities.WorkflowTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Domain.Entities.Workflow

  describe "new/1" do
    test "creates valid workflow from definition" do
      definition = %{
        "name" => "test_workflow",
        "entrypoint" => "start",
        "nodes" => %{
          "start" => %{"type" => "function", "config" => %{}}
        }
      }

      assert {:ok, %Workflow{}} = Workflow.new(definition)
    end

    test "rejects invalid definition" do
      assert {:error, _} = Workflow.new(%{})
    end
  end
end
```

### Use Case Tests (Application)
```elixir
# test/cerebelum/application/use_cases/create_workflow_test.exs
defmodule Cerebelum.Application.UseCases.CreateWorkflowTest do
  use ExUnit.Case, async: true

  import Mox

  alias Cerebelum.Application.UseCases.CreateWorkflow

  setup :verify_on_exit!

  test "creates workflow successfully" do
    params = %{name: "test", definition: valid_definition()}

    expect(WorkflowRepositoryMock, :create, fn workflow ->
      {:ok, workflow}
    end)

    assert {:ok, workflow} = CreateWorkflow.execute(params, WorkflowRepositoryMock)
    assert workflow.name == "test"
  end
end
```

---

## Summary

This design document provides:

✅ **Complete Clean Architecture** - 4 layers with clear boundaries
✅ **All Domain Entities** - Workflow, Execution, Node with full specs
✅ **All Domain Ports** - 6 behaviours for dependency inversion
✅ **Use Cases** - 5 main use cases with dependency injection
✅ **Infrastructure** - Ecto repos, GenServers, deterministic system
✅ **Database Schema** - Complete Ecto schemas and migrations
✅ **Directory Structure** - Exact file organization
✅ **Supervision Tree** - OTP application structure
✅ **Sequence Diagrams** - Workflow execution flow
✅ **Testing Strategy** - Unit, use case, integration tests

**A development team can now start implementing with confidence.**

**Next Steps:**
1. Create `03-implementation-tasks.md` with specific tasks
2. Set up project structure: `mix new cerebelum_core`
3. Begin Phase 1: Foundation (migrations, schemas, repo)
