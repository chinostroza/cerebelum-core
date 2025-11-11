# Execution Engine State Machine

**Status:** Design
**Created:** 2025-11-01
**Related:** [Workflow Syntax Design](workflow-syntax.md), [Implementation Tasks](../implementation/01-tasks.md)

---

## Overview

El `ExecutionEngine` está implementado como una **GenStateMachine** (`:gen_statem` en Erlang/OTP) en lugar de un GenServer tradicional. Esta decisión arquitectónica permite modelar explícitamente el ciclo de vida de una ejecución de workflow como estados y transiciones.

## Por Qué GenStateMachine

### Ventajas sobre GenServer

1. **Estados Explícitos**: Los estados son parte de la interfaz pública, no datos internos
2. **Transiciones Controladas**: Las transiciones son explícitas y verificables
3. **Timeouts por Estado**: Cada estado puede tener su propio timeout
4. **Eventos Internos**: Permite encadenar transiciones sin mensajes externos
5. **Debugging Superior**: Fácil visualizar y trazar el flujo de estados
6. **Prevención de Bugs**: Imposible llamar operaciones en estados inválidos

### Workflows son Máquinas de Estado

Un workflow execution es inherentemente una máquina de estado finito:

- **Estados**: :executing_step, :sleeping, :waiting_for_approval, :completed, :failed
- **Transiciones**: Determinadas por resultados de funciones y eventos externos
- **Timeouts**: Cada operación tiene límites de tiempo
- **Eventos**: Aprobaciones, timeouts, errores

## Diagrama de Estados

```
┌──────────────┐
│:initializing │
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│:executing_step   │◄─────────┐
└─────┬────────────┘          │
      │                       │
      ├─────────┐             │
      │         │             │
      ▼         ▼             │
 ┌─────────┐ ┌──────────┐    │
 │:eval    │ │:eval     │    │
 │diverge  │ │branch    │    │
 └────┬────┘ └────┬─────┘    │
      │           │           │
      └──┬────────┘           │
         │                    │
         │ (continue)         │
         └────────────────────┘
         │ (back_to/skip_to)

      ┌──────────┐
      │:sleeping │──┐
      └──────────┘  │
         ▲          │
         └──────────┘
         (timeout)

   ┌────────────────────┐
   │:waiting_for_approval│──┐
   └────────────────────┘  │
         ▲                 │
         └─────────────────┘
         (approve/reject)

   ┌────────────────────────┐
   │:waiting_for_subworkflows│──┐
   └────────────────────────┘  │
         ▲                      │
         └──────────────────────┘
         (all complete/timeout)

      ┌───────────┐
      │:completed │
      └───────────┘

      ┌─────────┐
      │:failed  │
      └─────────┘
```

## Estados Definidos

### :initializing

**Propósito**: Inicialización de la ejecución

**Entrada**: Al crear el proceso
**Salida**: Transiciona a `:executing_step`

**Eventos**:
- `:internal, :start` → Iniciar ejecución

**Timeouts**: Ninguno

**Implementación**:
```elixir
def initializing(:internal, :start, data) do
  Logger.info("Starting execution: #{data.context.execution_id}")

  event = %ExecutionStartedEvent{
    execution_id: data.context.execution_id,
    workflow_module: data.workflow_metadata.module,
    workflow_version: data.workflow_metadata.version
  }
  EventStore.append(event)

  {:next_state, :executing_step, data, [{:next_event, :internal, :execute}]}
end
```

---

### :executing_step

**Propósito**: Ejecutar el paso actual del workflow

**Entrada**:
- Desde `:initializing` (primer paso)
- Desde `:evaluating_branch` (continuar timeline)
- Desde `:sleeping` (despertar)
- Desde `:waiting_for_approval` (aprobado)

**Salida**:
- `:evaluating_diverge` (si existe diverge para este paso)
- `:evaluating_branch` (si no hay diverge)
- `:sleeping` (si función retorna `{:sleep, ...}`)
- `:waiting_for_approval` (si función retorna `{:wait_for_approval, ...}`)
- `:waiting_for_subworkflows` (si función retorna `{:parallel_subworkflows, ...}`)
- `:completed` (si es el último paso)
- `:failed` (si hay error)

**Eventos**:
- `:internal, :execute` → Ejecutar paso actual
- `:state_timeout, :step_timeout` → Timeout de ejecución

