# Tutorial 4: Fault Tolerance Model

**Tiempo estimado:** 30 minutos
**Prerrequisitos:** Tutoriales [1](01-understanding-processes.md), [2](02-genservers-and-supervision.md), [3](03-event-sourcing.md)

## Introducción

Ahora que entiendes procesos, supervisión y event sourcing, veamos cómo Cerebelum combina todo para crear un sistema **completamente tolerante a fallos**.

## Tipos de Fallos

### 1. Errores Controlados (`{:error, reason}`)

Son errores esperados del dominio de negocio:

```elixir
defmodule PaymentWorkflow do
  use Cerebelum.Workflow

  def charge_card(state) do
    case PaymentService.charge(state.amount, state.card) do
      {:ok, receipt} ->
        {:ok, Map.put(state, :receipt, receipt)}

      {:error, :insufficient_funds} ->
        # Error de negocio - NO es un crash
        {:error, :insufficient_funds}

      {:error, :card_expired} ->
        {:error, :card_expired}
    end
  end

  def handle_payment_error(state) do
    # Lógica de compensación
    notify_user("Payment failed: #{state.error}")
    {:ok, %{state | status: :payment_failed}}
  end

  workflow do
    edge &start/1 -> &charge_card/1

    # Manejo explícito de errores
    edge &charge_card/1 -> &success/1, when: {:ok, _}
    edge &charge_card/1 -> &handle_payment_error/1, when: {:error, _}
  end
end
```

**Flujo visual:**
```
start → charge_card → {:error, :insufficient_funds}
                   ↓
          handle_payment_error
                   ↓
          notify_user("Payment failed")
                   ↓
                 finish
```

**Eventos guardados:**
```
1. execution_started
2. node_completed: start
3. node_completed: charge_card (error: :insufficient_funds)
4. node_completed: handle_payment_error
5. execution_completed (status: payment_failed)
```

### 2. Excepciones (Crashes)

Errores inesperados que hacen que el proceso muera:

```elixir
def risky_node(state) do
  # Esto causa un crash
  raise "Database connection lost!"

  # O esto
  nil.some_field  # NoMethodError

  # O esto
  1 / 0  # ArithmeticError
end
```

**¿Qué pasa cuando hay un crash?**

```
Tiempo   Evento                           Estado del Sistema
──────────────────────────────────────────────────────────────────

T1       Ejecutando risky_node           [Proceso ejecutando]

T2       💥 raise "DB connection lost"   [Proceso MUERE]

T3       Supervisor detecta muerte       [Supervisor activo]

T4       Supervisor reinicia proceso     [Nuevo proceso inicia]

T5       init() lee eventos de DB        [Reconstruyendo estado]

T6       Replay de todos los eventos     [Estado restaurado]

T7       Decide: ¿Reintentar el nodo?   [Lógica de retry]

T8       Reintenta risky_node            [Ejecutando]

T9       Si falla de nuevo → retry N      [Con backoff]
         Si éxito → continúa              [Workflow sigue]
```

**Código interno de Cerebelum:**

```elixir
defmodule Cerebelum.ExecutionEngine do
  use GenServer

  def init(opts) do
    execution_id = opts[:execution_id]

    # Reconstruir desde eventos
    eventos = EventStore.get_events(execution_id)
    estado = rebuild_from_events(eventos)

    # Analizar último evento
    case List.last(eventos) do
      %{tipo: :node_started, node: node, attempts: attempts} ->
        # El proceso murió mientras ejecutaba este nodo
        if attempts < max_retries(node) do
          # Reintentar con backoff
          backoff = calculate_backoff(attempts)
          Process.send_after(self(), {:retry_node, node}, backoff)
        else
          # Max intentos alcanzado - marcar como fallido
          evento = %{tipo: :node_failed, node: node, reason: :max_retries}
          EventStore.append_event(execution_id, evento)
          {:stop, :normal, estado}
        end

      _ ->
        # Continuar normalmente
        send(self(), :continue_execution)
    end

    {:ok, estado}
  end
end
```

### 3. Timeouts

El nodo tarda demasiado y excede el timeout:

```elixir
def slow_api_call(state) do
  # Esta llamada puede tardar horas
  result = ExternalAPI.fetch_large_dataset(state.query)
  {:ok, result}
end

# Configuración del workflow
workflow do
  node &slow_api_call/1, timeout: :timer.seconds(30)
  # Si tarda más de 30 segundos → timeout
end
```

**Implementación interna:**

