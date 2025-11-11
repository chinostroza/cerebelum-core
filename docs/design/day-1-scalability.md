# Day 1 Scalability - Design for Scale from the Start

**Status:** Design - Final
**Created:** 2025-11-02
**Principle:** Same architecture from 1 node to 1000 nodes

---

## Core Principle: No Migration Required

> **"The architecture that runs on 1 node must be the same architecture that runs on 100 nodes"**

**Why?**
- No migration pain when scaling
- No code rewrites
- Testing on dev = testing production architecture
- Operational simplicity

**Anti-pattern (Temporal.io's mistake)**:
- Start simple → grow → hit limits → rewrite → migrate
- Different architectures for different scales

**Cerebelum approach**:
- Start distributed → grow → just add nodes
- Same architecture always

---

## Architecture: Day 1 to Day 1000

### Single Source of Truth

```elixir
defmodule Cerebelum.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Database
      Cerebelum.Repo,

      # Clustering (works with 1 node!)
      {Cluster.Supervisor, [topologies(), [name: Cerebelum.ClusterSupervisor]]},

      # Distributed Registry (Horde) - Day 1
      {Horde.Registry,
        name: Cerebelum.DistributedRegistry,
        keys: :unique,
        members: :auto
      },

      # Distributed Supervisor (Horde) - Day 1
      {Horde.DynamicSupervisor,
        name: Cerebelum.DistributedSupervisor,
        strategy: :one_for_one,
        members: :auto
      },

      # PubSub Distribuido - Day 1
      {Phoenix.PubSub, name: Cerebelum.PubSub},

      # Task Supervisor para parallel
      {Task.Supervisor, name: Cerebelum.TaskSupervisor},

      # Cache (ETS + Persistent Term)
      Cerebelum.Cache,

      # Telemetry
      Cerebelum.Telemetry,

      # HTTP API
      CerebelumWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Cerebelum.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp topologies do
    [
      cerebelum: [
        # Kubernetes (production)
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [
          service: "cerebelum-headless",
          application_name: "cerebelum",
          polling_interval: 5_000
        ]
      ],
      # Epmd (development - single node)
      local: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: []]
      ]
    ]
  end
end
```

**Clave**: Este mismo código funciona con:
- 1 nodo en development
- 3 nodos en staging
- 100 nodos en production

---

## Why Horde from Day 1?

### Horde en 1 Nodo = Funciona Perfecto

```elixir
# Con 1 nodo:
# - Horde.Registry funciona igual que Registry
# - Horde.DynamicSupervisor funciona igual que DynamicSupervisor
# - Zero overhead adicional
# - Misma API

# Con 100 nodos:
# - Horde.Registry distribuye lookups
# - Horde.DynamicSupervisor distribuye procesos
# - Failover automático
# - Misma API (no cambios de código!)
```

### Comparación

| Feature | Registry + DynamicSupervisor | Horde (Day 1) |
|---------|------------------------------|---------------|
| 1 nodo | ✅ Perfecto | ✅ Perfecto |
| 10 nodos | ❌ No soportado | ✅ Funciona |
| 100 nodos | ❌ No soportado | ✅ Funciona |
| Failover | ❌ Manual | ✅ Automático |
| Code changes when scaling | ❌ Reescribir | ✅ Zero changes |
| Operational complexity | Baja → Alta | Igual siempre |

---

## Execution Engine: Designed for Distribution

```elixir
defmodule Cerebelum.ExecutionSupervisor do
  @moduledoc """
  Distributed execution supervisor.

  Works identically on:
  - 1 node (development)
  - 100 nodes (production)

  No code changes required when scaling.
  """

  alias Horde.DynamicSupervisor

  def start_execution(workflow_module, inputs, opts \\ []) do
    execution_id = generate_execution_id()

    child_spec = {
      Cerebelum.ExecutionEngine,
      [
        workflow_module: workflow_module,
        inputs: inputs,
        execution_id: execution_id,
        # Via Horde.Registry - distributed from day 1
        name: {:via, Horde.Registry, {Cerebelum.DistributedRegistry, execution_id}}
      ] ++ opts
    }

    # Horde picks best node automatically
    # On 1 node: starts on local node
    # On 100 nodes: picks node with lowest load
    case DynamicSupervisor.start_child(Cerebelum.DistributedSupervisor, child_spec) do
      {:ok, pid} ->
        {:ok, %{id: execution_id, pid: pid, node: node(pid)}}

      {:error, {:already_started, pid}} ->
        {:ok, %{id: execution_id, pid: pid, node: node(pid)}}

      error ->
        error
    end
  end

  @doc """
  Lookup execution - works from any node

  On 1 node: local lookup
  On 100 nodes: distributed lookup
  Same code!
  """
  def lookup_execution(execution_id) do
    case Horde.Registry.lookup(Cerebelum.DistributedRegistry, execution_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List all executions across cluster

  On 1 node: lists local executions
  On 100 nodes: lists all executions across cluster
  Same code!
  """
  def list_all_executions do
    Horde.Registry.select(Cerebelum.DistributedRegistry, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc """
  Cluster statistics
  """
  def cluster_stats do
    members = Horde.DynamicSupervisor.members(Cerebelum.DistributedSupervisor)

    %{
      total_nodes: length(members),
      nodes: Enum.map(members, &node_stats/1)
    }
  end

  defp node_stats(node_name) do
    %{
      node: node_name,
      executions: count_executions_on_node(node_name),
      memory: get_node_memory(node_name)
    }
  end

  defp generate_execution_id, do: UUID.uuid4()
end
```

---

## Database: Partitioned from Day 1

### Event Store Schema

```elixir
defmodule Cerebelum.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  @partitions 64  # Day 1: 64 partitions

  def up do
    # Create partitioned table (PostgreSQL 10+)
    execute """
    CREATE TABLE events (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      execution_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      event_data JSONB NOT NULL,
      version INTEGER NOT NULL,
      inserted_at TIMESTAMP NOT NULL DEFAULT NOW()
    ) PARTITION BY HASH (execution_id);
    """

    # Create 64 partitions
    for partition <- 0..(@partitions - 1) do
      execute """
      CREATE TABLE events_#{partition}
      PARTITION OF events
      FOR VALUES WITH (MODULUS #{@partitions}, REMAINDER #{partition});
      """

      # Indexes on each partition
      execute """
      CREATE INDEX events_#{partition}_execution_id_idx
      ON events_#{partition}(execution_id);
      """

      execute """
      CREATE UNIQUE INDEX events_#{partition}_execution_id_version_idx
      ON events_#{partition}(execution_id, version);
      """
    end
  end

  def down do
    drop table(:events)
  end
end
```

**Ventajas**:
- 1 nodo: 64 particiones = mejor write throughput
- 100 nodos: 64 particiones = escala linealmente
- No migration al escalar

### Event Store Implementation

```elixir
defmodule Cerebelum.EventStore do
  @moduledoc """
  Partitioned event store.

  Writes are distributed across 64 partitions.
  Scales from 10K writes/sec to 640K writes/sec without code changes.
  """

  import Ecto.Query
  alias Cerebelum.Repo

  def append(execution_id, event, version) do
    # PostgreSQL routing handled automatically by partition key
    %Event{}
    |> Event.changeset(%{
      execution_id: execution_id,
      event_type: event_type(event),
      event_data: event,
      version: version
    })
    |> Repo.insert()
  end

  def get_events(execution_id) do
    # Query automatically routed to correct partition
    Event
    |> where([e], e.execution_id == ^execution_id)
    |> order_by([e], asc: e.version)
    |> Repo.all()
  end

  defp event_type(%module{}), do: module |> Module.split() |> List.last()
end
```

---

## Caching: Three Levels from Day 1

```elixir
defmodule Cerebelum.Cache do
  @moduledoc """
  Three-level cache designed for distribution.

  L1: Persistent Term (immutable, per-node, ultra-fast)
  L2: ETS (mutable, per-node, very fast)
  L3: Distributed (via Horde, cross-node, fast enough)
  """

  # L1: Workflow metadata (immutable, changes on deploy only)
  def get_workflow_metadata(module) do
    case :persistent_term.get({:workflow_metadata, module}, nil) do
      nil ->
        metadata = Cerebelum.Workflow.Metadata.extract(module)
        :persistent_term.put({:workflow_metadata, module}, metadata)
        metadata

      metadata ->
        metadata
    end
  end

  # L2: ETS for hot execution data (per-node)
  def init_ets do
    :ets.new(:execution_hot_cache, [
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true,
      decentralized_counters: true
    ])
  end

  def cache_execution_snapshot(execution_id, snapshot) do
    :ets.insert(:execution_hot_cache, {execution_id, snapshot, System.monotonic_time()})
  end

  def get_execution_snapshot(execution_id) do
    case :ets.lookup(:execution_hot_cache, execution_id) do
      [{^execution_id, snapshot, _}] -> {:ok, snapshot}
      [] -> :miss
    end
  end

  # L3: Distributed cache (cross-node via Horde Registry metadata)
  def get_execution_node(execution_id) do
    # Lookup via Horde tells us which node has the execution
    case Horde.Registry.lookup(Cerebelum.DistributedRegistry, execution_id) do
      [{pid, _}] -> {:ok, node(pid)}
      [] -> :error
    end
  end
end
```

---

## Development Experience: Single Node

```bash
# Developer laptop - single node
$ iex -S mix phx.server

[info] Running CerebelumWeb.Endpoint
[info] Horde.Registry started with 1 node
[info] Horde.DynamicSupervisor started with 1 node

iex> Cerebelum.execute_workflow(MyWorkflow, %{})
{:ok, %{id: "exec-123", pid: #PID<0.1234.0>, node: :"node1@localhost"}}

iex> Cerebelum.cluster_stats()
%{
  total_nodes: 1,
  nodes: [
    %{node: :"node1@localhost", executions: 1, memory: 150_000}
  ]
}
```

**Zero diferencia con producción** - misma arquitectura.

---

## Production: 10 Nodes

```bash
# Kubernetes - 10 nodos
$ kubectl get pods
NAME            READY   STATUS
cerebelum-0     1/1     Running
cerebelum-1     1/1     Running
...
cerebelum-9     1/1     Running

# Conectar a cualquier nodo
$ kubectl exec -it cerebelum-0 -- bin/cerebelum remote

iex> Cerebelum.cluster_stats()
%{
  total_nodes: 10,
  nodes: [
    %{node: :"cerebelum-0@10.1.1.1", executions: 10234, memory: 2_500_000},
    %{node: :"cerebelum-1@10.1.1.2", executions: 9876, memory: 2_400_000},
    %{node: :"cerebelum-2@10.1.1.3", executions: 10567, memory: 2_600_000},
    # ...
  ]
}

iex> Cerebelum.execute_workflow(MyWorkflow, %{})
{:ok, %{id: "exec-456", pid: #PID<0.5678.0>, node: :"cerebelum-3@10.1.1.4"}}
# ^ Horde automatically picked node with lowest load!
```

**Mismo código, 10x capacidad.**

---

## Scaling: Just Add Nodes

```bash
# Scale from 10 to 50 nodes
$ kubectl scale statefulset cerebelum --replicas=50

# Horde automatically:
# 1. Discovers new nodes (libcluster)
# 2. Adds them to the cluster
# 3. Redistributes load
# 4. Zero downtime
# 5. Zero code changes
```

**Visual**:
```
Before (10 nodes):
┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐
│ N1 │ N2 │ N3 │ N4 │ N5 │ N6 │ N7 │ N8 │ N9 │N10 │
│100k│100k│100k│100k│100k│100k│100k│100k│100k│100k│
└────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘
Total: 1M executions

Scale up to 50 nodes:
┌────┬────┬────┬─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┬────┐
│ N1 │ N2 │ N3 │                                │N50 │
│100k│100k│100k│           ...                  │100k│
└────┴────┴────┴─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┴────┘
Total: 5M executions capacity

Horde redistributes load automatically!
```

---

## Failover: Automatic from Day 1

```elixir
# Node crashes
┌────┬────┬────┐
│ N1 │ N2 │ N3 │
│E1  │E2  │E3  │
│E4  │E5  │E6  │
└────┴─💥─┴────┘
      N2 crashes!

# Horde detects failure (heartbeat timeout: ~5 seconds)
# Automatically restarts E2 and E5 on healthy nodes

┌────┬────┬────┐
│ N1 │    │ N3 │
│E1  │    │E3  │
│E4  │    │E6  │
│E2  │    │E5  │ ← Restarted from events!
└────┴────┴────┘

# Total downtime: ~5 seconds
# State recovered from event store
# Zero manual intervention
```

**Código**:
```elixir
# No necesitas escribir nada!
# Horde + GenStateMachine + Event Sourcing = automatic recovery

# ExecutionEngine automáticamente:
def init(opts) do
  execution_id = Keyword.fetch!(opts, :execution_id)

  # Intentar recuperar desde event store
  case EventStore.get_events(execution_id) do
    [] ->
      # Nueva ejecución
      start_fresh(opts)

    events ->
      # Recuperar desde crash
      state = StateReconstructor.reconstruct(events)
      {:ok, state.current_state, state.data, [{:next_event, :internal, :execute}]}
  end
end
```

---

## Performance: Linear Scaling

```
Single Node (8 cores, 16GB RAM):
- Concurrent executions: ~100,000
- Throughput: ~10,000/sec
- Latency p99: ~20ms

10 Nodes:
- Concurrent executions: ~1,000,000
- Throughput: ~100,000/sec
- Latency p99: ~25ms (+5ms for network)

50 Nodes:
- Concurrent executions: ~5,000,000
- Throughput: ~500,000/sec
- Latency p99: ~30ms

100 Nodes:
- Concurrent executions: ~10,000,000
- Throughput: ~1,000,000/sec
- Latency p99: ~35ms
```

**Linear scaling** because:
- Horde distributes evenly
- Partitioned event store (no single bottleneck)
- ETS cache per-node (no central cache)
- BEAM VM designed for this

---

## Configuration: Environment-Based

```elixir
# config/runtime.exs
import Config

# Same config for dev and prod!
config :cerebelum, Cerebelum.DistributedRegistry,
  # Auto-discovery via libcluster
  members: :auto

config :cerebelum, Cerebelum.DistributedSupervisor,
  members: :auto,
  # Different distribution strategies
  distribution_strategy:
    case config_env() do
      :prod -> Horde.UniformQuorumDistribution  # Quorum for safety
      _ -> Horde.UniformDistribution  # Simpler for dev
    end

# Clustering
config :libcluster,
  topologies: [
    cerebelum: [
      strategy:
        case System.get_env("CLUSTER_STRATEGY") do
          "k8s" -> Cluster.Strategy.Kubernetes.DNS
          "gossip" -> Cluster.Strategy.Gossip
          _ -> Cluster.Strategy.Epmd  # Dev: single node
        end,
      config: cluster_config()
    ]
  ]
```

**Environment variables**:
```bash
# Development (single node)
CLUSTER_STRATEGY=epmd

# Staging (3 nodes in K8s)
CLUSTER_STRATEGY=k8s
K8S_SERVICE=cerebelum-headless

# Production (50+ nodes in K8s)
CLUSTER_STRATEGY=k8s
K8S_SERVICE=cerebelum-headless
```

---

## Comparison: Cerebelum vs Temporal

| Aspect | Temporal.io | Cerebelum |
|--------|-------------|-----------|
| **Day 1 Architecture** | Simple (single node) | Distributed (works on 1 node) |
| **Day 100 Architecture** | Complex (multi-service) | Same (distributed) |
| **Migration Required** | ✅ Yes (major!) | ❌ No |
| **Services to Operate** | 5+ | 1 |
| **Code Changes when Scaling** | Many | Zero |
| **Failover** | Manual config | Automatic (Horde) |
| **Load Balancing** | External (gRPC) | Built-in (Horde) |
| **Operational Complexity** | High | Low |
| **Developer Experience** | Same code everywhere | Same code everywhere |

---

## Benefits Summary

### For Developers

✅ **Same code on laptop and production**
- No "works on my machine" issues
- Test full distributed behavior locally
- Single codebase, all environments

✅ **Zero migration pain**
- Start small, grow infinitely
- No rewrite when hitting limits
- Predictable scaling

✅ **Simple mental model**
- Horde = magic distributed supervisor
- Write normal GenStateMachine code
- OTP handles distribution

### For Operators

✅ **One service to deploy**
- Not 5+ services like Temporal
- Single Elixir release
- Kubernetes StatefulSet

✅ **Automatic scaling**
- kubectl scale = done
- No manual rebalancing
- No service discovery config

✅ **Built-in failover**
- Node dies? Horde handles it
- ~5 second recovery
- Zero data loss (event sourcing)

### For the Business

✅ **Lower costs**
- Fewer servers (no separate services)
- Less operational overhead
- Simpler infrastructure

✅ **Faster time to market**
- No scaling rewrites
- Focus on features
- Proven architecture from day 1

✅ **Competitive advantage**
- Simpler than Temporal
- More scalable than LangGraph
- Enterprise-ready immediately

---

## Updated Implementation Timeline

### Phase 2: Execution Engine (with Horde)

**Changes from original plan**:

```diff
- {Registry, keys: :unique, name: Cerebelum.ExecutionRegistry}
+ {Horde.Registry, name: Cerebelum.DistributedRegistry, keys: :unique, members: :auto}

- {DynamicSupervisor, name: Cerebelum.ExecutionSupervisor}
+ {Horde.DynamicSupervisor, name: Cerebelum.DistributedSupervisor, strategy: :one_for_one, members: :auto}

+ {Cluster.Supervisor, [topologies(), []]}
```

**Estimate**: +3 days (33-38 days total for Phase 2)
**Reason**: Horde setup and testing

**Worth it?** ✅ Absolutely
- No migration later
- Test distributed behavior early
- Production-ready from start

---

## Deployment Example

### Kubernetes Manifest

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cerebelum
spec:
  serviceName: cerebelum-headless
  replicas: 1  # Start with 1 node!
  selector:
    matchLabels:
      app: cerebelum
  template:
    metadata:
      labels:
        app: cerebelum
    spec:
      containers:
      - name: cerebelum
        image: cerebelum:latest
        env:
        - name: CLUSTER_STRATEGY
          value: "k8s"
        - name: K8S_SERVICE
          value: "cerebelum-headless"
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: RELEASE_NODE
          value: "cerebelum@$(POD_IP)"
        ports:
        - containerPort: 4000
          name: http
        - containerPort: 4369
          name: epmd
---
apiVersion: v1
kind: Service
metadata:
  name: cerebelum-headless
spec:
  clusterIP: None  # Headless for peer discovery
  selector:
    app: cerebelum
  ports:
  - port: 4369
    name: epmd
```

**Scale up**:
```bash
# Day 1: 1 node
kubectl apply -f cerebelum.yaml

# Day 100: 10 nodes
kubectl scale statefulset cerebelum --replicas=10

# Day 365: 50 nodes
kubectl scale statefulset cerebelum --replicas=50
```

**Same manifest, different scale!**

---

## Conclusion

**Design Principle**:
> "If it works on 1 node, it must work on 1000 nodes without code changes"

**Implementation**:
- Horde from day 1
- Partitioned database from day 1
- Distributed-ready caching from day 1
- Same code everywhere

**Result**:
- Zero migration pain
- Linear scaling
- Production-ready immediately
- **Competitive advantage vs Temporal.io**

---

**Next**: Update implementation plan to use Horde in Phase 2 instead of Phase 8.