**Timeouts**: 5 minutos por paso

**Implementación**:
```elixir
def executing_step(:enter, _old_state, data) do
  Logger.debug("Executing step: #{get_current_step_name(data)}")
  {:keep_state, data, [{:state_timeout, 5 * 60 * 1000, :step_timeout}]}
end

def executing_step(:internal, :execute, data) do
  case execute_current_step(data) do
    {:ok, result, new_data} ->
      data_with_result = store_result(new_data, result)

      if has_diverge?(data_with_result) do
        {:next_state, :evaluating_diverge, data_with_result,
         [{:next_event, :internal, :evaluate}]}
      else
        {:next_state, :evaluating_branch, data_with_result,
         [{:next_event, :internal, :evaluate}]}
      end

    {:sleep, opts, result} ->
      seconds = Keyword.fetch!(opts, :seconds)
      data_with_sleep = %{data | sleep_seconds: seconds}
      {:next_state, :sleeping, data_with_sleep}

    {:wait_for_approval, opts, result} ->
      {:next_state, :waiting_for_approval, data}

    {:parallel_subworkflows, subworkflows, opts} ->
      # Iniciar subworkflows en paralelo
      child_pids = SubworkflowRunner.start_parallel_subworkflows(
        subworkflows,
        data.context,
        opts
      )

      timeout = Keyword.get(opts, :timeout, 300_000)

      data_with_subworkflows = %{data |
        pending_subworkflows: child_pids,
        subworkflow_timeout: timeout,
        initial_subworkflow_count: length(child_pids)
      }

      {:next_state, :waiting_for_subworkflows, data_with_subworkflows}

    {:error, reason, new_data} ->
      {:next_state, :failed, %{new_data | error: reason}}
  end
end

def executing_step(:state_timeout, :step_timeout, data) do
  Logger.error("Step execution timeout")
  {:next_state, :failed, %{data | error: :step_timeout}}
end

def executing_step({:call, from}, :get_status, data) do
  status = %{
    state: :executing_step,
    current_step: get_current_step_name(data),
    progress: "#{data.current_step_index}/#{length(data.workflow_metadata.timeline)}"
  }
  {:keep_state, data, [{:reply, from, {:ok, status}}]}
end
```

---

### :evaluating_diverge

**Propósito**: Evaluar condiciones de diverge (error handling)

**Entrada**: Desde `:executing_step` (si existe diverge)

**Salida**:
- `:executing_step` (continue, back_to, skip_to)
- `:failed` (si diverge decide fallar)

**Eventos**:
- `:internal, :evaluate` → Evaluar condiciones

**Timeouts**: Ninguno (evaluación instantánea)

**Implementación**:
```elixir
def evaluating_diverge(:internal, :evaluate, data) do
  step_result = get_last_result(data)

  case DivergeHandler.handle_diverge(data.current_step, step_result, data) do
    {:continue, new_data} ->
      {:next_state, :evaluating_branch, new_data,
       [{:next_event, :internal, :evaluate}]}

    {:back_to, target, new_data} ->
      jumped_data = jump_to_step(new_data, target)
      {:next_state, :executing_step, jumped_data,
       [{:next_event, :internal, :execute}]}

    {:skip_to, target, new_data} ->
      jumped_data = jump_to_step(new_data, target)
      {:next_state, :executing_step, jumped_data,
       [{:next_event, :internal, :execute}]}

    {:error, reason, new_data} ->
      {:next_state, :failed, %{new_data | error: reason}}
  end
end
```

---

### :evaluating_branch

**Propósito**: Evaluar condiciones de branch (business logic)

**Entrada**:
- Desde `:executing_step` (si no hay diverge)
- Desde `:evaluating_diverge` (continue)

**Salida**:
- `:executing_step` (continue, skip_to)
- `:completed` (si terminó el workflow)

**Eventos**:
- `:internal, :evaluate` → Evaluar condiciones

**Timeouts**: Ninguno (evaluación instantánea)

**Implementación**:
```elixir
def evaluating_branch(:internal, :evaluate, data) do
  step_result = get_last_result(data)

  case BranchHandler.handle_branch(data.current_step, step_result, data) do
    {:continue, new_data} ->
      next_data = advance_to_next_step(new_data)

      if finished?(next_data) do
        {:next_state, :completed, next_data}
      else
        {:next_state, :executing_step, next_data,
         [{:next_event, :internal, :execute}]}
      end

    {:skip_to, target, new_data} ->
      jumped_data = jump_to_step(new_data, target)

      if finished?(jumped_data) do
        {:next_state, :completed, jumped_data}
      else
        {:next_state, :executing_step, jumped_data,
         [{:next_event, :internal, :execute}]}
      end
  end
end
```

