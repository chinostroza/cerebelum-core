# Subworkflows Design

**Status:** Design
**Created:** 2025-11-10
**Updated:** 2025-11-10 (Communication & Error Handling)
**Related:** [Workflow Syntax](workflow-syntax.md), [Execution Engine](execution-engine-state-machine.md), [Scalability Architecture](scalability-architecture.md)

---

## Table of Contents

1. [Overview](#overview)
2. [Motivation](#motivation)
3. [Types of Subworkflows](#types-of-subworkflows)
4. [Workflow Syntax](#workflow-syntax)
5. [Parallel Communication](#parallel-communication)
6. [Context Propagation](#context-propagation)
7. [Results Management](#results-management)
8. [Error Handling](#error-handling)
9. [Implementation Architecture](#implementation-architecture)
10. [Multi-Agent Systems](#multi-agent-systems)
11. [Complete Examples](#complete-examples)
12. [Group Chat Recipe](#group-chat-recipe)
13. [Design Decisions](#design-decisions)

---

## Overview

**Subworkflows** son workflows independientes que pueden ser ejecutados desde otro workflow (workflow padre). Cada subworkflow:

- Es un módulo `Cerebelum.Workflow` completo con su propio timeline, diverge, y branch
- Se ejecuta como un proceso `ExecutionEngine` independiente
- Tiene su propio `execution_id` y event stream
- Puede ejecutarse secuencialmente o en paralelo con otros subworkflows
- Retorna resultados al workflow padre cuando completa

---

## Motivation

### Use Cases

**1. Composición de Workflows**
```elixir
# Workflow padre orquesta múltiples subworkflows
ProcessOrder
  → ValidatePayment (subworkflow)
  → FulfillOrder (subworkflow)
  → SendNotifications (subworkflow)
```

**2. Multi-Agent Systems**
```elixir
# Múltiples agentes AI trabajando en paralelo
AIAnalysis
  → [SentimentAgent, EntityAgent, SummaryAgent] (parallel)
  → ConsolidateResults
```

**3. Reusabilidad**
```elixir
# Mismo workflow usado en múltiples contextos
SendEmail (subworkflow)
  ← usado por: ProcessOrder, UserSignup, PasswordReset
```

**4. Isolation**
```elixir
# Cada subworkflow tiene su propio timeout y error handling
ParentWorkflow
  → RiskyOperation (subworkflow con timeout de 30s)
  → SafeOperation (subworkflow con timeout de 5min)
```

---

## Types of Subworkflows

### 1. Sequential Subworkflow

Ejecuta un subworkflow y espera su resultado antes de continuar.

```elixir
workflow do
  timeline do
    start()
    |> load_order()
    |> subworkflow(ValidatePayment)  # Espera resultado
    |> ship_order()
    |> finish_success()
  end
end
```

**Ejecución:**
```
timeline: start → load_order → [wait for ValidatePayment] → ship_order → finish
                                     ↓
subworkflow:                   ValidatePayment (runs independently)
```

### 2. Parallel Subworkflows

Ejecuta múltiples subworkflows en paralelo y espera todos los resultados.

```elixir
workflow do
  timeline do
    start()
    |> load_data()
    |> parallel_subworkflows([
      {SentimentAgent, extract: :text},
      {EntityAgent, extract: :text},
      {SummaryAgent, extract: :text}
    ])
    |> consolidate_results()
    |> finish_success()
  end
end
```

**Ejecución:**
```
timeline: start → load_data → [wait for all 3] → consolidate → finish
                                  ↓    ↓    ↓
subworkflows:              Sentiment Entity Summary (parallel)
```

### 3. Fire-and-Forget Subworkflow

Inicia un subworkflow pero no espera su resultado.

```elixir
workflow do
  timeline do
    start()
    |> process_order()
    |> spawn_subworkflow(SendAnalytics)  # No espera
    |> finish_success()
  end
end
```

**Ejecución:**
```
timeline: start → process_order → finish (continúa inmediatamente)
                        ↓
subworkflow:      SendAnalytics (runs async, parent doesn't wait)
```

---

## Workflow Syntax

### Option 1: Explicit Function (Recommended for MVP)

El approach más simple y explícito:

```elixir
defmodule MyApp.ParentWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> run_validation()
      |> run_processing()
      |> finish_success()
    end
  end

  def run_validation(context, _results) do
    # Ejecuta subworkflow explícitamente
    result = Cerebelum.execute_subworkflow(
      MyApp.ValidationWorkflow,
      %{
        order_id: context.order_id,
        amount: context.amount
      },
      parent_execution_id: context.execution_id
    )

    case result do
      {:ok, validation_result} ->
        {:ok, validation_result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Option 2: Declarative Syntax (Future Enhancement)

Más declarativo, requiere más machinery en el engine:

```elixir
workflow do
  timeline do
    start()
    |> load_data()
    |> subworkflow(ValidationWorkflow)
    |> process_results()
    |> finish_success()
  end
end
```

### Option 3: Parallel Subworkflows

Para ejecución paralela:

```elixir
def run_agents(context, %{load_data: data}) do
  # Retorna tuple especial para parallel execution
  {:parallel_subworkflows, [
    {SentimentAgent, %{text: data.text}},
    {EntityAgent, %{text: data.text}},
    {SummaryAgent, %{text: data.text}}
  ], timeout: 30_000}
end
```

El engine reconoce el tuple `{:parallel_subworkflows, ...}` y:
1. Inicia cada subworkflow como proceso independiente
2. Monitorea todos los procesos
3. Espera a que todos completen (o timeout)
4. Retorna mapa con resultados indexados por módulo

---

## Parallel Communication

### Overview

Parallel subworkflows can optionally communicate with each other using **PubSub-based messaging**. Communication helpers are **always available** - if you don't use them, there's zero overhead.

### Syntax: Parallel Execution

```elixir
def run_agents(context, %{load_data: data}) do
  {:parallel_subworkflows, [
    {Agent1, %{data: data}},
    {Agent2, %{data: data}},
    {Agent3, %{data: data}}
  ], timeout: 60_000}
end
```

**Default behavior:**
- Agents execute independently
- No communication between agents
- Results collected at end
- Zero PubSub overhead if helpers not used
- Scales to millions

### Communication Helpers (Always Available)

Inside any agent running in a parallel group, these helpers are available:

```elixir
defmodule ResearchAgent do
  use Cerebelum.Workflow

  def research_and_share(context, %{topic: topic}) do
    findings = conduct_research(topic)

    # Broadcast to all peers
    broadcast_to_peers(:research_complete, %{
      findings: findings,
      agent: ResearchAgent
    })

    {:ok, %{findings: findings}}
  end
end

defmodule WriterAgent do
  use Cerebelum.Workflow

  def wait_for_research(context, _deps) do
    # Wait for message from specific agent
    case receive_from_peer(ResearchAgent, :research_complete, timeout: 30_000) do
      {:ok, %{findings: findings}} ->
        {:ok, %{research_data: findings}}

      :timeout ->
        {:error, :research_timeout}
    end
  end
end
```

### Available Communication Helpers

```elixir
# Broadcast to all peers in parallel group
broadcast_to_peers(:message_type, data)

# Send to specific agent
send_to_peer(TargetModule, :message_type, data)

# Receive from any peer
case receive_from_peers(timeout: 5_000) do
  {:ok, messages} -> process(messages)
  :timeout -> continue_solo()
end

# Receive from specific peer
case receive_from_peer(SourceModule, :message_type, timeout: 5_000) do
  {:ok, data} -> process(data)
  :timeout -> handle_timeout()
end
```

### When to Use Communication

**Use communication helpers when:**
- Agents need to coordinate decisions
- One agent's result affects another's behavior
- Sequential dependencies within parallel group
- Consensus or voting mechanisms
- Agent needs to notify peers of important events

**Don't use (keep agents independent) when:**
- Independent analysis tasks (most common case)
- Data processing pipelines
- Parallel API calls
- No inter-agent dependencies needed

**Key Point:** If you never call the helpers, there's **zero PubSub overhead**. Phoenix.PubSub is lazy - no messages = no cost.

### Event Sourcing for Messages

All inter-agent messages are persisted to EventStore for debugging and replay:

**Benefits:**
- ✅ **Full replay** - See entire conversation between agents
- ✅ **Debugging** - Trace who said what and when
- ✅ **At-least-once delivery** - Re-deliver if agent crashes before processing
- ✅ **Auditing** - Complete history of agent interactions
- ✅ **Time-travel** - Replay conversations at any point in time

**Implementation:**
```elixir
# Messages are persisted as events
EventStore.append_event(parent_execution_id, %MessageSentEvent{
  message_id: UUID.uuid4(),
  from: ResearchAgent,
  to: WriterAgent,
  message_type: :research_complete,
  payload: %{findings: "..."},
  timestamp: DateTime.utc_now()
})

# Delivery via BEAM mailbox (fast)
send(agent_pid, {:msg_from_peer, sender, msg_id, message})

# Receipt is also persisted
EventStore.append_event(parent_execution_id, %MessageReceivedEvent{...})
EventStore.append_event(parent_execution_id, %MessageProcessedEvent{...})
```

**Debugging Tools:**
```elixir
# View entire conversation
Cerebelum.Debug.message_trace(execution_id)

# Check message delivery
Cerebelum.Debug.check_message_delivery(execution_id, message_id)

# Find lost messages
Cerebelum.Debug.find_lost_messages(execution_id)

# Replay conversation
Cerebelum.Debug.replay_messages(execution_id, interactive: true)

# Visualize as diagram
Cerebelum.Debug.message_diagram(execution_id)
```

**Unique Feature:** No other multi-agent framework has complete replay of agent conversations with event sourcing.

---

## Context Propagation

### Parent Context

El subworkflow puede recibir datos del contexto padre:

```elixir
# Workflow padre
def run_validation(context, _results) do
  Cerebelum.execute_subworkflow(
    ValidationWorkflow,
    %{
      # Datos del contexto padre
      order_id: context.order_id,
      user_id: context.user_id,

      # Metadata de relación
      parent_execution_id: context.execution_id
    }
  )
end
```

### Subworkflow Context

El subworkflow crea su propio contexto:

```elixir
# Subworkflow recibe estos inputs y crea su context
%Context{
  execution_id: "sub-uuid-123",  # Nuevo ID único
  parent_execution_id: "parent-uuid-456",  # Link al padre

  # User inputs (pasados por el padre)
  order_id: "order-789",
  user_id: "user-101",

  # Metadata del subworkflow
  workflow_version: "1.0.0",
  started_at: ~U[2025-11-10 10:00:00Z],
  retry_count: 0
}
```

### Context Isolation

**Importante:** El subworkflow NO tiene acceso al `results` cache del padre.

```elixir
# ❌ INCORRECTO - El subworkflow no puede acceder a results del padre
def start(context, %{parent_step: data}) do  # Esto no existe
  # ...
end

# ✅ CORRECTO - El padre pasa datos explícitamente como inputs
def run_subworkflow(context, %{some_step: data}) do
  Cerebelum.execute_subworkflow(
    ChildWorkflow,
    %{extracted_data: data.important_field}  # Pasa solo lo necesario
  )
end
```

**Rationale:** Isolation es crucial para:
- Reusabilidad (el subworkflow no depende del estado del padre)
- Testing (puedes testear el subworkflow standalone)
- Debugging (scope claro)

---

## Results Management

### Single Subworkflow Result

El resultado del subworkflow se guarda en el results cache del padre:

```elixir
workflow do
  timeline do
    start()
    |> run_validation()      # Ejecuta ValidationWorkflow
    |> process_order()       # Accede al resultado
    |> finish_success()
  end
end

def run_validation(context, _results) do
  result = Cerebelum.execute_subworkflow(ValidationWorkflow, %{...})

  # El resultado se guarda automáticamente con el nombre de esta función
  result
  # => {:ok, %{status: :valid, checks_passed: 5}}
end

def process_order(context, %{run_validation: validation}) do
  # Accede al resultado del subworkflow
  if validation.status == :valid do
    {:ok, :processed}
  else
    {:error, :invalid_order}
  end
end
```

### Parallel Subworkflows Results

Resultados indexados por módulo:

```elixir
def run_agents(context, %{load_data: data}) do
  {:parallel_subworkflows, [
    {SentimentAgent, %{text: data.text}},
    {EntityAgent, %{text: data.text}},
    {SummaryAgent, %{text: data.text}}
  ]}
end

def consolidate_results(context, %{run_agents: agents}) do
  # agents es un mapa indexado por módulo
  %{
    SentimentAgent => %{sentiment: :positive, score: 0.85},
    EntityAgent => %{entities: ["Company A", "Person B"]},
    SummaryAgent => %{summary: "..."}
  } = agents

  {:ok, %{
    sentiment: agents[SentimentAgent].sentiment,
    entities: agents[EntityAgent].entities,
    summary: agents[SummaryAgent].summary
  }}
end
```

### Nested Access Pattern

Para acceder a resultados específicos de subworkflows:

```elixir
def analyze_results(context, %{
  run_agents: %{
    SentimentAgent: %{sentiment: sentiment},
    EntityAgent: %{entities: entities}
  }
}) do
  # Pattern matching directo sobre resultados de subworkflows
  {:ok, %{sentiment: sentiment, entity_count: length(entities)}}
end
```

---

## Error Handling

### Subworkflow Failure Propagation

Cuando un subworkflow falla, el error se propaga al padre:

```elixir
workflow do
  timeline do
    start()
    |> run_risky_subworkflow()
    |> finish_success()
  end

  diverge from run_risky_subworkflow do
    # Subworkflow falló
    {:error, :subworkflow_failed} ->
      log_failure() |> finish_with_error()

    # Subworkflow completó exitosamente
    {:ok, _result} ->
      continue()
  end
end
```

### Timeout Handling

Subworkflows pueden tener timeouts independientes:

```elixir
def run_slow_subworkflow(context, _results) do
  result = Cerebelum.execute_subworkflow(
    SlowWorkflow,
    %{data: context.data},
    timeout: 30_000  # 30 segundos
  )

  case result do
    {:ok, data} -> {:ok, data}
    {:error, :timeout} -> {:error, :subworkflow_timeout}
  end
end

# Manejado en diverge
diverge from run_slow_subworkflow do
  {:error, :subworkflow_timeout} when context.retry_count < 2 ->
    increment_retry() |> back_to(run_slow_subworkflow)

  {:error, :subworkflow_timeout} ->
    finish_with_error(:max_retries_exceeded)
end
```

### Error Handling Strategies

Control how failures in parallel subworkflows are handled:

#### Strategy 1: Stop on First Failure (Default)

```elixir
def run_agents(context, %{data: data}) do
  {:parallel_subworkflows, [
    {Agent1, %{data: data}},
    {Agent2, %{data: data}},
    {Agent3, %{data: data}}
  ],
    on_failure: :stop  # If any fails, kill all and fail workflow
  }
end
```

**Use when:** All agents must succeed, partial results are useless.

#### Strategy 2: Continue on Failure

```elixir
def run_agents(context, %{data: data}) do
  {:parallel_subworkflows, [
    {Agent1, %{data: data}},
    {Agent2, %{data: data}},
    {Agent3, %{data: data}}
  ],
    on_failure: :continue,  # Let others finish even if one fails
    min_successes: 2        # Require at least 2 successes
  }
end

# Handle partial results
def consolidate(context, %{run_agents: results}) do
  case results do
    # All succeeded
    %{Agent1: {:ok, r1}, Agent2: {:ok, r2}, Agent3: {:ok, r3}} ->
      {:ok, %{full: [r1, r2, r3]}}

    # Partial success (Agent3 failed but we have min_successes: 2)
    %{Agent1: {:ok, r1}, Agent2: {:ok, r2}, Agent3: {:error, _}} ->
      {:partial, %{data: [r1, r2]}}

    # Too few successes
    _ ->
      {:error, :insufficient_results}
  end
end

diverge from consolidate do
  {:partial, data} ->
    log_warning("Partial results") |> continue_with_partial(data)

  {:error, :insufficient_results} ->
    retry_failed_agents() |> back_to(run_agents)

  {:ok, _} ->
    continue()
end
```

**Use when:** Best-effort processing, partial results are acceptable.

#### Strategy 3: Retry on Failure

```elixir
def run_agents(context, %{data: data}) do
  {:parallel_subworkflows, [
    {Agent1, %{data: data}},
    {Agent2, %{data: data}},
    {Agent3, %{data: data}}
  ],
    on_failure: :retry,
    max_retries: 3,       # Retry failed agents up to N times
    retry_delay: 5_000    # Wait 5s between retries
  }
end
```

**Use when:** Transient failures are expected (network issues, rate limits).

### Complex Error Handling Example

```elixir
defmodule RobustMultiAgent do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> run_critical_agents()
      |> run_optional_agents()
      |> consolidate_all()
      |> finish_success()
    end

    # Critical agents - must all succeed
    diverge from run_critical_agents do
      {:error, _} when context.retry_count < 3 ->
        increment_retry() |> back_to(run_critical_agents)

      {:error, reason} ->
        finish_with_error(reason)

      {:ok, _} ->
        continue()
    end

    # Optional agents - partial results OK
    diverge from run_optional_agents do
      {:partial, results} ->
        log_partial_success() |> continue()

      {:ok, results} ->
        continue()

      {:error, :all_failed} ->
        log_warning() |> continue()  # Continue anyway
    end
  end

  def run_critical_agents(context, %{start: _}) do
    {:parallel_subworkflows, [
      {ValidationAgent, %{data: context.data}},
      {SecurityAgent, %{data: context.data}}
    ], on_failure: :stop}  # Must all succeed
  end

  def run_optional_agents(context, %{run_critical_agents: critical}) do
    {:parallel_subworkflows, [
      {EnrichmentAgent, %{data: critical}},
      {AnalyticsAgent, %{data: critical}},
      {NotificationAgent, %{data: critical}}
    ],
      on_failure: :continue,
      min_successes: 1  # At least 1 must succeed
    }
  end
end
```

---

## Implementation Architecture

### ExecutionEngine State Machine Extension

Nuevo estado para manejar subworkflows:

```
:executing_step
      ↓
  (returns {:parallel_subworkflows, ...})
      ↓
:waiting_for_subworkflows
      ↓
  (all complete or timeout)
      ↓
:executing_step (next step)
```

### State: :waiting_for_subworkflows

```elixir
def executing_step(:internal, :execute, data) do
  case execute_current_step(data) do
    # ... other cases ...

    {:parallel_subworkflows, subworkflows, opts} ->
      # Inicia todos los subworkflows
      child_pids = start_parallel_subworkflows(subworkflows, data.context, opts)

      new_data = %{data |
        pending_subworkflows: child_pids,
        subworkflow_timeout: Keyword.get(opts, :timeout, 300_000)
      }

      {:next_state, :waiting_for_subworkflows, new_data}
  end
end

def waiting_for_subworkflows(:enter, _old_state, data) do
  Logger.info("Waiting for #{length(data.pending_subworkflows)} subworkflows")

  # Set timeout para todos los subworkflows
  timeout = data.subworkflow_timeout
  {:keep_state, data, [{:state_timeout, timeout, :subworkflows_timeout}]}
end

def waiting_for_subworkflows(:info, {:DOWN, ref, :process, pid, reason}, data) do
  # Un subworkflow terminó
  handle_subworkflow_completion(pid, ref, reason, data)
end

def waiting_for_subworkflows(:state_timeout, :subworkflows_timeout, data) do
  Logger.error("Subworkflows timeout")

  # Kill todos los subworkflows pendientes
  Enum.each(data.pending_subworkflows, fn {pid, _ref, _module} ->
    Process.exit(pid, :kill)
  end)

  {:next_state, :failed, %{data | error: :subworkflows_timeout}}
end

defp handle_subworkflow_completion(pid, ref, reason, data) do
  case reason do
    :normal ->
      # Subworkflow completó exitosamente
      {^pid, ^ref, workflow_mod} =
        Enum.find(data.pending_subworkflows, fn {p, r, _} ->
          p == pid and r == ref
        end)

      # Obtener resultado del event store
      result = Cerebelum.EventStore.get_final_result(pid)

      # Guardar en results cache
      new_results = Map.put(data.results, workflow_mod, result)
      new_pending = List.delete(data.pending_subworkflows, {pid, ref, workflow_mod})

      # Si todos terminaron, continuar
      if Enum.empty?(new_pending) do
        all_results = collect_all_subworkflow_results(data.pending_subworkflows, new_results)
        new_data = %{data |
          results: store_subworkflows_result(data, all_results),
          pending_subworkflows: []
        }

        {:next_state, :executing_step, new_data,
         [{:next_event, :internal, :continue_after_subworkflows}]}
      else
        {:keep_state, %{data |
          results: new_results,
          pending_subworkflows: new_pending
        }}
      end

    error ->
      # Subworkflow falló
      Logger.error("Subworkflow failed: #{inspect(error)}")
      {:next_state, :failed, %{data | error: {:subworkflow_failed, error}}}
  end
end
```

### Supervision Tree

```
Application
├── Cerebelum.WorkflowSupervisor (DynamicSupervisor via Horde)
│   ├── ParentWorkflow (ExecutionEngine - GenStateMachine)
│   ├── ChildWorkflow1 (ExecutionEngine - GenStateMachine)
│   ├── ChildWorkflow2 (ExecutionEngine - GenStateMachine)
│   └── ChildWorkflow3 (ExecutionEngine - GenStateMachine)
├── Cerebelum.Registry (Horde.Registry)
└── Cerebelum.EventStore
```

Cada subworkflow:
- Es supervisado por `Cerebelum.WorkflowSupervisor`
- Se registra en `Cerebelum.Registry` con su `execution_id`
- Tiene su propio event stream en `EventStore`
- Puede fallar sin afectar al padre (gracias a monitoring, no linking)

### Starting Subworkflows

```elixir
defmodule Cerebelum.SubworkflowRunner do
  def execute_subworkflow(workflow_module, inputs, opts \\ []) do
    parent_execution_id = Keyword.get(opts, :parent_execution_id)
    timeout = Keyword.get(opts, :timeout, 300_000)

    # Crear contexto del subworkflow
    subworkflow_inputs = Map.merge(inputs, %{
      parent_execution_id: parent_execution_id
    })

    # Iniciar como proceso supervisado
    {:ok, %{id: execution_id, pid: pid}} =
      Cerebelum.ExecutionSupervisor.start_execution(
        workflow_module,
        subworkflow_inputs,
        opts
      )

    # Esperar resultado
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        # Obtener resultado final del event store
        result = Cerebelum.EventStore.get_final_result(execution_id)
        {:ok, result}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, {:subworkflow_failed, reason}}
    after
      timeout ->
        Process.exit(pid, :kill)
        {:error, :timeout}
    end
  end

  def start_parallel_subworkflows(subworkflows, parent_context, opts) do
    Enum.map(subworkflows, fn {workflow_mod, inputs} ->
      # Inicia subworkflow
      {:ok, %{id: exec_id, pid: pid}} =
        Cerebelum.ExecutionSupervisor.start_execution(
          workflow_mod,
          Map.merge(inputs, %{parent_execution_id: parent_context.execution_id}),
          opts
        )

      # Monitorea (no link) para recibir notificación cuando termine
      ref = Process.monitor(pid)

      {pid, ref, workflow_mod, exec_id}
    end)
  end
end
```

---

## Multi-Agent Systems

### Pattern: Collaborative Agents

Múltiples agentes procesan el mismo input y consolidan resultados:

```elixir
defmodule MyApp.MultiAgentAnalysis do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> load_document()
      |> run_analysis_agents()
      |> consolidate_insights()
      |> generate_final_report()
      |> finish_success()
    end
  end

  def load_document(context) do
    doc = Documents.get!(context.document_id)
    {:ok, %{text: doc.content, metadata: doc.metadata}}
  end

  def run_analysis_agents(context, %{load_document: doc}) do
    # Ejecuta 4 agentes en paralelo
    {:parallel_subworkflows, [
      {MyApp.Agents.SentimentAnalyzer, %{text: doc.text}},
      {MyApp.Agents.EntityExtractor, %{text: doc.text}},
      {MyApp.Agents.TopicClassifier, %{text: doc.text}},
      {MyApp.Agents.KeyphraseExtractor, %{text: doc.text}}
    ], timeout: 30_000}
  end

  def consolidate_insights(context, %{run_analysis_agents: agents}) do
    %{
      MyApp.Agents.SentimentAnalyzer: sentiment,
      MyApp.Agents.EntityExtractor: entities,
      MyApp.Agents.TopicClassifier: topics,
      MyApp.Agents.KeyphraseExtractor: keyphrases
    } = agents

    consolidated = %{
      sentiment: sentiment.sentiment,
      confidence: sentiment.confidence,
      entities: entities.entities,
      topics: topics.topics,
      keyphrases: keyphrases.phrases,
      metadata: %{
        analyzed_at: DateTime.utc_now(),
        agents_used: 4
      }
    }

    {:ok, consolidated}
  end

  def generate_final_report(context, %{consolidate_insights: insights}) do
    report = ReportGenerator.create(insights)
    {:ok, report}
  end
end
```

### Pattern: Hierarchical Agents

Un agente coordinador que delega a agentes especializados:

```elixir
defmodule MyApp.HierarchicalAgent do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> coordinator_agent()
      |> execute_specialized_agents()
      |> coordinator_synthesis()
      |> finish_success()
    end
  end

  def coordinator_agent(context) do
    # El coordinador analiza el problema y decide qué agentes usar
    plan = CoordinatorAI.plan(context.task)

    {:ok, %{
      agents_to_run: plan.agents,
      strategy: plan.strategy,
      parameters: plan.parameters
    }}
  end

  def execute_specialized_agents(context, %{coordinator_agent: plan}) do
    # Ejecuta los agentes que el coordinador decidió
    subworkflows = Enum.map(plan.agents_to_run, fn agent_config ->
      {agent_config.module, agent_config.params}
    end)

    {:parallel_subworkflows, subworkflows, timeout: 60_000}
  end

  def coordinator_synthesis(context, %{
    coordinator_agent: plan,
    execute_specialized_agents: results
  }) do
    # El coordinador sintetiza los resultados
    synthesis = CoordinatorAI.synthesize(plan, results)
    {:ok, synthesis}
  end
end
```

### Pattern: Sequential Chain of Agents

Cada agente procesa el output del anterior:

```elixir
defmodule MyApp.AgentChain do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> research_agent()
      |> planning_agent()
      |> execution_agent()
      |> review_agent()
      |> finish_success()
    end
  end

  def research_agent(context) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Agents.Researcher,
      %{topic: context.topic, depth: :comprehensive}
    )
    result
  end

  def planning_agent(context, %{research_agent: research}) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Agents.Planner,
      %{research: research, goals: context.goals}
    )
    result
  end

  def execution_agent(context, %{planning_agent: plan}) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Agents.Executor,
      %{plan: plan, constraints: context.constraints}
    )
    result
  end

  def review_agent(context, %{
    research_agent: research,
    planning_agent: plan,
    execution_agent: execution
  }) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Agents.Reviewer,
      %{
        research: research,
        plan: plan,
        execution: execution,
        criteria: context.quality_criteria
      }
    )
    result
  end
end
```

---

## Complete Examples

### Example 1: E-commerce Order Processing

```elixir
defmodule MyApp.ProcessOrder do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> validate_order()
      |> process_payment()
      |> allocate_inventory()
      |> ship_order()
      |> send_notifications()
      |> finish_success()
    end

    diverge from process_payment do
      {:error, :payment_failed} ->
        cancel_order() |> finish_with_error()

      {:ok, _} ->
        continue()
    end

    diverge from allocate_inventory do
      {:error, :out_of_stock} ->
        refund_payment() |> notify_customer() |> finish_with_error()

      {:ok, _} ->
        continue()
    end
  end

  def validate_order(context) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Workflows.ValidateOrder,
      %{order_id: context.order_id}
    )
    result
  end

  def process_payment(context, %{validate_order: validation}) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Workflows.ProcessPayment,
      %{
        order_id: context.order_id,
        amount: validation.total_amount,
        payment_method: context.payment_method
      }
    )
    result
  end

  def allocate_inventory(context, %{validate_order: validation}) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Workflows.AllocateInventory,
      %{
        items: validation.items,
        warehouse_id: context.warehouse_id
      }
    )
    result
  end

  def ship_order(context, %{allocate_inventory: allocation}) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Workflows.ShipOrder,
      %{
        order_id: context.order_id,
        allocation: allocation,
        shipping_address: context.shipping_address
      }
    )
    result
  end

  def send_notifications(context, %{ship_order: shipment}) do
    # Fire-and-forget - no espera resultado
    {:parallel_subworkflows, [
      {MyApp.Workflows.SendEmail, %{
        to: context.customer_email,
        template: :order_shipped,
        data: shipment
      }},
      {MyApp.Workflows.SendSMS, %{
        to: context.customer_phone,
        message: "Your order has been shipped!"
      }},
      {MyApp.Workflows.UpdateCRM, %{
        customer_id: context.customer_id,
        event: :order_shipped
      }}
    ], on_failure: :ignore}  # Continúa aunque fallen las notificaciones
  end
end
```

### Example 2: AI Content Generation Pipeline

```elixir
defmodule MyApp.ContentGenerationPipeline do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> analyze_requirements()
      |> parallel_research()
      |> generate_outline()
      |> parallel_content_generation()
      |> quality_review()
      |> publish_content()
      |> finish_success()
    end

    branch from quality_review do
      {:ok, %{quality_score: score}} when score >= 0.8 ->
        continue()

      {:ok, %{quality_score: score}} when score >= 0.6 ->
        request_human_review() |> back_to(quality_review)

      {:ok, %{quality_score: _score}} ->
        regenerate_content() |> back_to(parallel_content_generation)
    end
  end

  def analyze_requirements(context) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Agents.RequirementsAnalyzer,
      %{brief: context.brief, target_audience: context.audience}
    )
    result
  end

  def parallel_research(context, %{analyze_requirements: reqs}) do
    {:parallel_subworkflows, [
      {MyApp.Agents.WebResearcher, %{topics: reqs.topics}},
      {MyApp.Agents.CompetitorAnalyzer, %{industry: reqs.industry}},
      {MyApp.Agents.TrendAnalyzer, %{keywords: reqs.keywords}}
    ]}
  end

  def generate_outline(context, %{
    analyze_requirements: reqs,
    parallel_research: research
  }) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Agents.OutlineGenerator,
      %{
        requirements: reqs,
        research: research,
        format: context.content_format
      }
    )
    result
  end

  def parallel_content_generation(context, %{generate_outline: outline}) do
    # Genera cada sección en paralelo
    section_workflows = Enum.map(outline.sections, fn section ->
      {MyApp.Agents.SectionWriter, %{
        section: section,
        tone: context.tone,
        style: context.style
      }}
    end)

    {:parallel_subworkflows, section_workflows, timeout: 120_000}
  end

  def quality_review(context, %{parallel_content_generation: sections}) do
    result = Cerebelum.execute_subworkflow(
      MyApp.Agents.QualityReviewer,
      %{
        sections: sections,
        criteria: context.quality_criteria
      }
    )
    result
  end

  def publish_content(context, %{
    parallel_content_generation: sections,
    quality_review: review
  }) do
    final_content = assemble_content(sections)

    result = Cerebelum.execute_subworkflow(
      MyApp.Workflows.PublishContent,
      %{
        content: final_content,
        metadata: review.metadata,
        destination: context.publish_to
      }
    )
    result
  end

  defp assemble_content(sections) do
    sections
    |> Map.values()
    |> Enum.sort_by(& &1.order)
    |> Enum.map(& &1.content)
    |> Enum.join("\n\n")
  end
end
```

---

## Group Chat Recipe

### Overview

This is a **recipe** (not a built-in feature) showing how to implement AutoGen-style group chat with automatic speaker selection using Cerebelum primitives.

### Pattern: LLM-Moderated Group Chat

Multiple agents engage in a multi-round conversation where an LLM moderator decides who speaks next:

```elixir
defmodule MyApp.GroupChatWorkflow do
  use Cerebelum.Workflow

  @moduledoc """
  Recipe for AutoGen-style group chat with automatic speaker selection.

  Agents: ResearchAgent, WriterAgent, CriticAgent
  Moderator: Uses LLM to decide who speaks next
  Termination: After max_rounds or when consensus reached
  """

  workflow do
    timeline do
      start()
      |> initialize_conversation()
      |> run_conversation_rounds()
      |> consolidate_final_output()
      |> finish_success()
    end

    # Loop for conversation rounds
    branch from run_conversation_rounds do
      {:continue, state} when state.round < state.max_rounds ->
        next_round(state) |> back_to(run_conversation_rounds)

      {:consensus, result} ->
        finalize(result) |> skip_to(consolidate_final_output)

      {:max_rounds, result} ->
        finalize(result) |> skip_to(consolidate_final_output)
    end
  end

  def initialize_conversation(context) do
    {:ok, %{
      topic: context.topic,
      agents: [ResearchAgent, WriterAgent, CriticAgent],
      history: [],
      round: 0,
      max_rounds: 10
    }}
  end

  def run_conversation_rounds(context, %{initialize_conversation: state}) do
    # Decide who speaks next using LLM
    next_speaker = select_next_speaker(state)

    # Execute that agent with conversation history
    result = Cerebelum.execute_subworkflow(
      next_speaker,
      %{
        topic: state.topic,
        history: state.history,
        round: state.round
      }
    )

    # Update conversation history
    new_history = state.history ++ [%{
      agent: next_speaker,
      round: state.round,
      message: result.message
    }]

    # Check for termination
    case check_termination(new_history, state) do
      :consensus ->
        {:consensus, %{history: new_history}}

      :continue when state.round + 1 >= state.max_rounds ->
        {:max_rounds, %{history: new_history}}

      :continue ->
        {:continue, %{state |
          history: new_history,
          round: state.round + 1
        }}
    end
  end

  defp select_next_speaker(state) do
    # Use LLM to decide who should speak next
    prompt = """
    Given this conversation history:
    #{format_history(state.history)}

    Topic: #{state.topic}
    Round: #{state.round}/#{state.max_rounds}

    Which agent should speak next?
    Available agents:
    - ResearchAgent: Provides facts and research
    - WriterAgent: Creates content
    - CriticAgent: Reviews and provides feedback

    Respond with just the agent name.
    """

    {:ok, response} = Cortex.chat([
      %{role: "system", content: "You are a conversation moderator."},
      %{role: "user", content: prompt}
    ], model: "gpt-4")

    # Parse agent name from response
    case response.content do
      "ResearchAgent" -> ResearchAgent
      "WriterAgent" -> WriterAgent
      "CriticAgent" -> CriticAgent
      _ -> Enum.random(state.agents)  # Fallback
    end
  end

  defp check_termination(history, state) do
    # Use LLM to check if consensus reached
    if state.round < 3 do
      :continue
    else
      prompt = """
      Conversation history:
      #{format_history(history)}

      Has the group reached a consensus or completed the task?
      Respond with: CONSENSUS or CONTINUE
      """

      {:ok, response} = Cortex.chat([
        %{role: "user", content: prompt}
      ], model: "gpt-4")

      if String.contains?(response.content, "CONSENSUS") do
        :consensus
      else
        :continue
      end
    end
  end

  defp format_history(history) do
    history
    |> Enum.map(fn entry ->
      "Round #{entry.round} - #{entry.agent}: #{entry.message}"
    end)
    |> Enum.join("\n")
  end

  def consolidate_final_output(context, %{run_conversation_rounds: result}) do
    # Synthesize final output from conversation
    synthesis = synthesize_conversation(result.history)
    {:ok, synthesis}
  end

  defp synthesize_conversation(history) do
    prompt = """
    Synthesize this group conversation into a final output:
    #{format_history(history)}
    """

    {:ok, response} = Cortex.chat([
      %{role: "user", content: prompt}
    ], model: "gpt-4")

    %{
      final_output: response.content,
      rounds: length(history),
      participants: Enum.map(history, & &1.agent) |> Enum.uniq()
    }
  end
end
```

### Agent Implementation

Each agent is a simple workflow that responds based on history:

```elixir
defmodule ResearchAgent do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> research()
      |> finish_success()
    end
  end

  def research(context, _deps) do
    prompt = """
    You are a Research Agent. Provide factual research about: #{context.topic}

    Previous conversation:
    #{format_history(context.history)}

    Provide your research findings (max 200 words).
    """

    {:ok, response} = Cortex.chat([
      %{role: "system", content: "You are an expert researcher."},
      %{role: "user", content: prompt}
    ], model: "gpt-4")

    {:ok, %{message: response.content}}
  end

  defp format_history(history) do
    if Enum.empty?(history) do
      "(No previous messages)"
    else
      history
      |> Enum.take(-3)  # Last 3 messages
      |> Enum.map(fn h -> "#{h.agent}: #{h.message}" end)
      |> Enum.join("\n")
    end
  end
end

defmodule WriterAgent do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> write_content()
      |> finish_success()
    end
  end

  def write_content(context, _deps) do
    prompt = """
    You are a Writer Agent. Create content about: #{context.topic}

    Previous conversation:
    #{format_history(context.history)}

    Write your content (max 200 words).
    """

    {:ok, response} = Cortex.chat([
      %{role: "system", content: "You are a creative writer."},
      %{role: "user", content: prompt}
    ], model: "gpt-4")

    {:ok, %{message: response.content}}
  end

  defp format_history(history), do: ResearchAgent.format_history(history)
end

defmodule CriticAgent do
  use Cerebelum.Workflow

  workflow do
    timeline do
      start()
      |> critique()
      |> finish_success()
    end
  end

  def critique(context, _deps) do
    prompt = """
    You are a Critic Agent. Review the conversation about: #{context.topic}

    Previous conversation:
    #{format_history(context.history)}

    Provide constructive feedback (max 200 words).
    """

    {:ok, response} = Cortex.chat([
      %{role: "system", content: "You are a constructive critic."},
      %{role: "user", content: prompt}
    ], model: "gpt-4")

    {:ok, %{message: response.content}}
  end

  defp format_history(history), do: ResearchAgent.format_history(history)
end
```

### Usage

```elixir
# Start group chat
{:ok, exec_id} = Cerebelum.execute_workflow(
  MyApp.GroupChatWorkflow,
  %{topic: "The future of AI safety"}
)

# Monitor conversation
Cerebelum.get_execution_status(exec_id)
```

### Why This is a Recipe (Not Built-in)

1. **No single "right way"** - Different use cases need different moderation logic
2. **Easy to customize** - Change termination conditions, speaker selection, agent roles
3. **Composable** - Built from Cerebelum primitives (workflows, subworkflows, loops)
4. **Learnable** - Shows how to use the platform, not a black box

### Variations

**Round-Robin (Simple):**
```elixir
defp select_next_speaker(state) do
  Enum.at(state.agents, rem(state.round, length(state.agents)))
end
```

**Random Selection:**
```elixir
defp select_next_speaker(state) do
  Enum.random(state.agents)
end
```

**Parallel All (Not True Group Chat):**
```elixir
def run_all_agents(context, %{init: state}) do
  {:parallel_subworkflows, [
    {ResearchAgent, %{topic: state.topic}},
    {WriterAgent, %{topic: state.topic}},
    {CriticAgent, %{topic: state.topic}}
  ], timeout: 60_000}
end
```

---

## Design Decisions

### Decision 1: Process per Subworkflow (vs Thread Pool)

**Chosen:** Each subworkflow = independent ExecutionEngine process

**Rationale:**
- Full isolation (failure doesn't affect parent)
- Independent timeout and error handling
- Can be distributed across nodes (Horde)
- Natural supervision tree
- Event sourcing per subworkflow
- Easier debugging (each has its own process ID)

**Trade-off:** Slightly more overhead per subworkflow (~2KB per process), but negligible given BEAM's lightweight processes.

### Decision 2: Explicit Function Calls (vs Declarative DSL) for MVP

**Chosen:** Explicit `Cerebelum.execute_subworkflow()` calls in functions

**Rationale:**
- Simpler to implement initially
- More obvious what's happening
- Easier to add custom logic (retry, fallbacks, etc.)
- Can migrate to declarative syntax later

**Future:** Could add declarative `subworkflow()` macro later as syntactic sugar.

### Decision 3: Monitor vs Link for Subworkflows

**Chosen:** Monitor (not link)

**Rationale:**
- Parent continues if subworkflow crashes (can handle error in diverge)
- Parent decides how to handle failure
- No cascading failures

### Decision 4: Context Isolation

**Chosen:** Subworkflows do NOT inherit parent's results cache

**Rationale:**
- Reusability (subworkflow is standalone)
- Testability (can test in isolation)
- Explicit data flow (parent passes only what's needed)

**Trade-off:** Slightly more verbose (must pass data explicitly), but clearer.

### Decision 5: Parallel Subworkflows Return Type

**Chosen:** Map indexed by module name

```elixir
%{
  AgentA => result_a,
  AgentB => result_b
}
```

**Rationale:**
- Easy to access specific agent result
- Works with pattern matching
- Clear which agent produced which result

**Alternative considered:** List of results (rejected - hard to correlate with agent)

---

## Implementation Checklist

### Phase 1: Sequential Subworkflows
- [ ] `Cerebelum.execute_subworkflow/3` function
- [ ] Parent monitoring of subworkflow process
- [ ] Result propagation to parent's results cache
- [ ] Error propagation on subworkflow failure
- [ ] Event sourcing for subworkflow (separate stream)
- [ ] Tests for sequential subworkflow execution

### Phase 2: Parallel Subworkflows
- [ ] `:waiting_for_subworkflows` state in ExecutionEngine
- [ ] `{:parallel_subworkflows, [...]}` return type handling
- [ ] Start multiple subworkflows with monitoring
- [ ] Wait for all completions
- [ ] Timeout handling for parallel subworkflows
- [ ] Partial failure handling
- [ ] Tests for parallel execution

### Phase 3: Advanced Features
- [ ] Fire-and-forget subworkflows
- [ ] Subworkflow cancellation
- [ ] Parent-to-subworkflow messages
- [ ] Subworkflow progress reporting
- [ ] Declarative `subworkflow()` syntax (syntactic sugar)

---

## Next Steps

1. **Update `execution-engine-state-machine.md`** with `:waiting_for_subworkflows` state
2. **Update `workflow-syntax.md`** with subworkflow examples
3. **Implement `Cerebelum.SubworkflowRunner` module**
4. **Add tests for sequential subworkflow execution**
5. **Implement parallel subworkflows support**
6. **Create multi-agent example workflows**

---

**End of Document**
