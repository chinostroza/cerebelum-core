# Respuestas a Preguntas del Equipo ZEA Sport

Respuestas detalladas a las 6 preguntas técnicas planteadas.

---

## 1️⃣ ¿Cómo integramos Cerebelum con nuestra aplicación FastAPI existente?

### ¿Se ejecuta como servicio separado o embebido?

**Respuesta: Servicio separado (recomendado)**

Cerebelum Core corre como un **servicio independiente** que se comunica con tu aplicación FastAPI vía gRPC.

### Arquitectura de Comunicación

```
FastAPI App (Puerto 8000)
    │
    │ 1. executor.execute(workflow, inputs)
    │    ↓ gRPC
    │
Cerebelum Core (Puerto 9090)
    │
    │ 2. Asigna tasks a workers
    │    ↓ gRPC
    │
Python Workers (N procesos)
    │
    │ 3. Ejecutan steps
    │    └─→ Importan tus repositorios
    │        └─→ Acceden a tu PostgreSQL
```

### Integración Paso a Paso

**1. Instalar SDK en tu proyecto:**

```bash
pip install cerebelum-sdk  # O desde el repo: pip install -e /path/to/python-sdk
```

**2. Crear workflows que usen tu código existente:**

```python
# app/workflows/athlete_onboarding.py
from cerebelum import WorkflowBuilder
from app.domain.repositories.user_repository import UserRepository  # ← Tu código

user_repo = UserRepository()

async def validate_registration(ctx, inputs):
    # Usa tu repository existente
    user = await user_repo.get_by_id(inputs['user_id'])
    return {'user': user}

def build_workflow():
    return WorkflowBuilder("AthleteOnboarding") \
        .timeline(["validate_registration"]) \
        .step("validate_registration", validate_registration) \
        .build()
```

**3. Ejecutar workflows desde tus endpoints:**

```python
# app/api/endpoints/auth.py
from fastapi import APIRouter
from cerebelum import DistributedExecutor
from app.workflows.athlete_onboarding import build_workflow

router = APIRouter()

@router.post("/register")
async def register(data: RegisterData):
    # 1. Crear usuario (tu lógica actual)
    user = await create_user(data)

    # 2. Ejecutar workflow
    executor = DistributedExecutor(core_url="localhost:9090")
    result = await executor.execute(build_workflow(), {'user_id': user.id})

    return {'user_id': user.id, 'execution_id': result.execution_id}
```

**4. Levantar servicios:**

```bash
# Terminal 1: Cerebelum Core
docker-compose up cerebelum-core

# Terminal 2: Workers
python -m app.workers.main

# Terminal 3: FastAPI (tu app existente)
uvicorn app.main:app --reload
```

### ¿Ventajas de Servicio Separado?

✅ **Escalabilidad**: Core y Workers escalan independientemente
✅ **Resiliencia**: Si FastAPI se reinicia, workflows continúan
✅ **Multi-lenguaje**: Podrían tener workers en Python, Kotlin, etc.
✅ **Zero downtime**: Deploy de FastAPI no afecta workflows activos

### ¿Desventajas?

⚠️ Complejidad: Un servicio adicional para monitorear
⚠️ Latencia: ~5-10ms de overhead por comunicación gRPC (aceptable)

---

## 2️⃣ ¿Cómo manejamos workflows que esperan acción humana con timeout?

### Respuesta: `ctx.request_approval()` con timeout

Cerebelum tiene soporte nativo para **approvals con timeout automático**.

### Ejemplo: Evaluación de Atleta (48 horas)

```python
async def request_athlete_feedback(ctx, inputs):
    """
    Solicita feedback al atleta.
    Si no responde en 48 horas → auto-completa sin feedback.
    """
    booking_id = inputs['booking_id']

    # 1. Enviar email/notificación
    await send_feedback_email(booking_id)

    # 2. Esperar hasta 48 horas por respuesta
    approval_result = await ctx.request_approval(
        approval_type="athlete_session_feedback",
        approval_data={
            "booking_id": booking_id,
            "questions": ["¿Cómo calificarías la sesión? (1-5)"]
        },
        timeout_ms=48 * 60 * 60 * 1000  # 48 horas = 172,800,000 ms
    )

    # 3. Procesar resultado
    if approval_result.approved:
        # Atleta respondió a tiempo
        feedback = approval_result.data
        await save_feedback(booking_id, feedback)
        return {'feedback_received': True, 'rating': feedback['rating']}
    else:
        # TIMEOUT - No respondió en 48 horas
        await save_no_response(booking_id)
        return {'feedback_received': False, 'reason': 'timeout'}
```