---

### :sleeping

**Propósito**: Pausar ejecución sin bloquear BEAM (sleep)

**Entrada**: Desde `:executing_step` (función retorna `{:sleep, ...}`)

**Salida**: `:executing_step` (después del timeout)

**Eventos**:
- `:state_timeout, :wake_up` → Despertar

**Timeouts**: Configurado por la función (ej: 60 segundos)

**Implementación**:
```elixir
def sleeping(:enter, _old_state, data) do
  seconds = data.sleep_seconds
  Logger.info("Sleeping for #{seconds} seconds")

  event = %SleepStartedEvent{
    execution_id: data.context.execution_id,
    duration_seconds: seconds
  }
  EventStore.append(event)

  {:keep_state, data, [{:state_timeout, seconds * 1000, :wake_up}]}
end

def sleeping(:state_timeout, :wake_up, data) do
  Logger.info("Waking up from sleep")

  event = %SleepCompletedEvent{
    execution_id: data.context.execution_id
  }
  EventStore.append(event)

  {:next_state, :executing_step, data, [{:next_event, :internal, :execute}]}
end
```

---

### :waiting_for_approval

**Propósito**: Pausar ejecución esperando aprobación humana (HITL)

**Entrada**: Desde `:executing_step` (función retorna `{:wait_for_approval, ...}`)

**Salida**:
- `:executing_step` (aprobado)
- `:failed` (rechazado o timeout)

**Eventos**:
- `{:call, from}, {:approve, data}` → Aprobar
- `{:call, from}, {:reject, reason}` → Rechazar
- `:state_timeout, :approval_timeout` → Timeout (24 horas)

**Timeouts**: 24 horas

**Implementación**:
```elixir
def waiting_for_approval(:enter, _old_state, data) do
  Logger.info("Waiting for approval")

  event = %ApprovalRequestedEvent{
    execution_id: data.context.execution_id,
    approval_type: data.approval_type,
    approval_data: data.approval_data
  }
  EventStore.append(event)

  timeout_ms = 24 * 60 * 60 * 1000
  {:keep_state, data, [{:state_timeout, timeout_ms, :approval_timeout}]}
end

def waiting_for_approval({:call, from}, {:approve, approval_data}, data) do
  Logger.info("Approval received")

  result = %{decision: :approved, data: approval_data}
  data_with_approval = store_result(data, :approval, result)

  event = %ApprovalReceivedEvent{
    execution_id: data.context.execution_id,
    decision: :approved,
    data: approval_data
  }
  EventStore.append(event)

  {:next_state, :executing_step, data_with_approval,
   [{:reply, from, :ok}, {:next_event, :internal, :execute}]}
end

def waiting_for_approval({:call, from}, {:reject, reason}, data) do
  Logger.info("Approval rejected: #{inspect(reason)}")

  event = %ApprovalRejectedEvent{
    execution_id: data.context.execution_id,
    reason: reason
  }
  EventStore.append(event)

  {:next_state, :failed, %{data | error: {:rejected, reason}},
   [{:reply, from, :ok}]}
end

def waiting_for_approval(:state_timeout, :approval_timeout, data) do
  Logger.warn("Approval timeout")
  {:next_state, :failed, %{data | error: :approval_timeout}}
end
```

---

### :waiting_for_subworkflows

**Propósito**: Esperar a que completen uno o más subworkflows ejecutándose en paralelo

**Entrada**: Desde `:executing_step` (función retorna `{:parallel_subworkflows, ...}`)

**Salida**:
- `:executing_step` (todos los subworkflows completaron)
- `:failed` (algún subworkflow falló o timeout)

**Eventos**:
- `:info, {:DOWN, ref, :process, pid, reason}` → Un subworkflow terminó
- `:state_timeout, :subworkflows_timeout` → Timeout esperando subworkflows

**Timeouts**: Configurable (default: 5 minutos)