```elixir
def execute_node(node_func, state, opts) do
  timeout = opts[:timeout] || :timer.seconds(60)

  task = Task.async(fn ->
    node_func.(state)
  end)

  case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
    {:ok, result} ->
      result

    nil ->
      # Timeout!
      {:error, :timeout}
  end
end
```

**Eventos:**
```
1. node_started: slow_api_call (attempt: 1)
2. node_failed: slow_api_call (reason: :timeout, attempt: 1)
3. node_started: slow_api_call (attempt: 2, backoff: 1s)
... retry con exponential backoff ...
```

## Retry Policies

Cerebelum soporta configuración granular de retry por nodo:

```elixir
defmodule ResilientWorkflow do
  use Cerebelum.Workflow

  # API externa que puede fallar temporalmente
  def fetch_data(state) do
    case ExternalAPI.get("/data") do
      {:ok, data} -> {:ok, Map.put(state, :data, data)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Operación crítica que NO debe fallar
  def save_to_database(state) do
    DB.insert(state.data)
    {:ok, state}
  end

  workflow do
    node &fetch_data/1,
      retry_policy: [
        max_attempts: 5,
        initial_interval: :timer.seconds(1),
        backoff_coefficient: 2.0,  # 1s, 2s, 4s, 8s, 16s
        max_interval: :timer.minutes(1),
        retryable_errors: [:network_error, :timeout, :service_unavailable]
      ]

    node &save_to_database/1,
      retry_policy: [
        max_attempts: 10,  # Más intentos para operaciones críticas
        initial_interval: :timer.seconds(2),
        backoff_coefficient: 1.5
      ]

    edge &fetch_data/1 -> &save_to_database/1
  end
end
```

**Visual de retry con backoff:**
```
Intento 1: 💥 falla → espera 1s
Intento 2: 💥 falla → espera 2s  (1s * 2.0)
Intento 3: 💥 falla → espera 4s  (2s * 2.0)
Intento 4: 💥 falla → espera 8s  (4s * 2.0)
Intento 5: ✅ éxito → continúa
```

## Saga Pattern: Transacciones Distribuidas

Para workflows que necesitan coordinación entre múltiples servicios:

```elixir
defmodule BookingWorkflow do
  use Cerebelum.Workflow

  # Acciones principales (forward)
  def book_flight(state) do
    case FlightService.book(state.flight_id) do
      {:ok, booking} ->
        {:ok, Map.put(state, :flight_booking, booking)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def book_hotel(state) do
    case HotelService.book(state.hotel_id) do
      {:ok, booking} ->
        {:ok, Map.put(state, :hotel_booking, booking)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def charge_card(state) do
    case PaymentService.charge(state.total) do
      {:ok, charge} ->
        {:ok, Map.put(state, :charge_id, charge.id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Compensaciones (backward) - se ejecutan en orden inverso
  def cancel_hotel(state) do
    HotelService.cancel(state.hotel_booking.id)
    {:ok, state}
  end

  def cancel_flight(state) do
    FlightService.cancel(state.flight_booking.id)
    {:ok, state}
  end

  def refund_card(state) do
    if state[:charge_id] do
      PaymentService.refund(state.charge_id)
    end
    {:ok, state}
  end

  workflow do
    # Happy path (forward)
    edge &start/1 -> &book_flight/1
    edge &book_flight/1 -> &book_hotel/1, when: {:ok, _}
    edge &book_hotel/1 -> &charge_card/1, when: {:ok, _}
    edge &charge_card/1 -> &success/1, when: {:ok, _}

    # Sad path (compensaciones en cascade)
    edge &charge_card/1 -> &cancel_hotel/1, when: {:error, _}
    edge &cancel_hotel/1 -> &cancel_flight/1
    edge &cancel_flight/1 -> &failure/1

    edge &book_hotel/1 -> &cancel_flight/1, when: {:error, _}

    edge &book_flight/1 -> &failure/1, when: {:error, _}
  end
end
```

**Escenario 1: Todo funciona**
```
book_flight ✅ → book_hotel ✅ → charge_card ✅ → success
```

**Escenario 2: Falla charge_card**
```
book_flight ✅ → book_hotel ✅ → charge_card 💥
                                       ↓
                            cancel_hotel ✅
                                       ↓
                            cancel_flight ✅
                                       ↓
                                   failure
```

**Eventos guardados:**
```
1. node_completed: book_flight (booking: {id: "FL123"})
2. node_completed: book_hotel (booking: {id: "HT456"})
3. node_failed: charge_card (error: :card_declined)
4. node_completed: cancel_hotel (cancelled: "HT456")
5. node_completed: cancel_flight (cancelled: "FL123")
6. execution_completed (status: :compensated)
```