### ¿Cómo funciona internamente?

1. **Workflow entra en estado `WAITING_FOR_APPROVAL`**
2. **Proceso del workflow puede hibernar** (libera memoria)
3. **Scheduler de Cerebelum revisa cada 30 segundos**:
   - ¿Ya se recibió aprobación? → Continúa workflow
   - ¿Expiró timeout? → Marca como rechazado y continúa
4. **Workflow continúa automáticamente** en ambos casos

### Endpoint para Recibir Aprobación

```python
# app/api/endpoints/feedback.py
from fastapi import APIRouter
from cerebelum import DistributedExecutor

router = APIRouter()

@router.post("/feedback/submit")
async def submit_feedback(data: FeedbackData):
    """
    Endpoint que atleta/coach llaman para enviar feedback.
    """
    executor = DistributedExecutor(core_url="localhost:9090")

    # Aprobar el workflow
    await executor.approve_execution(
        execution_id=data.execution_id,
        approval_type="athlete_session_feedback",
        approval_data={
            'rating': data.rating,
            'comments': data.comments
        }
    )

    return {'message': 'Gracias por tu feedback!'}
```

### Timeouts Configurables

```python
# Diferentes timeouts según el caso:

# Perfil de atleta: 7 días
timeout_ms=7 * 24 * 60 * 60 * 1000

# Feedback de sesión: 48 horas
timeout_ms=48 * 60 * 60 * 1000

# Aprobación de admin: 24 horas
timeout_ms=24 * 60 * 60 * 1000

# Confirmación inmediata: 5 minutos
timeout_ms=5 * 60 * 1000
```

### ¿Qué pasa si el sistema se reinicia durante la espera?

✅ **El workflow sobrevive y continúa esperando**
✅ Event sourcing guarda el estado completo
✅ Al reiniciar, Cerebelum automáticamente resucita workflows pausados
✅ El countdown del timeout continúa desde donde quedó

---

## 3️⃣ ¿Cómo accedemos a nuestra base de datos PostgreSQL desde los workflows?

### Respuesta: Importar repositorios existentes directamente

Los **workers ejecutan código Python normal** y pueden importar cualquier módulo de tu aplicación.

### Opción 1: Importar Repositorios (Recomendado)

```python
# app/workflows/booking_request.py
from cerebelum import WorkflowBuilder
from app.domain.repositories.booking_repository import BookingRepository
from app.domain.repositories.user_repository import UserRepository
from app.domain.repositories.slot_repository import SlotRepository

# Instanciar repositorios (misma instancia que usa FastAPI)
booking_repo = BookingRepository()
user_repo = UserRepository()
slot_repo = SlotRepository()

async def validate_slot_availability(ctx, inputs):
    coach_id = inputs['coach_id']
    slot_datetime = inputs['slot_datetime']

    # Usar tu repository existente
    is_available = await slot_repo.is_available(coach_id, slot_datetime)

    if not is_available:
        raise Exception(f"Slot {slot_datetime} no disponible")

    return {'slot_available': True}

async def create_booking_record(ctx, inputs):
    # Usar tu repository para crear booking
    booking = await booking_repo.create({
        'athlete_id': inputs['athlete_id'],
        'coach_id': inputs['coach_id'],
        'scheduled_at': inputs['slot_datetime'],
        'status': 'PENDING'
    })

    return {'booking_id': booking.id}
```

### Opción 2: Usar Casos de Uso

```python
from app.domain.use_cases.create_booking import CreateBookingUseCase

async def create_booking_step(ctx, inputs):
    use_case = CreateBookingUseCase()

    booking = await use_case.execute(
        athlete_id=inputs['athlete_id'],
        coach_id=inputs['coach_id'],
        slot_datetime=inputs['slot_datetime']
    )

    return {'booking_id': booking.id}
```

### Opción 3: SQLAlchemy Directo

```python
from app.database import get_db_session
from app.models import Booking

async def create_booking_step(ctx, inputs):
    async with get_db_session() as session:
        booking = Booking(
            athlete_id=inputs['athlete_id'],
            coach_id=inputs['coach_id'],
            scheduled_at=inputs['slot_datetime']
        )
        session.add(booking)
        await session.commit()
        await session.refresh(booking)

        return {'booking_id': booking.id}
```

### Configuración de Database en Workers