**Implementación**:
```elixir
def waiting_for_subworkflows(:enter, _old_state, data) do
  num_subworkflows = length(data.pending_subworkflows)
  Logger.info("Waiting for #{num_subworkflows} subworkflows to complete")

  event = %SubworkflowsStartedEvent{
    execution_id: data.context.execution_id,
    subworkflow_count: num_subworkflows,
    subworkflow_modules: Enum.map(data.pending_subworkflows, fn {_pid, _ref, mod, _exec_id} -> mod end)
  }
  EventStore.append(event)

  timeout_ms = data.subworkflow_timeout || 300_000  # Default 5 minutes
  {:keep_state, data, [{:state_timeout, timeout_ms, :subworkflows_timeout}]}
end

def waiting_for_subworkflows(:info, {:DOWN, ref, :process, pid, reason}, data) do
  # Un subworkflow terminó (normal o con error)
  {^pid, ^ref, workflow_mod, exec_id} =
    Enum.find(data.pending_subworkflows, fn {p, r, _mod, _id} ->
      p == pid and r == ref
    end)

  case reason do
    :normal ->
      # Subworkflow completó exitosamente
      Logger.debug("Subworkflow #{workflow_mod} completed successfully")

      # Obtener resultado del event store
      result = EventStore.get_final_result(exec_id)

      # Actualizar results cache con el resultado de este subworkflow
      new_results = Map.put(data.results, workflow_mod, result)
      new_pending = List.delete(data.pending_subworkflows, {pid, ref, workflow_mod, exec_id})

      # Verificar si todos los subworkflows terminaron
      if Enum.empty?(new_pending) do
        Logger.info("All subworkflows completed")

        # Todos completaron - guardar resultados consolidados
        consolidated_results = consolidate_subworkflow_results(data, new_results)

        event = %SubworkflowsCompletedEvent{
          execution_id: data.context.execution_id,
          completed_count: length(data.pending_subworkflows)
        }
        EventStore.append(event)

        new_data = %{data |
          results: store_result(data, data.current_step, consolidated_results),
          pending_subworkflows: []
        }

        {:next_state, :executing_step, new_data,
         [{:next_event, :internal, :execute}]}
      else
        # Aún hay subworkflows pendientes - seguir esperando
        {:keep_state, %{data |
          results: new_results,
          pending_subworkflows: new_pending
        }}
      end

    error_reason ->
      # Subworkflow falló
      Logger.error("Subworkflow #{workflow_mod} failed: #{inspect(error_reason)}")

      event = %SubworkflowFailedEvent{
        execution_id: data.context.execution_id,
        subworkflow_module: workflow_mod,
        subworkflow_execution_id: exec_id,
        reason: error_reason
      }
      EventStore.append(event)

      # Matar todos los subworkflows restantes
      Enum.each(new_pending, fn {pid, _ref, _mod, _id} ->
        Process.exit(pid, :kill)
      end)

      {:next_state, :failed, %{data |
        error: {:subworkflow_failed, workflow_mod, error_reason}
      }}
  end
end

def waiting_for_subworkflows(:state_timeout, :subworkflows_timeout, data) do
  Logger.error("Subworkflows timeout - killing #{length(data.pending_subworkflows)} pending subworkflows")

  # Matar todos los subworkflows pendientes
  Enum.each(data.pending_subworkflows, fn {pid, _ref, mod, _id} ->
    Logger.warn("Killing timed out subworkflow: #{mod}")
    Process.exit(pid, :kill)
  end)

  event = %SubworkflowsTimeoutEvent{
    execution_id: data.context.execution_id,
    pending_count: length(data.pending_subworkflows)
  }
  EventStore.append(event)

  {:next_state, :failed, %{data | error: :subworkflows_timeout}}
end

def waiting_for_subworkflows({:call, from}, :get_status, data) do
  status = %{
    state: :waiting_for_subworkflows,
    pending_count: length(data.pending_subworkflows),
    completed_count: initial_count(data) - length(data.pending_subworkflows),
    subworkflows: Enum.map(data.pending_subworkflows, fn {_pid, _ref, mod, exec_id} ->
      %{module: mod, execution_id: exec_id}
    end)
  }
  {:keep_state, data, [{:reply, from, {:ok, status}}]}
end

defp consolidate_subworkflow_results(data, results) do
  # Retorna un mapa indexado por módulo con los resultados
  data.pending_subworkflows
  |> Enum.map(fn {_pid, _ref, mod, _exec_id} -> {mod, results[mod]} end)
  |> Enum.into(%{})
end

defp initial_count(data) do
  Map.get(data, :initial_subworkflow_count, length(data.pending_subworkflows))
end
```