**Si el proceso crashea durante compensación:**
```
book_flight ✅ → book_hotel ✅ → charge_card 💥
                                       ↓
                            cancel_hotel ✅
                                       ↓
                            cancel_flight ← 💥 CRASH AQUÍ

--- Supervisor reinicia ---

                    init() lee eventos:
                    - flight booked ✅
                    - hotel booked ✅
                    - charge failed 💥
                    - hotel cancelled ✅
                    - flight cancel in progress...

                    Retoma: cancel_flight
                                       ↓
                            cancel_flight ✅  ← ¡Completa la compensación!
                                       ↓
                                   failure
```

## Checkpointing para Operaciones Largas

Para workflows que toman días/meses/años:

```elixir
defmodule LongRunningWorkflow do
  use Cerebelum.Workflow

  def process_large_dataset(state) do
    total = state.total_items
    processed = state[:processed] || 0

    # Procesar en lotes de 100
    Enum.reduce_while(processed..(total - 1), state, fn i, acc ->
      item = fetch_item(i)
      result = process_item(item)

      # Checkpoint cada 100 items
      if rem(i + 1, 100) == 0 do
        checkpoint_state = %{acc | processed: i + 1, results: [result | acc.results]}

        # Guardar checkpoint (evento especial)
        EventStore.append_event(state.execution_id, %{
          tipo: :checkpoint,
          node: :process_large_dataset,
          state: checkpoint_state
        })

        {:cont, checkpoint_state}
      else
        {:cont, %{acc | results: [result | acc.results]}}
      end
    end)

    {:ok, state}
  end
end
```

**Beneficio:**
```
Procesando item 5,550 de 10,000
💥 Crash!
--- Reinicio ---
Lee último checkpoint: item 5,500
Continúa desde item 5,500  ← ¡Solo re-procesa 50 items!
```

## Disaster Recovery

### Escenario 1: VM Crash (toda la máquina se apaga)

```elixir
# T1: Workflows corriendo
Execution 1 (PID<0.123>) → ejecutando nodo :fetch_data
Execution 2 (PID<0.124>) → esperando sleep(30 días)
Execution 3 (PID<0.125>) → esperando human approval

# T2: 💥 VM crash (se va la luz, kernel panic, etc.)

# T3: VM reinicia, aplicación inicia

# T4: ExecutionRecovery proceso inicia
defmodule Cerebelum.ExecutionRecovery do
  use GenServer

  def init(_) do
    # Buscar ejecuciones activas en DB
    active_executions = DB.query("""
      SELECT execution_id, workflow, last_event
      FROM executions
      WHERE status IN ('running', 'waiting')
    """)

    # Reiniciar cada una
    for exec <- active_executions do
      ExecutionSupervisor.start_execution(exec.workflow, exec.execution_id)
    end

    {:ok, %{}}
  end
end

# T5: Cada ejecución se reconstruye desde eventos
Execution 1 → lee eventos → estaba en :fetch_data → reintenta
Execution 2 → lee eventos → timer para 29 días 23 horas 45 min restantes
Execution 3 → lee eventos → esperando approval → reconecta webhook
```

### Escenario 2: Network Partition

```elixir
defmodule Cerebelum.NetworkAware do
  def execute_node_with_partition_handling(node, state) do
    case execute_node(node, state) do
      {:error, :network_error} ->
        # Detectar si es partition o servicio down
        if can_reach_alternative_endpoint?() do
          # Network partition - esperar y reintentar
          :timer.sleep(5000)
          execute_node_with_partition_handling(node, state)
        else
          # Servicio realmente down - usar retry policy
          {:error, :service_unavailable}
        end

      result ->
        result
    end
  end
end
```

### Escenario 3: Database Failover

```elixir
# PostgreSQL en modo Primary-Replica

# T1: Escritura a Primary
EventStore.append_event(exec_id, evento)  # ✅ Éxito

# T2: Primary muere 💥

# T3: Replica promovida a Primary (automático con Patroni/Stolon)

# T4: Aplicación detecta y reconecta
Repo.disconnect()
Repo.connect(new_primary_url)

# T5: Workflow continúa sin pérdida de datos
# Todos los eventos están en la nueva Primary
```

## Modelo Completo de Recuperación