```python
# app/workers/main.py
import asyncio
import os
from cerebelum import Worker

# Configurar conexión a DB (mismo config que FastAPI)
from app.database import init_db

async def main():
    # 1. Inicializar DB
    await init_db(os.getenv('DATABASE_URL'))

    # 2. Iniciar worker
    worker = Worker(
        core_url=os.getenv('CEREBELUM_CORE_URL', 'localhost:9090'),
        worker_id=os.getenv('CEREBELUM_WORKER_ID', 'worker-1')
    )

    await worker.run()

if __name__ == "__main__":
    asyncio.run(main())
```

### Variables de Entorno

```bash
# .env
DATABASE_URL=postgresql://user:pass@localhost:5432/zea_sport_db
CEREBELUM_CORE_URL=localhost:9090
```

### ¿Cómo se comparte la conexión?

✅ **Workers y FastAPI usan el MISMO connection pool**
✅ Mismo `DATABASE_URL` en ambos
✅ Mismo código de conexión (SQLAlchemy, asyncpg, etc.)
✅ Respetan transacciones y locking

### Ejemplo Completo con Transacciones

```python
from app.database import get_db_session
from sqlalchemy.exc import IntegrityError

async def reserve_slot_atomic(ctx, inputs):
    """
    Reserva un slot de forma atómica (con transaction).
    """
    coach_id = inputs['coach_id']
    slot_datetime = inputs['slot_datetime']
    booking_id = inputs['booking_id']

    async with get_db_session() as session:
        async with session.begin():  # Transaction
            # 1. Check availability con lock
            slot = await session.execute(
                "SELECT * FROM slots WHERE coach_id = :coach_id AND datetime = :dt FOR UPDATE",
                {'coach_id': coach_id, 'dt': slot_datetime}
            )

            if slot.available == False:
                raise Exception("Slot ya reservado por otro atleta")

            # 2. Marcar como reservado
            await session.execute(
                "UPDATE slots SET available = false, booking_id = :booking_id WHERE id = :slot_id",
                {'booking_id': booking_id, 'slot_id': slot.id}
            )

            # Transaction auto-commit

    return {'slot_reserved': True}
```

---

## 4️⃣ ¿Cómo configuramos el entorno de desarrollo local?

### Respuesta: Docker Compose (Recomendado)

### 1. Crear `docker-compose.yml`

Ver archivo completo en: `zea_sport_examples/docker-compose.yml`

Incluye:
- Tu FastAPI app
- Tu PostgreSQL existente
- Cerebelum Core (nuevo)
- PostgreSQL para Cerebelum (nuevo)
- Python Workers (nuevo)

### 2. Levantar todo con un comando

```bash
docker-compose up
```

Esto levanta:
- ✅ FastAPI en `localhost:8000`
- ✅ Cerebelum Core en `localhost:9090`
- ✅ PostgreSQL (tu DB) en `localhost:5432`
- ✅ PostgreSQL (Cerebelum) en `localhost:5433`
- ✅ 2 Workers Python

### 3. Desarrollo sin Docker

Si prefieres desarrollo local:

```bash
# Terminal 1: PostgreSQL (si no usas Docker)
brew install postgresql@15
brew services start postgresql@15
createdb zea_sport_db
createdb cerebelum_db

# Terminal 2: Cerebelum Core
cd /path/to/cerebelum-core
mix deps.get
mix ecto.create
mix ecto.migrate
mix run --no-halt

# Terminal 3: Worker
cd /path/to/your-fastapi-app
source venv/bin/activate
python -m app.workers.main

# Terminal 4: FastAPI
uvicorn app.main:app --reload --port 8000
```

### 4. Variables de Entorno

```bash
# .env.local
DATABASE_URL=postgresql://localhost:5432/zea_sport_db
CEREBELUM_CORE_URL=localhost:9090
CEREBELUM_WORKER_ID=local-worker-1

# .env.docker
DATABASE_URL=postgresql://postgres:5432/zea_sport_db
CEREBELUM_CORE_URL=cerebelum-core:9090
CEREBELUM_WORKER_ID=docker-worker-1
```

### 5. Scripts de Desarrollo

```bash
# scripts/dev.sh
#!/bin/bash
set -e

echo "🚀 Starting ZEA Sport Development Environment"

# Start databases
docker-compose up -d postgres postgres-cerebelum

# Wait for DBs
sleep 5

# Start Cerebelum Core
docker-compose up -d cerebelum-core

# Wait for Core
sleep 3

# Start Worker
python -m app.workers.main &
WORKER_PID=$!

# Start FastAPI
uvicorn app.main:app --reload --port 8000 &
FASTAPI_PID=$!

echo "✅ Environment ready!"
echo "   FastAPI: http://localhost:8000"
echo "   Cerebelum Core: localhost:9090"
echo ""
echo "Press Ctrl+C to stop all services"

# Wait for Ctrl+C
trap "kill $WORKER_PID $FASTAPI_PID; docker-compose down; exit" INT
wait
```

