# Cerebelum vs Temporal.io: Análisis Arquitectural Completo

**Fecha:** 2024-12-11
**Autor:** Análisis técnico para competir con Temporal.io

---

## 1. Estado Actual de Cerebelum Core

### Dos Arquitecturas Separadas

#### A. **Engine System** (Elixir Workflows) ✅ COMPLETO

```
User → Cerebelum.execute_workflow(MyWorkflow, inputs)
         ↓
    Execution.Supervisor.start_execution()
         ↓
    Execution.Engine (GenStateMachine)
         ↓
    - Ejecuta steps (código Elixir)
    - Emite eventos a EventStore
    - Maneja Sleep/Approval
    - StateReconstructor para resurrection
    - Resurrector automático en boot
    - WorkflowScheduler para timers
```

**Capacidades:**
- ✅ Resurrection completa
- ✅ Sleep multi-día con hibernación
- ✅ State reconstruction desde eventos
- ✅ Sobrevive restarts del sistema
- ✅ EventStore con persistencia
- ✅ Approval workflows
- ✅ Scheduler externo

**Limitaciones:**
- ❌ Solo workflows de Elixir
- ❌ No distribuido a workers externos

---

#### B. **Worker System** (Distributed) ❌ SIN RESURRECTION

```
Python Worker → gRPC ExecuteRequest
                  ↓
           worker_service_server.ex: execute_workflow()
                  ↓
           BlueprintRegistry.get_blueprint()
                  ↓
           ExecutionStateManager.create_execution() (ETS only!)
                  ↓
           TaskRouter.queue_initial_tasks()
                  ↓
           Worker polls → TaskRouter.poll_for_task()
                  ↓
           Worker ejecuta step → submit_result()
                  ↓
           ExecutionStateManager.complete_step() (ETS only!)
                  ↓
           ExecutionStateManager.get_next_steps()
                  ↓
           TaskRouter.queue_next_steps()
```

**Capacidades:**
- ✅ Workers distribuidos (Python, Kotlin, TypeScript)
- ✅ Long-polling para tasks
- ✅ Sticky routing (cache locality)
- ✅ Task retry con exponential backoff
- ✅ DLQ para tasks fallidos
- ✅ Diverge/Branch rules
- ✅ Timeline dependencies

**Limitaciones Críticas:**
- ❌ NO usa EventStore (solo ETS en memoria)
- ❌ NO emite eventos
- ❌ NO hay resurrection
- ❌ Si Core muere, ejecuciones se pierden
- ❌ NO hay Sleep/Approval
- ❌ NO sobrevive restarts

---

## 2. Arquitectura de Temporal.io

### Modelo de Ejecución

```
Python Worker → Registra workflow code
                  ↓
Client → temporal.start_workflow("my_workflow", inputs)
           ↓
      Temporal Server persiste WorkflowTaskScheduled event
           ↓
      Worker polls → Recibe WorkflowTask + event history
           ↓
      Worker EJECUTA workflow code con replay determinístico
           ↓
      Worker genera commands (ScheduleActivityTask, StartTimer, etc)
           ↓
      Temporal Server persiste eventos
           ↓
      Worker polls → Recibe ActivityTask
           ↓
      Worker ejecuta activity
           ↓
      Worker envía ActivityTaskCompleted
           ↓
      Temporal Server persiste evento + envía nuevo WorkflowTask
           ↓
      Worker re-ejecuta workflow con historial actualizado
```

### Componentes Clave

| Componente | Responsabilidad |
|------------|-----------------|
| **Temporal Server** | • Persiste eventos (event sourcing)<br>• Maneja timers (sleep, timeout)<br>• Coordina workers<br>• NO ejecuta código del usuario |
| **Worker** | • Ejecuta workflow code (orquestación)<br>• Ejecuta activities (steps)<br>• Re-ejecuta determinísticamente con historial |
| **Event History** | • Log inmutable de todos los eventos<br>• Fuente de verdad para reconstruir estado<br>• Workflows leen historial para resumir |

### Eventos en Temporal.io

```python
# Worker ejecuta workflow code
@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, user_id: str):
        # Step 1: Activity
        user = await workflow.execute_activity(
            fetch_user,
            user_id,
            start_to_close_timeout=timedelta(seconds=30)
        )
        # → Genera comando: ScheduleActivityTask
        # → Server persiste: ActivityTaskScheduled
        # → Worker ejecuta activity
        # → Worker persiste: ActivityTaskCompleted

        # Step 2: Sleep
        await asyncio.sleep(10)  # workflow.sleep()
        # → Genera comando: StartTimer(10s)
        # → Server persiste: TimerStarted
        # → Worker puede morir aquí
        # → Server espera 10s
        # → Server persiste: TimerFired
        # → Nuevo WorkflowTask enviado a worker
        # → Worker re-ejecuta desde el principio con historial
        # → Worker lee historial y salta hasta después del sleep

        # Step 3: Otra activity
        await workflow.execute_activity(send_email, user)
```

