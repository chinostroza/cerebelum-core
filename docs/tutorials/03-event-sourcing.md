# Tutorial 3: Event Sourcing Fundamentals

**Tiempo estimado:** 25 minutos
**Prerrequisitos:** [Tutorial 2 - GenServers and Supervision](02-genservers-and-supervision.md)

## El Problema

En el tutorial anterior vimos que cuando un GenServer crashea y se reinicia, **pierde todo su estado**:

```elixir
Contador en 99
💥 Crash!
Supervisor reinicia
Contador en 0  ← ¡Perdimos 99!
```

**Solución tradicional:** Guardar el estado en una base de datos cada vez que cambia.

**Problema:** ¿Qué pasa si crashea JUSTO antes de guardar?

## La Solución: Event Sourcing

En lugar de guardar el **estado actual**, guardamos **todos los eventos** que llevaron a ese estado.

### Analogía: Cuenta bancaria

**Approach tradicional (guardar estado):**
```
Base de Datos
┌──────────────┐
│ Saldo: $150  │  ← Solo guardamos el número final
└──────────────┘
```

Si se corrompe, perdemos todo. No sabemos cómo llegamos a $150.

**Event Sourcing (guardar eventos):**
```
Base de Datos - Eventos
┌──────────────────────────────┐
│ 1. Depósito:    +$100        │
│ 2. Depósito:    +$50         │
│ 3. Retiro:      -$20         │
│ 4. Depósito:    +$20         │
└──────────────────────────────┘

Saldo actual = sum(eventos) = $150
```

**Ventajas:**
- ✅ Nunca perdemos información
- ✅ Auditoría completa (sabemos TODO lo que pasó)
- ✅ Podemos reconstruir el estado en cualquier momento
- ✅ Time-travel: ver el estado en el pasado

## Event Sourcing en Código

### Sin Event Sourcing (Frágil)

```elixir
defmodule CuentaBancariaFragil do
  use GenServer

  def init(_) do
    {:ok, %{saldo: 0}}  # Estado se pierde si crashea
  end

  def handle_call({:depositar, monto}, _from, state) do
    nuevo_saldo = state.saldo + monto
    # ¿Qué pasa si crashea AQUÍ? ↓
    {:reply, {:ok, nuevo_saldo}, %{state | saldo: nuevo_saldo}}
  end
end
```

### Con Event Sourcing (Resiliente)

```elixir
defmodule CuentaBancariaResiliente do
  use GenServer

  def init(cuenta_id) do
    # Paso 1: Leer TODOS los eventos de la DB
    eventos = EventStore.get_events(cuenta_id)

    # Paso 2: Reconstruir estado desde eventos
    estado = Enum.reduce(eventos, %{saldo: 0, cuenta_id: cuenta_id}, fn evento, acc ->
      apply_event(evento, acc)
    end)

    {:ok, estado}
  end

  def handle_call({:depositar, monto}, _from, state) do
    # Paso 1: Crear el evento
    evento = %{
      tipo: :deposito,
      monto: monto,
      timestamp: DateTime.utc_now()
    }

    # Paso 2: Guardar el evento PRIMERO (en DB) ✅
    EventStore.append_event(state.cuenta_id, evento)

    # Paso 3: Aplicar el evento al estado
    nuevo_estado = apply_event(evento, state)

    # Ahora, si crashea aquí, no importa:
    # Al reiniciar, lee los eventos (incluyendo este) y reconstruye
    {:reply, {:ok, nuevo_estado.saldo}, nuevo_estado}
  end

  # Función que aplica un evento al estado
  defp apply_event(%{tipo: :deposito, monto: monto}, state) do
    %{state | saldo: state.saldo + monto}
  end

  defp apply_event(%{tipo: :retiro, monto: monto}, state) do
    %{state | saldo: state.saldo - monto}
  end
end
```

**Flujo de recuperación:**
```
T1: Saldo = $0
T2: Evento: deposito +$100  → guardado en DB ✅
T3: Estado: Saldo = $100
T4: Evento: deposito +$50   → guardado en DB ✅
T5: 💥 CRASH antes de actualizar estado!

--- Reinicio ---

T6: init() lee eventos de DB:
    - deposito +$100
    - deposito +$50

T7: Reconstruye:
    $0 + $100 + $50 = $150  ← ¡Estado recuperado!

T8: Continúa normalmente
```

## EventStore Simple