### 6. Verificar que Todo Funciona

```bash
# Test FastAPI
curl http://localhost:8000/health

# Test Cerebelum Core
cd /path/to/cerebelum-core/examples/python-sdk
./cerebelum_cli.py list

# Test Worker
# Debería mostrar logs tipo:
# "Worker started: zea-sport-worker-1"
# "Connected to Core: localhost:9090"
```

---

## 5️⃣ ¿Event sourcing es suficiente para nuestros analytics?

### Respuesta: Depende del tipo de analytics

### Event Sourcing te da:

✅ **Auditoría completa**:
- Quién hizo qué y cuándo
- Historial completo de cada workflow
- Trazabilidad end-to-end

✅ **Analytics de workflows**:
- ¿Cuántos onboardings completados?
- ¿Cuántos abandonan en qué paso?
- Tiempo promedio por workflow
- Tasa de éxito/falla

✅ **Debugging**:
- Reproducir cualquier ejecución
- Ver estado en cualquier punto del tiempo
- Identificar cuellos de botella

### Para Analytics de Negocio: Usar tu DB

Para analytics de negocio (reportes, dashboards), usa tu PostgreSQL normal:

```python
# Analytics desde tu DB (NO event sourcing)

# 1. Ingresos mensuales
SELECT SUM(price) FROM bookings WHERE status = 'COMPLETED' AND MONTH(created_at) = 11

# 2. Coaches más populares
SELECT coach_id, COUNT(*) as bookings FROM bookings GROUP BY coach_id ORDER BY bookings DESC

# 3. Horarios más demandados
SELECT HOUR(scheduled_at) as hour, COUNT(*) FROM bookings GROUP BY hour

# 4. Tasa de no-show
SELECT
  COUNT(CASE WHEN status = 'NO_SHOW' THEN 1 END) / COUNT(*) as no_show_rate
FROM bookings
```

### Combinar Ambos

```python
async def get_onboarding_analytics():
    """
    Analytics combinando event sourcing + tu DB.
    """
    from cerebelum import ExecutionClient

    # 1. Workflows de onboarding desde Cerebelum
    client = ExecutionClient(core_url="localhost:9090")
    executions, total, _ = await client.list_executions(
        workflow_name="zea_sport.AthleteOnboarding",
        limit=1000
    )

    completed = sum(1 for e in executions if e.status == ExecutionState.COMPLETED)
    failed = sum(1 for e in executions if e.status == ExecutionState.FAILED)
    avg_duration = sum(e.elapsed_seconds for e in executions) / len(executions)

    # 2. Atletas activos desde tu DB
    from app.repositories.athlete_repository import AthleteRepository
    athlete_repo = AthleteRepository()

    active_athletes = await athlete_repo.count_active()

    return {
        'onboarding': {
            'total': total,
            'completed': completed,
            'failed': failed,
            'success_rate': completed / total,
            'avg_duration_seconds': avg_duration
        },
        'athletes': {
            'active': active_athletes
        }
    }
```

### Recomendación

🎯 **Usa Event Sourcing para**:
- Auditoría de workflows
- Debugging y troubleshooting
- Analytics de procesos (tiempo, pasos, fallas)

🎯 **Usa tu PostgreSQL para**:
- Reportes de negocio (ingresos, conversión, etc.)
- Dashboards de métricas
- Analytics de usuarios/bookings

---

## 6️⃣ ¿Cuál es el mejor approach para workflows mixtos (sync + async)?

### Respuesta: Ejecutar todos async, pero workflows rápidos responden inmediato

### Approach Recomendado

**TODOS los workflows se ejecutan asíncronamente**, pero:
- Workflows rápidos (<1s) → `await executor.execute()` retorna resultado
- Workflows largos (días) → Retornas `execution_id` y usuario puede checar después

### Ejemplo 1: Workflow Síncrono (Booking Request)

```python
@app.post("/api/bookings")
async def create_booking(data: BookingRequest):
    """
    Workflow rápido (<1 segundo).
    Usuario espera respuesta inmediata.
    """
    executor = DistributedExecutor(core_url="localhost:9090")

    # await espera a que el workflow COMPLETE (rápido)
    result = await executor.execute(
        build_booking_request_workflow(),
        {
            'athlete_id': current_user.id,
            'coach_id': data.coach_id,
            'slot_datetime': data.slot_datetime
        }
    )

    # Workflow ya terminó, retornar resultado
    return {
        'booking_id': result.output['booking_id'],
        'status': 'CONFIRMED',
        'execution_id': result.execution_id
    }
```