---

### :completed

**Propósito**: Ejecución completada exitosamente

**Entrada**:
- Desde `:evaluating_branch` (último paso)

**Salida**: Ninguna (estado terminal)

**Eventos**: Ninguno

**Timeouts**: Ninguno

**Implementación**:
```elixir
def completed(:enter, _old_state, data) do
  Logger.info("Execution completed: #{data.context.execution_id}")

  event = %ExecutionCompletedEvent{
    execution_id: data.context.execution_id,
    final_result: get_last_result(data),
    timestamp: DateTime.utc_now()
  }
  EventStore.append(event)

  :keep_state_and_data
end

def completed({:call, from}, :get_status, data) do
  status = %{
    state: :completed,
    result: get_last_result(data),
    steps_executed: data.current_step_index
  }
  {:keep_state, data, [{:reply, from, {:ok, status}}]}
end
```

---

### :failed

**Propósito**: Ejecución falló con error

**Entrada**:
- Desde `:executing_step` (error o timeout)
- Desde `:waiting_for_approval` (rechazado o timeout)
- Desde `:evaluating_diverge` (decidió fallar)

**Salida**: Ninguna (estado terminal)

**Eventos**: Ninguno

**Timeouts**: Ninguno

**Implementación**:
```elixir
def failed(:enter, _old_state, data) do
  Logger.error("Execution failed: #{inspect(data.error)}")

  event = %ExecutionFailedEvent{
    execution_id: data.context.execution_id,
    error: data.error,
    last_step: get_current_step_name(data),
    timestamp: DateTime.utc_now()
  }
  EventStore.append(event)

  :keep_state_and_data
end

def failed({:call, from}, :get_status, data) do
  status = %{
    state: :failed,
    error: data.error,
    failed_at_step: get_current_step_name(data)
  }
  {:keep_state, data, [{:reply, from, {:ok, status}}]}
end
```

---

## Estructura de Datos (Data)

```elixir
defmodule Cerebelum.ExecutionEngine do
  defstruct [
    # Workflow metadata
    :context,              # %Context{} - immutable execution context
    :workflow_metadata,    # %{timeline: [...], diverges: %{}, branches: %{}}

    # Execution state
    results: %{},          # %{step_name => result} - results cache
    current_step_index: 0, # Integer - position in timeline

    # Temporary state for specific operations
    sleep_seconds: nil,    # Integer - for :sleeping state
    approval_type: nil,    # Atom - for :waiting_for_approval state
    approval_data: nil,    # Term - for :waiting_for_approval state

    # Subworkflow tracking (for :waiting_for_subworkflows state)
    pending_subworkflows: [],       # [{pid, ref, module, exec_id}]
    subworkflow_timeout: nil,       # Integer - timeout in milliseconds
    initial_subworkflow_count: nil, # Integer - original count for progress tracking

    # Error tracking
    error: nil             # Term - error reason (for :failed state)
  ]
end
```

## Callbacks de GenStateMachine

### callback_mode/0

```elixir
def callback_mode do
  [:state_functions, :state_enter]
end
```

**Explicación**:
- `:state_functions` - Cada estado es una función separada
- `:state_enter` - Llama automáticamente a `state(:enter, old_state, data)` al entrar a un estado

### init/1

```elixir
def init(opts) do
  workflow_module = Keyword.fetch!(opts, :workflow_module)
  inputs = Keyword.fetch!(opts, :inputs)

  data = %__MODULE__{
    context: Context.new(workflow_module, inputs),
    workflow_metadata: Metadata.extract(workflow_module)
  }

  {:ok, :initializing, data, [{:next_event, :internal, :start}]}
end
```

**Retorno**: `{:ok, initial_state, initial_data, actions}`

## Eventos y Acciones

### Tipos de Eventos

1. **Externos** (`:call`, `:cast`, `:info`)
   ```elixir
   {:call, from}, :get_status
   {:call, from}, {:approve, data}
   ```

2. **Internos** (`:internal`)
   ```elixir
   {:next_event, :internal, :execute}
   {:next_event, :internal, :evaluate}
   ```

3. **Timeouts**
   ```elixir
   :state_timeout, :wake_up
   :state_timeout, :step_timeout
   ```