```elixir
defmodule EventStore do
  @moduledoc """
  EventStore simple usando ETS (en producción: PostgreSQL)
  """

  def init do
    :ets.new(:event_store, [:named_table, :ordered_set, :public])
  end

  def append_event(stream_id, evento) do
    # Obtener el número de secuencia
    count = :ets.select_count(:event_store, [
      {{{stream_id, :_}, :_}, [], [true]}
    ])

    sequence = count + 1
    evento_con_metadata = Map.put(evento, :sequence, sequence)

    # Guardar evento
    :ets.insert(:event_store, {{stream_id, sequence}, evento_con_metadata})

    :ok
  end

  def get_events(stream_id) do
    :ets.match_object(:event_store, {{stream_id, :_}, :_})
    |> Enum.map(fn {_key, evento} -> evento end)
    |> Enum.sort_by(& &1.sequence)
  end
end
```

### Uso del EventStore

```elixir
# Inicializar
EventStore.init()

# Guardar eventos
EventStore.append_event("cuenta-123", %{
  tipo: :deposito,
  monto: 100,
  timestamp: DateTime.utc_now()
})

EventStore.append_event("cuenta-123", %{
  tipo: :retiro,
  monto: 20,
  timestamp: DateTime.utc_now()
})

# Leer eventos
eventos = EventStore.get_events("cuenta-123")
# [
#   %{tipo: :deposito, monto: 100, sequence: 1, ...},
#   %{tipo: :retiro, monto: 20, sequence: 2, ...}
# ]

# Reconstruir estado
saldo_final = Enum.reduce(eventos, 0, fn evento, saldo ->
  case evento.tipo do
    :deposito -> saldo + evento.monto
    :retiro -> saldo - evento.monto
  end
end)

IO.puts("Saldo: $#{saldo_final}")
# Output: Saldo: $80
```

## Event Sourcing en Cerebelum Workflows

Cerebelum usa Event Sourcing para cada ejecución de workflow:

```elixir
defmodule Cerebelum.ExecutionEngine do
  use GenServer

  def init(opts) do
    execution_id = opts[:execution_id]
    workflow = opts[:workflow]

    # Leer eventos de esta ejecución
    eventos = EventStore.get_events(execution_id)

    # Reconstruir estado
    estado = case eventos do
      [] ->
        # Primera ejecución
        %ExecutionState{
          execution_id: execution_id,
          workflow: workflow,
          status: :initializing,
          current_node: workflow.entrypoint,
          workflow_state: %{},
          completed_nodes: []
        }

      eventos ->
        # Recuperando de un crash - reconstruir desde eventos
        Enum.reduce(eventos, %ExecutionState{}, fn evento, state ->
          apply_event(evento, state)
        end)
    end

    # Continuar desde donde quedó
    send(self(), :continue_execution)

    {:ok, estado}
  end

  def handle_info(:continue_execution, state) do
    # Ejecutar siguiente nodo
    resultado = ejecutar_nodo(state.current_node, state.workflow_state)

    case resultado do
      {:ok, output} ->
        # Guardar evento PRIMERO
        evento = %{
          tipo: :node_completed,
          node: state.current_node,
          output: output,
          timestamp: DateTime.utc_now()
        }

        EventStore.append_event(state.execution_id, evento)

        # Aplicar evento al estado
        nuevo_estado = apply_event(evento, state)

        # Continuar
        send(self(), :continue_execution)
        {:noreply, nuevo_estado}

      {:error, reason} ->
        # Guardar evento de fallo
        evento = %{
          tipo: :node_failed,
          node: state.current_node,
          error: reason,
          timestamp: DateTime.utc_now()
        }

        EventStore.append_event(state.execution_id, evento)

        {:stop, :normal, state}
    end
  end

  # Aplicar eventos al estado
  defp apply_event(%{tipo: :execution_started, workflow: workflow}, _state) do
    %ExecutionState{
      workflow: workflow,
      status: :running,
      current_node: workflow.entrypoint,
      completed_nodes: []
    }
  end

  defp apply_event(%{tipo: :node_completed, node: node, output: output}, state) do
    %{state |
      completed_nodes: [node | state.completed_nodes],
      current_node: determinar_siguiente_nodo(state, node),
      workflow_state: output
    }
  end

  defp apply_event(%{tipo: :node_failed}, state) do
    %{state | status: :failed}
  end
end
```

## Ejemplo Completo: Workflow con Crash