```elixir
defmodule Cerebelum.ExecutionEngine do
  use GenServer

  def init(opts) do
    execution_id = opts[:execution_id]

    # Paso 1: Cargar snapshot si existe
    snapshot = EventStore.get_latest_snapshot(execution_id)

    # Paso 2: Cargar eventos desde snapshot
    eventos = case snapshot do
      {:ok, snap} ->
        EventStore.get_events_since(execution_id, snap.sequence)

      {:error, :no_snapshot} ->
        EventStore.get_events(execution_id)
    end

    # Paso 3: Reconstruir estado
    estado_base = snapshot[:estado] || %ExecutionState{}
    estado = Enum.reduce(eventos, estado_base, &apply_event/2)

    # Paso 4: Analizar situación actual
    strategy = determine_recovery_strategy(estado, eventos)

    # Paso 5: Ejecutar estrategia
    case strategy do
      :continue_from_current ->
        send(self(), :continue_execution)

      {:retry_node, node, delay} ->
        Process.send_after(self(), {:retry_node, node}, delay)

      {:wait_for_timer, remaining_ms} ->
        Process.send_after(self(), :timer_expired, remaining_ms)

      {:wait_for_approval, approval_id} ->
        ApprovalManager.resubscribe(approval_id)

      :mark_as_failed ->
        evento = %{tipo: :execution_failed, reason: :max_retries_exceeded}
        EventStore.append_event(execution_id, evento)
        {:stop, :normal, estado}
    end

    {:ok, estado}
  end

  defp determine_recovery_strategy(estado, eventos) do
    ultimo_evento = List.last(eventos)

    case ultimo_evento do
      %{tipo: :node_started, node: node, attempts: attempts} ->
        # Proceso murió mientras ejecutaba - retry?
        if attempts < max_attempts(node) do
          delay = calculate_backoff(attempts)
          {:retry_node, node, delay}
        else
          :mark_as_failed
        end

      %{tipo: :sleep_started, wake_at: wake_at} ->
        now = DateTime.utc_now()
        remaining = DateTime.diff(wake_at, now, :millisecond)

        if remaining > 0 do
          {:wait_for_timer, remaining}
        else
          :continue_from_current
        end

      %{tipo: :approval_requested, approval_id: id} ->
        {:wait_for_approval, id}

      _ ->
        :continue_from_current
    end
  end
end
```

## Testing Fault Tolerance

Cerebelum provee helpers para testing de fallos:

```elixir
defmodule MyWorkflowTest do
  use Cerebelum.TestCase

  test "workflow survives crash during critical node" do
    # Configurar mock para crashear
    expect(ExternalAPI, :fetch, fn _ ->
      raise "Simulated crash"
    end)

    # Iniciar workflow
    {:ok, execution_id} = Cerebelum.start_workflow(MyWorkflow, %{})

    # Esperar a que crashee
    assert_receive {:execution_crashed, ^execution_id}, 1000

    # Mock ahora funciona
    expect(ExternalAPI, :fetch, fn _ ->
      {:ok, "data"}
    end)

    # El workflow debe recuperarse automáticamente
    assert_receive {:execution_completed, ^execution_id}, 5000
  end

  test "workflow respects max retries" do
    # Mock siempre falla
    expect(ExternalAPI, :fetch, fn _ ->
      {:error, :network_error}
    end)

    {:ok, execution_id} = Cerebelum.start_workflow(MyWorkflow, %{},
      retry_policy: [max_attempts: 3]
    )

    # Debe fallar después de 3 intentos
    assert_receive {:execution_failed, ^execution_id, :max_retries}, 10_000
  end
end
```

## Resumen: Modelo Completo

| Tipo de Fallo | Detección | Recuperación | Garantía |
|---------------|-----------|--------------|----------|
| **Error controlado** | Retorno `{:error, reason}` | Edge a nodo de manejo | Exactamente una vez |
| **Crash (exception)** | Supervisor detecta muerte | Reinicio + replay events + retry | Al menos una vez |
| **Timeout** | Task no responde | Kill task + retry con backoff | Al menos una vez |
| **VM crash** | ExecutionRecovery al boot | Reiniciar desde DB + replay | Al menos una vez |
| **Network partition** | Detect + wait | Esperar reconexión + retry | Al menos una vez |
| **DB failover** | Connection error | Reconectar a nueva primary | Exactamente una vez* |

\* Con transacciones

## Siguiente: Code-First Workflows

Ahora entiendes el modelo completo de fault tolerance. En el [próximo tutorial](05-workflow-code-first.md), aprenderás cómo escribir workflows usando código Elixir.

## Referencias

- [Temporal.io - Fault Tolerance](https://docs.temporal.io/concepts/what-is-a-failure/)
- [Chris McCord - Phoenix LiveView Resilience](https://www.youtube.com/watch?v=XhNv1ikZNLs)
- [Joe Armstrong - Erlang Thesis (Chapter 5: Fault Tolerance)](https://erlang.org/download/armstrong_thesis_2003.pdf)