**Eventos generados:**
1. WorkflowExecutionStarted
2. WorkflowTaskScheduled
3. WorkflowTaskStarted
4. WorkflowTaskCompleted → Commands: [ScheduleActivityTask(fetch_user)]
5. ActivityTaskScheduled(fetch_user)
6. ActivityTaskStarted(fetch_user)
7. ActivityTaskCompleted(fetch_user) → result: {...}
8. WorkflowTaskScheduled
9. WorkflowTaskStarted
10. WorkflowTaskCompleted → Commands: [StartTimer(10s)]
11. TimerStarted(10s)
12. **[Worker puede morir aquí - no importa]**
13. TimerFired (después de 10s)
14. WorkflowTaskScheduled
15. WorkflowTaskStarted
16. WorkflowTaskCompleted → Commands: [ScheduleActivityTask(send_email)]
17. ...

### Determinismo y Replay

**Regla de Oro:** El workflow code debe ser determinístico.

```python
# ❌ MAL - No determinístico
@workflow.run
async def bad_workflow(self):
    if random.random() > 0.5:  # ← NUNCA hacer esto
        return "A"
    else:
        return "B"

# ✅ BIEN - Determinístico
@workflow.run
async def good_workflow(self):
    result = await workflow.execute_activity(get_random_number)
    if result > 0.5:  # ← Activity result está en el historial
        return "A"
    else:
        return "B"
```

**Por qué:** Cuando el worker resucita, re-ejecuta el workflow code desde el principio, pero en vez de ejecutar activities, LEE los resultados del historial. Si el código no es determinístico, tomará diferentes decisiones y generará comandos diferentes.

---

## 3. Diferencias Críticas

| Aspecto | Temporal.io | Cerebelum Engine | Cerebelum Worker System |
|---------|-------------|------------------|-------------------------|
| **Workflow code ejecuta en** | Worker | Core (BEAM) | ❌ No hay workflow code |
| **Orquestación** | Worker (determinístico) | Engine (state machine) | TaskRouter (queue) |
| **Persistencia** | Event sourcing (Cassandra/PostgreSQL) | EventStore (PostgreSQL) | ❌ Solo ETS (memoria) |
| **Resurrection** | Re-ejecuta workflow con historial | StateReconstructor | ❌ No existe |
| **Sleep** | Server timer + historial | Engine state machine | ❌ No soportado |
| **Worker muere** | Server resucita otro worker | Engine continúa (solo Elixir) | ❌ Ejecución se pierde |
| **Eventos** | Todo es evento | Solo Engine emite | ❌ No emite eventos |
| **Replay determinístico** | ✅ Worker re-ejecuta | ✅ StateReconstructor | ❌ No aplica |

---

## 4. Gap Analysis: Qué falta para competir

### 4.1. Worker System NO tiene resurrection

**Problema:**
```python
# Python Worker ejecuta workflow
@step
async def wait_for_ip(context, inputs):
    for i in range(30):
        droplet = check_droplet()
        if droplet.ip:
            return {"ip": droplet.ip}
        await sleep(5000)  # ← Esto usa asyncio.sleep()
```

**Qué pasa hoy:**
1. Worker duerme localmente con `asyncio.sleep(5000)`
2. Si Worker muere → workflow se pierde
3. Core no sabe del sleep
4. ExecutionStateManager solo tiene estado en ETS
5. Core restart → todo se pierde

**Qué debería pasar (Temporal model):**
1. `sleep(5000)` envía comando al Core
2. Core persiste `TimerStarted` event
3. Core programa timer de 5s
4. Worker puede morir - no importa
5. Core espera 5s
6. Core persiste `TimerFired` event
7. Core envía nueva Task al Worker
8. Worker recibe historial completo
9. Worker re-ejecuta step con historial
10. Worker continúa después del sleep

### 4.2. Worker NO envía eventos

**Problema:**
```python
# Worker ejecuta step
async def create_droplet(context, inputs):
    droplet = api.create()
    return {"droplet_id": droplet.id}

# Worker envía SOLO el resultado
→ gRPC TaskResult {status: SUCCESS, result: {droplet_id: 123}}
```

**Core solo ve:** "Step X completó con resultado Y"

**Qué falta:**
- Core no sabe QUÉ pasó durante la ejecución
- No hay eventos para reconstruir estado
- No hay historial para replay