```elixir
defmodule SimpleWorkflow do
  use Cerebelum.Workflow

  def start(_input), do: {:ok, %{count: 0}}

  def increment(state) do
    new_count = state.count + 1

    if new_count == 3 do
      # Simular crash
      raise "¡Error intencional!"
    end

    {:ok, %{state | count: new_count}}
  end

  def finish(state), do: {:ok, "Completado con #{state.count}"}

  workflow do
    edge &start/1 -> &increment/1
    edge &increment/1 -> &increment/1  # Loop
    edge &increment/1 -> &finish/1, when: fn state -> state.count >= 5 end
  end
end

# Ejecutar
execution_id = "exec-crash-test"
{:ok, pid} = Cerebelum.start_workflow(SimpleWorkflow, %{}, execution_id: execution_id)

# Eventos guardados antes del crash:
# 1. execution_started
# 2. node_completed: start (output: %{count: 0})
# 3. node_completed: increment (output: %{count: 1})
# 4. node_completed: increment (output: %{count: 2})
# 5. node_started: increment
# 💥 CRASH en increment cuando count = 3

# El supervisor detecta y reinicia
# ExecutionEngine.init() lee eventos 1-5
# Reconstruye:
#   - Ya completó: start, increment (2 veces)
#   - Estaba ejecutando: increment
#   - Estado actual: %{count: 2}
#
# Decisión: Reintentar increment
# Esta vez pasa (quizás el error fue transitorio)
# Continúa hasta completar
```

**Timeline con eventos:**
```
Base de Datos                     Proceso
──────────────────────────────────────────────────────────

[1. execution_started]           init()
                                 estado = %{count: 0, node: :start}

[2. node_completed: start]       ejecuta start()
                                 estado = %{count: 0, node: :increment}

[3. node_completed: increment]   ejecuta increment()
                                 estado = %{count: 1, node: :increment}

[4. node_completed: increment]   ejecuta increment()
                                 estado = %{count: 2, node: :increment}

[5. node_started: increment]     ejecuta increment()
                                 💥 CRASH (count = 3)

[sin cambios]                    Supervisor reinicia

[sin cambios]                    init() lee eventos [1-5]
                                 Reconstruye:
                                 - completados: start, increment×2
                                 - estado: %{count: 2}
                                 - siguiente: increment (retry)

[6. node_completed: increment]   ejecuta increment() exitosamente
                                 estado = %{count: 3}

...continúa hasta finish...
```

## Snapshots: Optimización

Problema: Si un workflow tiene 1,000,000 de eventos, reconstruir es lento.

**Solución:** Guardar snapshots del estado cada N eventos:

```elixir
defmodule EventStore do
  def create_snapshot(stream_id, estado, last_event_sequence) do
    :ets.insert(:snapshots, {stream_id, %{
      estado: estado,
      sequence: last_event_sequence,
      timestamp: DateTime.utc_now()
    }})
  end

  def get_latest_snapshot(stream_id) do
    case :ets.lookup(:snapshots, stream_id) do
      [{^stream_id, snapshot}] -> {:ok, snapshot}
      [] -> {:error, :no_snapshot}
    end
  end

  def get_events_since(stream_id, sequence) do
    :ets.match_object(:event_store, {{stream_id, :_}, :_})
    |> Enum.map(fn {_key, evento} -> evento end)
    |> Enum.filter(fn evento -> evento.sequence > sequence end)
    |> Enum.sort_by(& &1.sequence)
  end
end
```

**Recuperación con snapshot:**
```elixir
def init(opts) do
  execution_id = opts[:execution_id]

  # Intentar cargar snapshot
  case EventStore.get_latest_snapshot(execution_id) do
    {:ok, snapshot} ->
      # Cargar desde snapshot + eventos nuevos
      eventos_nuevos = EventStore.get_events_since(execution_id, snapshot.sequence)

      estado = Enum.reduce(eventos_nuevos, snapshot.estado, fn evento, state ->
        apply_event(evento, state)
      end)

      {:ok, estado}

    {:error, :no_snapshot} ->
      # No hay snapshot, cargar todos los eventos
      eventos = EventStore.get_events(execution_id)
      estado = rebuild_from_events(eventos)
      {:ok, estado}
  end
end
```

**Beneficio:**
```
Sin snapshot:
  - 1,000,000 eventos → reconstruir todos → 10 segundos

Con snapshot cada 10,000 eventos:
  - Cargar snapshot en evento 990,000 → instantáneo
  - Replay 10,000 eventos → 0.1 segundos
  - Total: 0.1 segundos (100x más rápido)
```

## Ventajas de Event Sourcing

| Característica | Beneficio |
|----------------|-----------|
| **Auditoría completa** | Sabes exactamente qué pasó y cuándo |
| **Time-travel debugging** | Reproduce cualquier punto en el tiempo |
| **Recuperación de crashes** | Nunca pierdes trabajo |
| **Replay determinístico** | Mismos eventos = mismo resultado |
| **Compliance** | Requerimientos regulatorios (finanzas, salud) |
| **Testing** | Tests con eventos reales de producción |

