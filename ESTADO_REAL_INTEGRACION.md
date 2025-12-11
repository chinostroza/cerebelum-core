# Estado Real: Python SDK + Cerebelum Core

**Fecha:** 2024-12-11
**Hallazgo:** El Python SDK NO está usando el Engine actualmente

---

## ✅ Lo que SÍ tienen implementado

### 1. Engine System (Elixir Workflows) - COMPLETO

```elixir
defmodule MyWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      step1() |> step2() |> step3()
    end
  end

  def step1(context), do: {:ok, :data}
end

# Ejecución
Cerebelum.execute_workflow(MyWorkflow, inputs)
```

**Capacidades:**
- ✅ Execution.Engine (GenStateMachine)
- ✅ EventStore con persistencia PostgreSQL
- ✅ StateReconstructor - reconstruye estado desde eventos
- ✅ Resurrection completa - workflows sobreviven restarts
- ✅ Sleep multi-día con hibernación
- ✅ Approval workflows
- ✅ WorkflowScheduler - despierta workflows automáticamente
- ✅ Registry - mapea execution_id → PID
- ✅ Supervisor OTP - restart policies

---

### 2. Python SDK (DSL Declarativo) - COMPLETO

```python
from cerebelum import step, workflow

@step
async def fetch_user(context, inputs):
    user_id = inputs["user_id"]
    user = await db.get_user(user_id)
    return {"ok": user}

@step
async def send_email(context, fetch_user):
    user = fetch_user["ok"]
    await email.send(user["email"])
    return {"ok": "sent"}

@workflow
def my_workflow(wf):
    wf.timeline(fetch_user >> send_email)

# Ejecución local
result = await my_workflow.execute({"user_id": 123})
```

**Capacidades:**
- ✅ @step decorator con dependency resolution
- ✅ @workflow decorator con timeline/diverge/branch DSL
- ✅ DSLLocalExecutor - ejecuta localmente en Python
- ✅ Worker class - registra con Core via gRPC
- ✅ Blueprint serialization a protobuf
- ✅ DistributedExecutor - submit workflows a Core
- ✅ Async helpers: poll(), retry(), sleep()

---

### 3. Worker System (Distribución) - COMPLETO

**En Core (Elixir):**
- ✅ BlueprintRegistry - guarda blueprints de workflows
- ✅ TaskRouter - queue tasks, long-polling, sticky routing
- ✅ ExecutionStateManager - tracking de steps completados (ETS)
- ✅ WorkerRegistry - workers activos
- ✅ worker_service_server.ex - gRPC endpoints

**En Python:**
- ✅ Worker polls for tasks
- ✅ Worker ejecuta steps
- ✅ Worker devuelve resultados

---

## ❌ Lo que NO está conectado

### El Gap Crítico

```
Python Worker → gRPC ExecuteRequest
                  ↓
           worker_service_server.ex:execute_workflow() (línea 369)
                  ↓
           BlueprintRegistry.get_blueprint()
                  ↓
           ❌ ExecutionStateManager.create_execution() [ETS only!]
           ❌ TaskRouter.queue_initial_tasks()
                  ↓
           ❌ NO llama a Execution.Supervisor.start_execution()
           ❌ NO usa el Engine
           ❌ NO emite eventos
           ❌ NO hay resurrection
```

### Consecuencias

**Workflows de Python NO tienen:**
- ❌ EventStore (solo ETS en memoria)
- ❌ Resurrection automática
- ❌ Sleep multi-día con hibernación
- ❌ StateReconstructor
- ❌ WorkflowScheduler
- ❌ Sobrevivir restarts del Core

**Si el Core se reinicia:**
- ❌ ExecutionStateManager se pierde (ETS)
- ❌ TaskRouter state se pierde
- ❌ Ejecuciones de Python workflows se pierden

---

## 🎯 Lo que pensabas que tenían

> "mi idea fue crear todo el sistema para funcionar con elixir, y no perder lo de OTP, entonces el python SDK, estaba sobre eso, entonces teniamos todas esas ventajas tmb con python"

**La intención era correcta**, pero la implementación está incompleta:

### Arquitectura Deseada (NO implementada)

```
Python Worker → gRPC ExecuteRequest
                  ↓
           worker_service_server.ex:execute_workflow()
                  ↓
           ✅ Execution.Supervisor.start_execution()  ← FALTA ESTO
                  ↓
           ✅ Execution.Engine (GenStateMachine)
                  ↓
           Para cada step:
             - Engine emite StepStartedEvent
             - Engine delega a TaskRouter
             - Worker ejecuta step
             - Worker devuelve resultado
             - Engine emite StepCompletedEvent
             - Engine continúa
                  ↓
           Sleep/Approval:
             - Worker envía SleepRequest
             - Engine procesa {:sleep, [...], data}
             - Engine emite SleepStartedEvent
             - Hibernation funciona
             - Resurrection funciona ✅
```