### Ejemplo 2: Workflow Asíncrono (Session Completion)

```python
@app.post("/api/bookings/{booking_id}/complete")
async def complete_session(booking_id: str, data: CompleteSessionData):
    """
    Workflow largo (puede durar días esperando evaluaciones).
    NO esperamos a que termine.
    """
    executor = DistributedExecutor(core_url="localhost:9090")

    # await solo espera a que el workflow INICIE
    result = await executor.execute(
        build_session_completion_workflow(),
        {
            'booking_id': booking_id,
            'actual_start_time': data.actual_start_time,
            'actual_end_time': data.actual_end_time
        }
    )

    # Workflow queda activo (esperando evaluaciones)
    # Retornar inmediatamente
    return {
        'message': 'Session completed. Feedback requests sent.',
        'execution_id': result.execution_id,
        'billable_minutes': result.output['actual_duration_minutes'],
        'status_url': f'/api/executions/{result.execution_id}/status'
    }
```

### Endpoint para Consultar Estado

```python
@app.get("/api/executions/{execution_id}/status")
async def get_execution_status(execution_id: str):
    """
    Endpoint para que UI pueda checar progreso de workflows largos.
    """
    from cerebelum import ExecutionClient

    client = ExecutionClient(core_url="localhost:9090")
    status = await client.get_execution_status(execution_id)

    return {
        'execution_id': execution_id,
        'status': status.status.value,
        'progress': status.progress_percentage,
        'current_step': status.current_step_name,
        'completed_steps': len(status.completed_steps),
        'total_steps': status.total_steps
    }
```

### Pattern: Fire-and-Forget con Callbacks

```python
@app.post("/api/bookings/{booking_id}/complete")
async def complete_session(booking_id: str, data: CompleteSessionData):
    """
    Pattern fire-and-forget con webhook callback.
    """
    executor = DistributedExecutor(core_url="localhost:9090")

    # Incluir webhook URL en inputs
    result = await executor.execute(
        build_session_completion_workflow(),
        {
            'booking_id': booking_id,
            'webhook_url': f'https://api.zeasport.com/webhooks/session-completed',
            'actual_start_time': data.actual_start_time
        }
    )

    return {'execution_id': result.execution_id, 'status': 'processing'}

# Webhook que recibe notificación cuando workflow termina
@app.post("/webhooks/session-completed")
async def session_completed_webhook(data: WebhookData):
    execution_id = data.execution_id
    booking_id = data.booking_id

    # Actualizar UI, enviar notificación, etc.
    await notify_user(booking_id, "Tu sesión ha sido finalizada")
```

### Frontend: Polling vs WebSockets

**Opción A: Polling** (Más simple)

```javascript
// Frontend: Consultar cada 5 segundos
async function monitorWorkflow(executionId) {
  const interval = setInterval(async () => {
    const response = await fetch(`/api/executions/${executionId}/status`);
    const status = await response.json();

    if (status.status === 'COMPLETED' || status.status === 'FAILED') {
      clearInterval(interval);
      showNotification(status);
    } else {
      updateProgressBar(status.progress);
    }
  }, 5000);
}
```

**Opción B: WebSockets** (Más eficiente)

```python
# FastAPI WebSocket endpoint
from fastapi import WebSocket

@app.websocket("/ws/executions/{execution_id}")
async def execution_updates(websocket: WebSocket, execution_id: str):
    await websocket.accept()

    client = ExecutionClient(core_url="localhost:9090")

    while True:
        status = await client.get_execution_status(execution_id)

        await websocket.send_json({
            'status': status.status.value,
            'progress': status.progress_percentage
        })

        if status.status in [ExecutionState.COMPLETED, ExecutionState.FAILED]:
            break

        await asyncio.sleep(2)

    await websocket.close()
```

### Resumen

| Caso de Uso | Approach | Retorno |
|-------------|----------|---------|
| Booking Request | Sync (esperar) | Booking confirmado |
| Onboarding | Async (fire-forget) | execution_id + status URL |
| Session Completion | Async (fire-forget) | execution_id + webhook |
| Payment Report | Sync (esperar) | CSV file URL |

---

## 📚 Recursos Adicionales

- Ver ejemplos completos en: `zea_sport_examples/`
- Docker Compose: `zea_sport_examples/docker-compose.yml`
- Worker: `zea_sport_examples/worker_main.py`
- Quick Start: `zea_sport_examples/QUICK_START.md`

---

¿Más preguntas? Revisar `README.md` o contactar al equipo de Cerebelum! 🚀