## Desventajas y Trade-offs

| Desventaja | Mitigación |
|------------|-----------|
| Más espacio en DB | Snapshots + compresión |
| Reconstrucción lenta | Snapshots cada N eventos |
| Complejidad | Abstracciones (Cerebelum hace esto por ti) |
| Eventos inmutables | Compensación con eventos nuevos |

## Resumen

```elixir
# Estado tradicional
GuardarEstado(estado_actual)  # Si crashea antes, se pierde

# Event Sourcing
GuardarEvento(evento)  # ✅ Guardado
AplicarEvento(estado, evento)  # Si crashea aquí, no importa

# Al reiniciar
eventos = LeerTodosLosEventos()
estado = ReplayEventos(eventos)  # ¡Recuperado!
```

**Fórmula mágica:**
```
Estado Actual = Replay(Todos los Eventos Guardados)
```

## Ejercicio: Todo List con Event Sourcing

Implementa una lista de tareas con Event Sourcing que sobreviva crashes:

<details>
<summary>Ver solución</summary>

```elixir
defmodule TodoList do
  use GenServer

  def start_link(list_id) do
    GenServer.start_link(__MODULE__, list_id, name: via_tuple(list_id))
  end

  def add_task(list_id, task) do
    GenServer.call(via_tuple(list_id), {:add_task, task})
  end

  def complete_task(list_id, task_id) do
    GenServer.call(via_tuple(list_id), {:complete_task, task_id})
  end

  def get_tasks(list_id) do
    GenServer.call(via_tuple(list_id), :get_tasks)
  end

  # Callbacks

  def init(list_id) do
    EventStore.init()

    # Reconstruir desde eventos
    eventos = EventStore.get_events(list_id)

    estado = Enum.reduce(eventos, %{list_id: list_id, tasks: %{}}, fn evento, state ->
      apply_event(evento, state)
    end)

    {:ok, estado}
  end

  def handle_call({:add_task, task}, _from, state) do
    task_id = generate_id()

    evento = %{
      tipo: :task_added,
      task_id: task_id,
      task: task,
      timestamp: DateTime.utc_now()
    }

    EventStore.append_event(state.list_id, evento)
    nuevo_estado = apply_event(evento, state)

    {:reply, {:ok, task_id}, nuevo_estado}
  end

  def handle_call({:complete_task, task_id}, _from, state) do
    evento = %{
      tipo: :task_completed,
      task_id: task_id,
      timestamp: DateTime.utc_now()
    }

    EventStore.append_event(state.list_id, evento)
    nuevo_estado = apply_event(evento, state)

    {:reply, :ok, nuevo_estado}
  end

  def handle_call(:get_tasks, _from, state) do
    {:reply, state.tasks, state}
  end

  # Event application

  defp apply_event(%{tipo: :task_added, task_id: id, task: task}, state) do
    nueva_task = %{id: id, description: task, completed: false}
    %{state | tasks: Map.put(state.tasks, id, nueva_task)}
  end

  defp apply_event(%{tipo: :task_completed, task_id: id}, state) do
    updated_task = Map.update!(state.tasks, id, fn task ->
      %{task | completed: true}
    end)

    %{state | tasks: updated_task}
  end

  defp via_tuple(list_id), do: {:via, Registry, {TodoRegistry, list_id}}
  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16()
end

# Usar con supervisor
{:ok, _} = TodoList.start_link("lista-compras")

{:ok, task_id} = TodoList.add_task("lista-compras", "Comprar leche")

# Simular crash
Process.exit(Process.whereis({:via, Registry, {TodoRegistry, "lista-compras"}}), :kill)

# Supervisor reinicia
:timer.sleep(100)

# ¡Los datos persisten!
tasks = TodoList.get_tasks("lista-compras")
IO.inspect(tasks)
# %{"ABC123" => %{id: "ABC123", description: "Comprar leche", completed: false}}
```
</details>

## Siguiente: Fault Tolerance

Ahora entiendes cómo Event Sourcing permite recuperar estado. En el [próximo tutorial](04-fault-tolerance.md), veremos el **modelo completo de manejo de fallos** en Cerebelum.

## Referencias

- [Martin Fowler - Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)
- [Greg Young - CQRS and Event Sourcing](https://www.youtube.com/watch?v=JHGkaShoyNs)
- [Event Store - Projections](https://www.eventstore.com/event-sourcing)