**Temporal model:**
```python
# Worker ejecuta y GENERA EVENTOS
result = await worker.execute_activity(create_droplet)
# Worker envía:
# - ActivityTaskStarted
# - ActivityTaskCompleted con resultado
# Estos eventos se persisten en el server
```

### 4.3. Worker NO recibe historial

**Problema:**
```python
# Worker recibe Task para ejecutar step
task = poll_for_task()
# task.step_inputs = {...}
# task.context = {...}
```

**Qué falta:**
- Worker no recibe historial de eventos previos
- No puede reconstruir estado
- No puede hacer replay determinístico

**Temporal model:**
```protobuf
message WorkflowTask {
  string task_id = 1;
  string execution_id = 2;

  // ✅ Historial completo para replay
  repeated Event event_history = 3;

  string step_name = 4;
  Struct step_inputs = 5;
}
```

### 4.4. ExecutionStateManager no persiste

**Problema:**
```elixir
# ExecutionStateManager usa solo ETS
def create_execution(execution_id, blueprint, inputs) do
  execution_state = %{
    execution_id: execution_id,
    completed_steps: %{},
    pending_steps: MapSet.new(...),
    # ...
  }

  :ets.insert(@table_name, {execution_id, execution_state})
  # ❌ NO persiste a DB
  # ❌ NO emite eventos
end
```

**Consecuencias:**
- Core restart → estado se pierde
- No hay eventos para reconstruir
- No hay resurrection

---

## 5. Arquitectura Propuesta: Unificación

### Opción A: Worker System delega al Engine (RECOMENDADA)

```
Python Worker → gRPC ExecuteRequest
                  ↓
           worker_service_server.ex: execute_workflow()
                  ↓
           Execution.Supervisor.start_execution()  ← NUEVO
                  ↓
           Execution.Engine (state machine)
                  ↓
           Para cada step:
             - Engine emite StepStartedEvent
             - Engine delega a TaskRouter.queue_task()
             - Worker polls y ejecuta
             - Worker envía resultado
             - Engine emite StepCompletedEvent
             - Engine continúa con siguiente step
                  ↓
           Sleep/Approval:
             - Worker envía SleepRequest en TaskResult
             - Engine procesa y entra en :sleeping state
             - Engine emite SleepStartedEvent
             - Hibernation/Resurrection funcionan ✅
```

**Ventajas:**
- ✅ Reusa toda la infraestructura de resurrection
- ✅ Workers obtienen Sleep/Approval automáticamente
- ✅ Un solo camino de ejecución unificado
- ✅ EventStore para todo
- ✅ No duplicamos código

**Implementación:**

1. **Modificar `worker_service_server.ex:execute_workflow`**
```elixir
def execute_workflow(request, _stream) do
  # En vez de:
  # ExecutionStateManager.create_execution(...)
  # TaskRouter.queue_initial_tasks(...)

  # Hacer:
  {:ok, pid} = Execution.Supervisor.start_execution(
    WorkerDelegatingWorkflow,  # ← NUEVO
    inputs,
    blueprint: blueprint
  )
end
```

2. **Crear `WorkerDelegatingWorkflow`**
```elixir
defmodule Cerebelum.WorkerDelegatingWorkflow do
  use Cerebelum.Workflow

  # Workflow dinámico que carga blueprint y delega steps a workers
  workflow do
    # Timeline, diverge, branch se cargan dinámicamente del blueprint
  end

  # Cada step delega al Worker
  def execute_step(context, step_name, inputs) do
    # Queue task to TaskRouter
    task = %{
      workflow_module: context.workflow_module,
      step_name: step_name,
      inputs: inputs
    }

    {:ok, task_id} = TaskRouter.queue_task(context.execution_id, task)

    # Block hasta que worker complete
    result = await_task_completion(task_id)

    # Check si worker pidió sleep/approval
    case result do
      {:sleep, duration_ms, data} ->
        {:sleep, [milliseconds: duration_ms], data}

      {:approval, approval_data} ->
        {:approval, approval_data}

      {:ok, data} ->
        {:ok, data}
    end
  end
end
```

3. **Extender `TaskResult` protobuf**
```protobuf
message TaskResult {
  string task_id = 1;
  string execution_id = 2;

  TaskStatus status = 3;
  google.protobuf.Struct result = 4;

  // ✅ NUEVO: Sleep/Approval requests
  SleepRequest sleep_request = 5;
  ApprovalRequest approval_request = 6;
}
```

4. **Python SDK: `sleep()` helper actualizado**
```python
async def sleep(duration: int) -> None:
    """Sleep workflow-aware."""
    context = get_current_context()

    if context.distributed:
        # ✅ NUEVO: Return special marker
        return {"_sleep": True, "duration_ms": duration}
    else:
        # Local mode
        await asyncio.sleep(duration / 1000)
```

