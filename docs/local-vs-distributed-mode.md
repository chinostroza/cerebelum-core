# Modo Local vs Modo Distribuido - Estado Actual

**Fecha:** 2024-12-11

---

## Modo Local - DSLLocalExecutor

```python
@workflow
def my_workflow(wf):
    wf.timeline(step1 >> step2)

# Ejecución LOCAL (default)
result = await my_workflow.execute({"user_id": 123})
# distributed=False (default)
```

### Qué hace:
```
Python Process
    ↓
DSLLocalExecutor.execute()
    ↓
Ejecuta step1 → resultado
    ↓
Ejecuta step2 → resultado
    ↓
Return ExecutionResult
```

### Características:
- ✅ Todo corre en proceso Python
- ✅ No requiere Core corriendo
- ✅ `sleep()` usa `asyncio.sleep()`
- ✅ `poll()` y `retry()` funcionan
- ❌ NO hay resurrection (si Python muere, se pierde)
- ❌ NO hay hibernación
- ❌ NO usa Engine del Core
- ❌ NO usa EventStore

**Uso:** Desarrollo, testing, workflows cortos (<30 min)

---

## Modo Distribuido - DistributedExecutor

```python
@workflow
def my_workflow(wf):
    wf.timeline(step1 >> step2)

# Ejecución DISTRIBUIDA
result = await my_workflow.execute({"user_id": 123}, distributed=True)
```

### Qué hace ACTUALMENTE:

```
Python Process
    ↓
DistributedExecutor.execute()
    ↓
gRPC: ExecuteRequest("my_workflow", inputs)
    ↓
Core: worker_service_server.ex:execute_workflow()
    ↓
BlueprintRegistry.get_blueprint()
    ↓
❌ ExecutionStateManager.create_execution() [ETS only]
❌ TaskRouter.queue_initial_tasks()
    ↓
Worker polls for tasks
    ↓
Worker ejecuta step1 → resultado
    ↓
TaskRouter.submit_result()
    ↓
ExecutionStateManager.complete_step()
    ↓
ExecutionStateManager.get_next_steps()
    ↓
TaskRouter.queue_next_task(step2)
    ↓
Worker ejecuta step2 → resultado
    ↓
Workflow completa
```

### Características ACTUALES:
- ✅ Workers distribuidos
- ✅ Long-polling
- ✅ Sticky routing
- ✅ Task retry
- ✅ DLQ para failures
- ❌ NO usa Engine
- ❌ NO emite eventos a EventStore
- ❌ NO hay resurrection (si Core muere, se pierde)
- ❌ NO hay Sleep multi-día
- ❌ NO hay hibernación
- ❌ State solo en ETS (memoria)

**Problema:** Si reinicia el Core, `ExecutionStateManager` (ETS) se pierde.

---

## Modo Distribuido - LO QUE DEBERÍA HACER

### Intención Original (según usuario):
> "mi idea fue crear todo el sistema para funcionar con elixir, y no perder lo de OTP, entonces el python SDK, estaba sobre eso, entonces teniamos todas esas ventajas tmb con python"

### Qué DEBERÍA hacer:

```
Python Process
    ↓
DistributedExecutor.execute()
    ↓
gRPC: ExecuteRequest("my_workflow", inputs)
    ↓
Core: worker_service_server.ex:execute_workflow()
    ↓
✅ Execution.Supervisor.start_execution()  ← DEBERÍA LLAMAR ESTO
    ↓
✅ Execution.Engine (GenStateMachine)
    ↓
Para cada step:
  - ✅ Engine emite StepStartedEvent → EventStore
  - ✅ Engine delega step a TaskRouter
  - ✅ Worker poll y ejecuta step
  - ✅ Worker devuelve resultado
  - ✅ Engine emite StepCompletedEvent → EventStore
  - ✅ Engine continúa con siguiente step
    ↓
Si hay Sleep:
  - ✅ Worker envía SleepRequest
  - ✅ Engine procesa {:sleep, [milliseconds: X], data}
  - ✅ Engine emite SleepStartedEvent → EventStore
  - ✅ Engine puede hibernar (libera memoria)
  - ✅ Core se reinicia → Resurrector lo levanta
  - ✅ WorkflowScheduler lo despierta
  - ✅ Engine continúa ✅
```

### Características DESEADAS:
- ✅ Workers distribuidos
- ✅ Long-polling, retry, DLQ
- ✅ **Engine del Core (OTP)**
- ✅ **EventStore con persistencia**
- ✅ **Resurrection automática**
- ✅ **Sleep multi-día con hibernación**
- ✅ **Sobrevive restarts del Core**
- ✅ **StateReconstructor**
- ✅ **WorkflowScheduler**

**Ventaja:** Aprovecha TODO el poder de BEAM/OTP desde Python

---

## Comparación Detallada

| Feature | Local (DSLLocalExecutor) | Distribuido (HOY) | Distribuido (IDEAL) |
|---------|-------------------------|-------------------|---------------------|
| **Dónde corre** | Python process | Core + Workers | Core (Engine) + Workers |
| **Requiere Core** | ❌ No | ✅ Sí | ✅ Sí |
| **EventStore** | ❌ | ❌ | ✅ |
| **Engine** | ❌ | ❌ | ✅ |
| **Resurrection** | ❌ | ❌ | ✅ |
| **Sleep multi-día** | ❌ | ❌ | ✅ |
| **Hibernation** | ❌ | ❌ | ✅ |
| **OTP Supervisor** | ❌ | ❌ | ✅ |
| **Sobrevive Core restart** | N/A | ❌ | ✅ |
| **State persistence** | Memoria Python | ETS (volátil) | PostgreSQL ✅ |
| **Workers distribuidos** | ❌ | ✅ | ✅ |
| **Uso** | Dev/testing | Producción básica | Producción enterprise |