4. **Enter/Exit** (`:enter`, `:exit`)
   ```elixir
   :enter, old_state
   ```

### Tipos de Acciones

1. **Transiciones**
   ```elixir
   {:next_state, :executing_step, new_data}
   ```

2. **Mantener estado**
   ```elixir
   {:keep_state, new_data}
   :keep_state_and_data
   ```

3. **Eventos internos**
   ```elixir
   [{:next_event, :internal, :execute}]
   ```

4. **Timeouts**
   ```elixir
   [{:state_timeout, 5000, :wake_up}]
   ```

5. **Respuestas**
   ```elixir
   [{:reply, from, :ok}]
   ```

## Ventajas Prácticas

### 1. Debugging y Observabilidad

```elixir
# Ver estado actual
:sys.get_state(pid)
# => {:executing_step, %Data{...}}

# Trace de transiciones
:sys.trace(pid, true)
# => *DBG* :executing_step got {:internal, :execute}
# => *DBG* :executing_step → :evaluating_diverge

# Estadísticas
:sys.statistics(pid, :get)
```

### 2. Introspección

```elixir
# Obtener estado actual
def get_current_state(pid) do
  {:current_state, state} = :sys.get_status(pid)
  state
end

# Verificar si está esperando aprobación
def waiting_for_approval?(pid) do
  get_current_state(pid) == :waiting_for_approval
end
```

### 3. Testing

```elixir
test "execution transitions from initializing to executing_step" do
  {:ok, pid} = ExecutionEngine.start_link(workflow_module: MyWorkflow, inputs: %{})

  # Wait for initialization
  :timer.sleep(10)

  # Check state
  assert :sys.get_state(pid) |> elem(0) == :executing_step
end

test "sleep timeout wakes up execution" do
  {:ok, pid} = start_supervised({ExecutionEngine, ...})

  # Trigger sleep
  send(pid, {:execute_step_returning_sleep})

  assert :sys.get_state(pid) |> elem(0) == :sleeping

  # Wait for timeout
  :timer.sleep(1100)

  assert :sys.get_state(pid) |> elem(0) == :executing_step
end
```

### 4. Visualización

Es fácil generar diagramas automáticamente desde el código:

```elixir
defmodule Cerebelum.Debug.StateDiagram do
  def generate_dot(engine_module) do
    states = get_all_states(engine_module)
    transitions = extract_transitions(engine_module)

    """
    digraph ExecutionEngine {
      #{Enum.map(states, &"  #{&1};")}

      #{Enum.map(transitions, fn {from, to} ->
        "  #{from} -> #{to};"
      end)}
    }
    """
  end
end
```

## Event Sourcing Integration

Cada transición de estado genera un evento:

```elixir
# Generic state transition event
defmodule StateTransitionEvent do
  defstruct [
    :execution_id,
    :from_state,
    :to_state,
    :trigger,  # :internal | :timeout | :call
    :timestamp
  ]
end

# Log all transitions
def handle_event(:enter, old_state, new_state, data) when old_state != new_state do
  event = %StateTransitionEvent{
    execution_id: data.context.execution_id,
    from_state: old_state,
    to_state: new_state,
    trigger: :internal,
    timestamp: DateTime.utc_now()
  }

  EventStore.append(event)
  {:keep_state, data}
end
```

## Resumen

| Aspecto | Implementación |
|---------|----------------|
| **Behaviour** | `:gen_statem` |
| **Callback Mode** | `:state_functions` + `:state_enter` |
| **Estados** | 9 estados explícitos |
| **Transiciones** | Controladas por retornos de funciones y eventos |
| **Timeouts** | Por estado (step: 5min, approval: 24h, sleep: variable, subworkflows: 5min) |
| **Eventos Internos** | Para encadenar transiciones sin latencia |
| **Event Sourcing** | Cada transición es un evento |
| **Testing** | Fácil con `:sys.get_state/1` |
| **Debugging** | Excelente con `:sys.trace/2` |
| **Subworkflows** | Soporte nativo con estado `:waiting_for_subworkflows` |

---

**Referencias**:
- [Erlang gen_statem](https://www.erlang.org/doc/man/gen_statem.html)
- [Elixir :gen_statem](https://www.erlang.org/doc/design_principles/statem.html)
- [State Machine Design](https://learnyousomeerlang.com/finite-state-machines)