---

## 📊 Comparación Real

| Feature | Elixir Workflows | Python SDK (HOY) | Python SDK (IDEAL) |
|---------|-----------------|------------------|-------------------|
| Engine execution | ✅ | ❌ | ✅ |
| EventStore | ✅ | ❌ | ✅ |
| Resurrection | ✅ | ❌ | ✅ |
| Sleep multi-día | ✅ | ❌ | ✅ |
| Hibernation | ✅ | ❌ | ✅ |
| OTP Supervisor | ✅ | ❌ | ✅ |
| StateReconstructor | ✅ | ❌ | ✅ |
| WorkflowScheduler | ✅ | ❌ | ✅ |
| Distributed workers | N/A | ✅ | ✅ |
| Python DSL | N/A | ✅ | ✅ |

---

## 🔧 Qué falta implementar

### 1. Modificar `worker_service_server.ex:execute_workflow`

**Antes (líneas 369-412):**
```elixir
def execute_workflow(request, _stream) do
  # ...
  case BlueprintRegistry.get_blueprint(request.workflow_module) do
    {:ok, blueprint} ->
      # ❌ Esto NO usa el Engine
      {:ok, _exec_state} = ExecutionStateManager.create_execution(...)
      {:ok, _task_ids} = TaskRouter.queue_initial_tasks(...)
  end
end
```

**Después (PROPUESTA):**
```elixir
def execute_workflow(request, _stream) do
  inputs = struct_to_map(request.inputs)

  case BlueprintRegistry.get_blueprint(request.workflow_module) do
    {:ok, blueprint} ->
      # ✅ Usar el Engine
      {:ok, pid} = Execution.Supervisor.start_execution(
        Cerebelum.WorkflowDelegatingWorkflow,
        inputs,
        blueprint: blueprint,
        workflow_module: request.workflow_module
      )

      # El Engine maneja todo: eventos, sleep, resurrection
  end
end
```

### 2. Crear `Cerebelum.WorkflowDelegatingWorkflow`

```elixir
defmodule Cerebelum.WorkflowDelegatingWorkflow do
  use Cerebelum.Workflow

  @doc """
  Workflow dinámico que carga blueprint de Python y delega steps a workers.
  """

  workflow do
    # Timeline se carga dinámicamente del blueprint
  end

  # Cada step delega al Worker via TaskRouter
  def execute_step(context, step_name, inputs) do
    task = %{
      workflow_module: context.workflow_module,
      step_name: step_name,
      inputs: inputs
    }

    {:ok, task_id} = TaskRouter.queue_task(context.execution_id, task)

    # Esperar resultado del worker
    result = await_task_completion(task_id, timeout: 300_000)

    # Procesar respuesta del worker
    case result do
      {:sleep, duration_ms, data} ->
        # Worker pidió sleep - Engine lo maneja
        {:sleep, [milliseconds: duration_ms], data}

      {:approval, approval_data} ->
        # Worker pidió approval - Engine lo maneja
        {:approval, approval_data}

      {:ok, data} ->
        {:ok, data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_task_completion(task_id, opts) do
    # Implementar blocking wait para resultado del worker
    # Opciones:
    # 1. GenServer.call con timeout
    # 2. Process mailbox con receive
    # 3. Registry + monitor
  end
end
```

### 3. Extender `TaskResult` protobuf

```protobuf
message TaskResult {
  string task_id = 1;
  string execution_id = 2;
  string worker_id = 3;

  TaskStatus status = 4;
  google.protobuf.Struct result = 5;
  ErrorInfo error = 6;

  // ✅ NUEVO: Sleep/Approval support
  SleepRequest sleep_request = 7;
  ApprovalRequest approval_request = 8;
}

message SleepRequest {
  int64 duration_ms = 1;
  google.protobuf.Struct data = 2;
}

message ApprovalRequest {
  string approval_type = 1;
  google.protobuf.Struct data = 2;
  int64 timeout_ms = 3;
}

enum TaskStatus {
  TASK_STATUS_UNSPECIFIED = 0;
  SUCCESS = 1;
  FAILED = 2;
  TIMEOUT = 3;
  CANCELLED = 4;
  SLEEP = 5;      // ✅ NUEVO
  APPROVAL = 6;   // ✅ NUEVO
}
```