---

## El Gap de Implementación

### Lo que falta en `worker_service_server.ex`:

**Línea 369 - ANTES:**
```elixir
def execute_workflow(request, _stream) do
  # ...
  case BlueprintRegistry.get_blueprint(request.workflow_module) do
    {:ok, blueprint} ->
      # ❌ Esto NO usa el Engine
      {:ok, _exec_state} = ExecutionStateManager.create_execution(
        execution_id,
        blueprint,
        inputs
      )

      {:ok, _task_ids} = TaskRouter.queue_initial_tasks(
        execution_id,
        request.workflow_module,
        initial_steps,
        inputs
      )
  end
end
```

**Línea 369 - DESPUÉS (PROPUESTA):**
```elixir
def execute_workflow(request, _stream) do
  inputs = struct_to_map(request.inputs)

  case BlueprintRegistry.get_blueprint(request.workflow_module) do
    {:ok, blueprint} ->
      # ✅ Usar el Engine (aprovecha OTP)
      {:ok, pid} = Execution.Supervisor.start_execution(
        Cerebelum.WorkflowDelegatingWorkflow,
        inputs,
        blueprint: blueprint,
        workflow_module: request.workflow_module,
        execution_mode: :distributed  # Indica que delega a workers
      )

      # Engine maneja todo:
      # - Emite eventos
      # - Delega steps a TaskRouter
      # - Procesa Sleep/Approval
      # - Resurrection automática

      execution_id = Cerebelum.Engine.Data.get_execution_id(pid)
  end

  %ExecutionHandle{
    execution_id: execution_id,
    status: "running",
    started_at: current_timestamp()
  }
end
```

---

## Flujo Completo - Modo Distribuido Ideal

### 1. Cliente ejecuta workflow

```python
# 07_execute_workflow.py
executor = DistributedExecutor(core_url="localhost:9090")
result = await executor.execute(
    workflow="my_workflow",
    input_data={"user_id": 123}
)
```

### 2. gRPC → Core

```
ExecuteRequest {
  workflow_module: "my_workflow",
  inputs: {"user_id": 123}
}
```

### 3. Core inicia Engine

```elixir
# worker_service_server.ex
def execute_workflow(request, _stream) do
  {:ok, pid} = Execution.Supervisor.start_execution(
    WorkflowDelegatingWorkflow,
    inputs,
    blueprint: blueprint
  )
end
```

### 4. Engine ejecuta workflow

```elixir
# WorkflowDelegatingWorkflow
def step1(context) do
  # Delega a TaskRouter
  task_id = TaskRouter.queue_task(context.execution_id, "step1", inputs)

  # Espera resultado del worker
  {:ok, result} = await_worker_result(task_id)

  # Engine emite evento
  EventStore.append(StepCompletedEvent.new(...))

  {:ok, result}
end
```

### 5. Worker ejecuta step

```python
# 07_distributed_server.py - Worker polling
task = await worker.poll_for_task()
result = await execute_step(task)
await worker.submit_result(result)
```

### 6. Engine recibe resultado y continúa

```elixir
# Engine recibe resultado del worker
# Continúa con siguiente step
# O procesa Sleep si el step lo pidió
```

### 7. Sleep multi-día

```python
@step
async def wait_deployment(context, inputs):
    await sleep(timedelta(days=1))  # ← Worker envía SleepRequest
    return {"ok": "deployed"}
```

```elixir
# Engine recibe SleepRequest
def process_sleep_request(duration_ms, data) do
  # Engine emite SleepStartedEvent
  EventStore.append(SleepStartedEvent.new(...))

  # Engine hiberna si duration > 1 hora
  if duration_ms > 3_600_000 do
    WorkflowPause.create(execution_id, resume_at: now + duration_ms)
    {:stop, :normal, data}  # Libera memoria
  else
    {:keep_state, data, [{:state_timeout, duration_ms, :wake_up}]}
  end
end
```

### 8. Core se reinicia

```
Core restart → Resurrector scan → Find paused workflows → Resume Engine
```

### 9. WorkflowScheduler despierta workflow

```elixir
# 24 horas después
WorkflowScheduler.scan()
  → Find resume_at <= now
  → Execution.Supervisor.resume_execution(execution_id)
  → StateReconstructor.reconstruct_from_events()
  → Engine continúa ✅
```

---

## Conclusión

**Tu intención era correcta:**
- Modo Local: desarrollo rápido sin Core
- Modo Distribuido: **aprovecha TODO el poder de BEAM/OTP**

**Pero la implementación del modo distribuido está incompleta:**
- Actualmente usa TaskRouter + ExecutionStateManager (ETS)
- NO usa el Engine
- NO tiene resurrection

**La solución:** Modificar `execute_workflow` para usar `Execution.Supervisor.start_execution()` y aprovechar todo el sistema de Engine que ya tienen implementado.

Esto te daría ventaja competitiva sobre Temporal.io:
- Temporal: Workers ejecutan orquestación (complejo)
- Cerebelum: Engine ejecuta orquestación, Workers ejecutan steps (más simple + OTP power)