---

### Opción B: Modelo Temporal.io completo (MÁS COMPLEJO)

Worker ejecuta workflow code con replay determinístico.

```
Python Worker → Registra workflow definition
                  ↓
Client → executor.execute("my_workflow", inputs)
           ↓
      Core persiste WorkflowExecutionStarted
           ↓
      Worker polls → Recibe WorkflowTask + event history []
           ↓
      Worker ejecuta workflow code:
        @workflow
        def my_workflow(wf):
            wf.timeline(step1 >> step2)
           ↓
      Worker genera comandos:
        - ScheduleActivityTask(step1)
           ↓
      Core persiste ActivityTaskScheduled
           ↓
      Worker polls → Recibe ActivityTask(step1)
           ↓
      Worker ejecuta step1 → resultado
           ↓
      Core persiste ActivityTaskCompleted
           ↓
      Worker polls → Recibe WorkflowTask + history [ActivityTaskCompleted]
           ↓
      Worker RE-EJECUTA workflow code con history:
        - Lee history: step1 completó con resultado X
        - Continúa con step2
           ↓
      Worker genera comando: ScheduleActivityTask(step2)
```

**Requiere:**
1. Worker envía eventos (no solo resultados)
2. Core persiste eventos en EventStore
3. Worker recibe historial completo
4. Worker hace replay determinístico
5. DSLLocalExecutor con replay capability

**Complejidad:** ALTA - requiere rediseño completo del Worker SDK

---

## 6. Recomendación

### Fase 1: Opción A - Worker delega al Engine ⭐

**Por qué:**
- Aprovecha todo el trabajo de resurrection ya hecho
- Menor complejidad de implementación
- Workers obtienen Sleep/Approval inmediatamente
- Unifica las dos arquitecturas

**Limitación:**
- Engine ejecuta la orquestación (no el Worker)
- No es 100% igual a Temporal.io
- Worker solo ejecuta steps individuales

**Pero suficiente para:**
- ✅ Resurrection completa
- ✅ Sleep multi-día
- ✅ Workflows distribuidos
- ✅ Competir con casos de uso básicos de Temporal

### Fase 2: Modelo Temporal.io completo (Futuro)

Cuando necesitemos:
- Worker ejecuta orquestación completa
- Replay determinístico completo
- 100% paridad con Temporal.io

---

## 7. Tasks para Implementar Opción A

### 7.1. Protocolo gRPC

- [ ] Extender `TaskResult` con `SleepRequest` y `ApprovalRequest`
- [ ] Regenerar protobuf: `mix protobuf.generate`

### 7.2. Core (Elixir)

- [ ] Crear `WorkerDelegatingWorkflow` module
- [ ] Modificar `worker_service_server.ex:execute_workflow` para usar Engine
- [ ] Modificar `worker_service_server.ex:submit_result` para procesar Sleep/Approval
- [ ] Integrar TaskRouter con Engine

### 7.3. Python SDK

- [ ] Actualizar `sleep()` helper para modo distribuido
- [ ] Actualizar `DSLLocalExecutor` para generar sleep markers
- [ ] Actualizar `Worker._execute_task` para enviar SleepRequest
- [ ] Documentación de resurrection en distributed mode

### 7.4. Testing

- [ ] Test: Python → Core → Sleep → Kill Core → Resurrect → Complete
- [ ] Test: Python → Core → Sleep → Kill Worker → Continue → Complete
- [ ] Test: Multi-step workflow con resurrection
- [ ] Test: Approval workflow distribuido

### 7.5. Documentación

- [ ] Guía: "Resurrection for Distributed Workflows"
- [ ] Comparación con Temporal.io
- [ ] Migration guide

---

## 8. Comparación Final

| Feature | Temporal.io | Cerebelum (HOY) | Cerebelum (Opción A) |
|---------|-------------|-----------------|----------------------|
| Distributed workers | ✅ | ✅ | ✅ |
| Event sourcing | ✅ | ✅ Engine only | ✅ Unified |
| Resurrection | ✅ | ✅ Engine only | ✅ Unified |
| Sleep multi-día | ✅ | ✅ Engine only | ✅ Unified |
| Hibernation | ✅ | ✅ Engine only | ✅ Unified |
| Worker ejecuta orquestación | ✅ | ❌ | ❌ |
| Replay determinístico en Worker | ✅ | ❌ | ❌ |
| Multi-language (Python, Go, Java) | ✅ | ✅ | ✅ |
| Long-polling | ✅ | ✅ | ✅ |
| Retry & DLQ | ✅ | ✅ | ✅ |

**Conclusión:** Opción A nos da 80% de paridad con Temporal.io con 20% del esfuerzo.