### 4. Actualizar Python SDK `sleep()`

```python
async def sleep(duration: int) -> None:
    """Sleep workflow-aware."""
    context = get_current_context()

    if context.distributed:
        # ✅ Return marker para que worker envíe SleepRequest
        return {"_sleep": True, "duration_ms": duration}
    else:
        # Local mode
        await asyncio.sleep(duration / 1000)
```

### 5. Actualizar `Worker._execute_task`

```python
async def _execute_task(self, task) -> TaskResult:
    # Ejecutar step
    output = await step_function(ctx, **inputs)

    # ✅ NUEVO: Detectar sleep marker
    if isinstance(output, dict) and output.get("_sleep"):
        return TaskResult(
            task_id=task.task_id,
            execution_id=task.execution_id,
            worker_id=self.worker_id,
            status=TaskStatus.SLEEP,
            sleep_request=SleepRequest(
                duration_ms=output["duration_ms"],
                data=struct_from_dict(output.get("data", {}))
            )
        )

    # ✅ NUEVO: Detectar approval marker
    if isinstance(output, dict) and output.get("_approval"):
        return TaskResult(
            ...
            status=TaskStatus.APPROVAL,
            approval_request=ApprovalRequest(...)
        )

    # Normal success
    return TaskResult(
        ...
        status=TaskStatus.SUCCESS,
        result=struct_from_dict(output)
    )
```

### 6. Actualizar `worker_service_server.ex:submit_result`

```elixir
def submit_result(result, _stream) do
  case result.status do
    :SLEEP ->
      # Notificar al Engine que el step está sleeping
      # Engine procesa y entra en :sleeping state
      notify_engine_sleep(result)

    :APPROVAL ->
      # Notificar al Engine que espera approval
      notify_engine_approval(result)

    :SUCCESS ->
      # Normal flow
      notify_engine_success(result)
  end
end
```

---

## 🎯 Resultado Final

### Después de implementar esto:

```python
# Python Worker code
@step
async def wait_for_deployment(context, inputs):
    # ✅ Este sleep funcionará con resurrection
    await sleep(timedelta(days=1))
    return {"ok": "deployed"}

@workflow
def my_workflow(wf):
    wf.timeline(deploy >> wait_for_deployment >> verify)

# Execute
await my_workflow.execute(inputs, distributed=True)
```

**Lo que pasará:**
1. Python worker ejecuta `deploy` step
2. Python worker ejecuta `wait_for_deployment`
3. Worker detecta `sleep(1 day)` y envía `SleepRequest`
4. Core/Engine recibe y procesa como `{:sleep, [milliseconds: 86400000], data}`
5. Engine emite `SleepStartedEvent`
6. Engine puede hibernar el proceso (libera memoria)
7. **Core se reinicia** → ✅ Workflow sobrevive
8. WorkflowScheduler despierta el workflow después de 1 día
9. Engine continúa con `verify` step
10. Worker ejecuta `verify`
11. Workflow completa ✅

---

## 📋 Tasks de Implementación

1. [ ] Crear `WorkflowDelegatingWorkflow` module
2. [ ] Implementar `await_task_completion` con blocking wait
3. [ ] Modificar `execute_workflow` para usar `Execution.Supervisor`
4. [ ] Extender protobuf con `SleepRequest`/`ApprovalRequest`
5. [ ] Regenerar protobuf: `mix protobuf.generate`
6. [ ] Actualizar Python `sleep()` helper
7. [ ] Actualizar `Worker._execute_task` para detectar markers
8. [ ] Actualizar `submit_result` para notificar Engine
9. [ ] Testing end-to-end: Python → Sleep → Kill Core → Resurrect → Complete
10. [ ] Documentación

---

## 💡 Ventajas vs Temporal.io

Una vez implementado, tendrán:

| Feature | Temporal.io | Cerebelum (después de implementar) |
|---------|-------------|-------------------------------------|
| Resurrection | ✅ | ✅ |
| Sleep multi-día | ✅ | ✅ |
| Event sourcing | ✅ | ✅ |
| OTP/BEAM power | ❌ | ✅ (único!) |
| Python DSL | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ (más simple) |
| Replay determinístico | ✅ Complejo | ❌ Pero no lo necesitan! |
| Distributed workers | ✅ | ✅ |

**Ventaja competitiva:** NO necesitan replay determinístico porque el Engine mantiene el estado. Más simple que Temporal pero con los mismos beneficios de resurrection.
