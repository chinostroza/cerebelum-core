# ZEA Sport Platform - Integración con Cerebelum

Guía completa de integración de Cerebelum Workflows con tu aplicación FastAPI existente.

---

## 📋 Tabla de Contenidos

1. [Arquitectura](#arquitectura)
2. [Setup Inicial](#setup-inicial)
3. [Integración con FastAPI](#integración-con-fastapi)
4. [Workflows Implementados](#workflows-implementados)
5. [Acceso a tu Base de Datos](#acceso-a-tu-base-de-datos)
6. [Docker Compose](#docker-compose)
7. [Desarrollo Local](#desarrollo-local)
8. [Monitoreo y Debugging](#monitoreo-y-debugging)
9. [Preguntas Frecuentes](#preguntas-frecuentes)

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                 Tu Aplicación FastAPI (Puerto 8000)         │
│                                                             │
│  - REST endpoints                                           │
│  - Clean Architecture (Use Cases + Repositories)            │
│  - PostgreSQL (tu DB existente)                            │
│                                                             │
│  from cerebelum import DistributedExecutor                  │
│  executor = DistributedExecutor("localhost:9090")           │
│  await executor.execute(workflow, inputs)                   │
│                                                             │
└───────────────────────┬─────────────────────────────────────┘
                        │ gRPC (Python SDK)
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│          Cerebelum Core (Puerto 9090)                       │
│                                                             │
│  - Workflow Orchestration (Elixir/OTP)                      │
│  - Event Store (PostgreSQL separado)                        │
│  - State Management + Resurrection                          │
│  - gRPC Server                                              │
│                                                             │
└───────────────────────┬─────────────────────────────────────┘
                        │ gRPC (Task Assignment)
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              Python Workers (Tu Lógica de Negocio)          │
│                                                             │
│  from cerebelum import Worker                               │
│  worker = Worker(core_url="localhost:9090")                 │
│  await worker.run()                                         │
│                                                             │
│  - Ejecutan steps de workflows                              │
│  - Importan tus repositorios existentes                     │
│  - Acceden a tu PostgreSQL                                  │
│  - Usan tus casos de uso                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Puntos Clave:**
- ✅ **FastAPI sigue siendo tu aplicación principal** (REST API, UI, etc.)
- ✅ **Cerebelum Core corre como servicio separado** (orquestación de workflows)
- ✅ **Workers son procesos Python** que importan tu código existente
- ✅ **2 bases de datos PostgreSQL separadas**:
  - Tu DB existente (usuarios, bookings, etc.)
  - Cerebelum DB (solo event sourcing, no afecta tu schema)

---

## 🚀 Setup Inicial

### 1. Instalar Dependencias

```bash
# En tu proyecto FastAPI
pip install cerebelum-sdk  # TODO: publicar en PyPI

# O desde el repo:
cd /path/to/cerebelum-core/examples/python-sdk
pip install -e .
```

### 2. Configuración de Entorno

Crear `.env` en tu proyecto FastAPI:

```bash
# Tu DB existente (sin cambios)
DATABASE_URL=postgresql://user:pass@localhost:5432/zea_sport_db

# Cerebelum Core
CEREBELUM_CORE_URL=localhost:9090

# Workers
CEREBELUM_WORKER_ID=zea-sport-worker-${HOSTNAME:-local}
```

### 3. Estructura de Archivos Recomendada

```
your-fastapi-app/
├── app/
│   ├── api/
│   │   └── endpoints/
│   │       ├── auth.py
│   │       ├── bookings.py
│   │       └── admin.py
│   ├── domain/
│   │   ├── use_cases/
│   │   └── repositories/
│   ├── workflows/              # ← NUEVO
│   │   ├── __init__.py
│   │   ├── athlete_onboarding.py
│   │   ├── booking_request.py
│   │   ├── session_completion.py
│   │   └── payment_report.py
│   └── workers/                # ← NUEVO
│       ├── __init__.py
│       └── main.py             # Worker principal
├── docker-compose.yml
├── .env
└── requirements.txt
```

---

## 🔌 Integración con FastAPI

### Paso 1: Definir Workflows

En `app/workflows/athlete_onboarding.py`:

```python
from cerebelum import WorkflowBuilder
from app.domain.repositories.user_repository import UserRepository
from app.domain.repositories.athlete_repository import AthleteRepository

# Importar tus repositorios existentes
user_repo = UserRepository()
athlete_repo = AthleteRepository()


async def validate_registration(ctx, inputs):
    """Step que usa tu repository existente."""
    user_id = inputs['user_id']

    # Usar tu código existente
    user = await user_repo.get_by_id(user_id)

    if not user:
        raise Exception(f"User {user_id} not found")

    return {
        'user_id': user.id,
        'email': user.email,
        'registration_valid': True
    }


async def request_profile_completion(ctx, inputs):
    """Espera hasta 7 días que el atleta complete el perfil."""
    user_id = inputs['user_id']

    approval_result = await ctx.request_approval(
        approval_type="athlete_profile_completion",
        approval_data={"user_id": user_id},
        timeout_ms=7 * 24 * 60 * 60 * 1000  # 7 días
    )

    if approval_result.approved:
        return approval_result.data
    else:
        raise Exception("Profile not completed in time")


async def enable_booking_capability(ctx, inputs):
    """Habilita al atleta para hacer bookings."""
    user_id = ctx.execution_id.split('-')[0]

    # Usar tu repository
    await athlete_repo.update(user_id, {
        'can_book': True,
        'profile_completed_at': datetime.utcnow()
    })

    return {'can_book': True}


def build_athlete_onboarding_workflow():
    return (
        WorkflowBuilder("zea_sport.AthleteOnboarding")
        .timeline([
            "validate_registration",
            "request_profile_completion",
            "enable_booking_capability"
        ])
        .step("validate_registration", validate_registration)
        .step("request_profile_completion", request_profile_completion)
        .step("enable_booking_capability", enable_booking_capability)
        .build()
    )
```

### Paso 2: Ejecutar desde Endpoints

En `app/api/endpoints/auth.py`:

```python
from fastapi import APIRouter, Depends
from cerebelum import DistributedExecutor
from app.workflows.athlete_onboarding import build_athlete_onboarding_workflow
from app.domain.use_cases.register_user import RegisterUserUseCase
import os

router = APIRouter()


@router.post("/register")
async def register_user(data: RegisterData):
    """
    Endpoint de registro con workflow de onboarding.
    """
    # 1. Crear usuario usando tu caso de uso existente
    use_case = RegisterUserUseCase()
    user = await use_case.execute(data.email, data.password)

    # 2. Ejecutar workflow de onboarding
    executor = DistributedExecutor(
        core_url=os.getenv('CEREBELUM_CORE_URL', 'localhost:9090')
    )

    result = await executor.execute(
        build_athlete_onboarding_workflow(),
        {
            'user_id': user.id,
            'email': user.email
        }
    )

    # 3. Retornar respuesta inmediata
    return {
        'user_id': user.id,
        'onboarding_execution_id': result.execution_id,
        'message': 'Registration successful. Please complete your profile.'
    }
```

En `app/api/endpoints/bookings.py`:

```python
from fastapi import APIRouter
from cerebelum import DistributedExecutor
from app.workflows.booking_request import build_booking_request_workflow

router = APIRouter()


@router.post("/bookings")
async def create_booking(data: BookingRequest, current_user: User = Depends(get_current_user)):
    """
    Endpoint para crear una reserva.
    """
    executor = DistributedExecutor(core_url=os.getenv('CEREBELUM_CORE_URL'))

    result = await executor.execute(
        build_booking_request_workflow(),
        {
            'athlete_id': current_user.id,
            'coach_id': data.coach_id,
            'slot_datetime': data.slot_datetime.isoformat(),
            'athlete_notes': data.notes
        }
    )

    # Workflow es rápido (<1s), retorna booking confirmado
    return {
        'booking_id': result.output.get('booking_id'),
        'status': 'CONFIRMED',
        'execution_id': result.execution_id
    }


@router.post("/bookings/{booking_id}/complete")
async def complete_session(
    booking_id: str,
    data: CompleteSessionData,
    current_user: User = Depends(get_current_user)
):
    """
    Endpoint para que el coach marque la sesión como completada.
    """
    from app.workflows.session_completion import build_session_completion_workflow

    executor = DistributedExecutor(core_url=os.getenv('CEREBELUM_CORE_URL'))

    result = await executor.execute(
        build_session_completion_workflow(),
        {
            'booking_id': booking_id,
            'athlete_id': data.athlete_id,
            'coach_id': current_user.id,
            'actual_start_time': data.actual_start_time.isoformat(),
            'actual_end_time': data.actual_end_time.isoformat()
        }
    )

    # Workflow queda activo esperando evaluaciones (días)
    return {
        'message': 'Session completed. Feedback requests sent.',
        'execution_id': result.execution_id,
        'billable_minutes': result.output.get('actual_duration_minutes')
    }
```

### Paso 3: Endpoint para Aprobar Workflows

En `app/api/endpoints/feedback.py`:

```python
from fastapi import APIRouter
from cerebelum import DistributedExecutor

router = APIRouter()


@router.post("/feedback/submit")
async def submit_feedback(data: FeedbackData, current_user: User = Depends(get_current_user)):
    """
    Endpoint para que atleta/coach envíen feedback.
    """
    # Aprobar el workflow correspondiente
    executor = DistributedExecutor(core_url=os.getenv('CEREBELUM_CORE_URL'))

    # TODO: Implementar approve_execution en SDK
    # await executor.approve_execution(
    #     execution_id=data.execution_id,
    #     approval_type="athlete_session_feedback",
    #     approval_data={
    #         'rating': data.rating,
    #         'objectives_met': data.objectives_met,
    #         'comments': data.comments
    #     }
    # )

    return {'message': 'Thank you for your feedback!'}
```

---

## 📊 Workflows Implementados

### 1. Athlete Onboarding (`01_athlete_onboarding.py`)

**Trigger:** POST `/api/auth/register`

**Flujo:**
1. Valida registro
2. Espera 7 días que complete perfil (approval)
3. Habilita bookings

**Duración:** Hasta 7 días

**Casos de uso:**
- Atleta completa perfil inmediatamente → workflow termina en segundos
- Atleta tarda 3 días → workflow continúa después
- Atleta nunca completa → timeout a los 7 días

### 2. Booking Request (`02_booking_request.py`)

**Trigger:** POST `/api/bookings`

**Flujo:**
1. Valida slot disponible
2. Verifica balance
3. Crea booking
4. Reserva slot
5. Descuenta crédito
6. Confirma
7. Notifica coach y atleta (paralelo)

**Duración:** <1 segundo

**Ventajas:**
- Atómico (si algo falla, rollback completo)
- Notificaciones no bloquean confirmación

### 3. Session Completion (`03_session_completion.py`)

**Trigger:** POST `/api/bookings/{id}/complete`

**Flujo:**
1. Registra tiempo real trabajado
2. **PARALELO:**
   - Solicita feedback a atleta (timeout 48h)
   - Solicita evaluación a coach (timeout 7d)
3. Finaliza sesión

**Duración:** Hasta 7 días

**Características:**
- Workflows pueden durar días/semanas
- Timeouts automáticos
- Evaluaciones en paralelo
- Sobrevive a reinicios del sistema

### 4. Payment Report (`04_payment_report.py`)

**Trigger:** POST `/api/admin/reports/payment` o Cron Job

**Flujo:**
1. Consulta sesiones completadas
2. Calcula total horas
3. Agrupa por semana
4. Genera reporte
5. Guarda en DB
6. Exporta a CSV
7. Notifica admin

**Duración:** ~5 segundos

**Uso:**
- Manual: Admin ejecuta desde UI
- Automático: Cron job mensual

---

## 🗄️ Acceso a tu Base de Datos

### Opción 1: Importar Repositorios Directamente

**Recomendado** - Reutiliza tu código existente

```python
# En tus workflow steps
from app.domain.repositories.booking_repository import BookingRepository
from app.domain.repositories.user_repository import UserRepository

booking_repo = BookingRepository()
user_repo = UserRepository()

async def create_booking_step(ctx, inputs):
    # Usar tu repository existente
    booking = await booking_repo.create({
        'athlete_id': inputs['athlete_id'],
        'coach_id': inputs['coach_id'],
        'scheduled_at': inputs['slot_datetime'],
        'status': 'PENDING'
    })

    return {'booking_id': booking.id}
```

### Opción 2: Dependency Injection

Si usas DI en FastAPI:

```python
# app/workflows/dependencies.py
from app.domain.repositories import get_booking_repository

async def create_booking_step(ctx, inputs):
    # Obtener repository vía DI
    booking_repo = get_booking_repository()

    booking = await booking_repo.create(...)
    return {'booking_id': booking.id}
```

### Opción 3: Shared Database Connection Pool

```python
# app/database.py
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

engine = create_async_engine(os.getenv('DATABASE_URL'))
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession)

# En workflows
async def some_step(ctx, inputs):
    async with AsyncSessionLocal() as session:
        result = await session.execute("SELECT * FROM bookings WHERE id = :id", {'id': inputs['booking_id']})
        booking = result.fetchone()
        return {'booking': booking}
```

**IMPORTANTE:**
- ✅ Workers pueden acceder directamente a tu PostgreSQL
- ✅ Usan tu connection string existente
- ✅ Comparten el mismo pool de conexiones
- ✅ Respetan transacciones y locking

---

## 🐳 Docker Compose

### `docker-compose.yml`

```yaml
version: '3.8'

services:
  # Tu aplicación FastAPI existente
  fastapi-app:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@postgres:5432/zea_sport_db
      - CEREBELUM_CORE_URL=cerebelum-core:9090
    depends_on:
      - postgres
      - cerebelum-core
    volumes:
      - ./app:/app

  # Tu PostgreSQL existente
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: zea_sport_db
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  # Cerebelum Core (NUEVO)
  cerebelum-core:
    image: cerebelum/core:latest  # TODO: publicar imagen
    ports:
      - "9090:9090"
    environment:
      - DATABASE_URL=postgresql://user:pass@postgres-cerebelum:5432/cerebelum_db
      - ENABLE_WORKFLOW_RESURRECTION=true
    depends_on:
      - postgres-cerebelum

  # PostgreSQL para Cerebelum Event Store (NUEVO)
  postgres-cerebelum:
    image: postgres:15
    environment:
      POSTGRES_DB: cerebelum_db
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
    ports:
      - "5433:5432"  # Puerto diferente para no conflictuar
    volumes:
      - cerebelum_postgres_data:/var/lib/postgresql/data

  # Python Workers (NUEVO)
  cerebelum-worker:
    build: .
    command: python -m app.workers.main
    environment:
      - CEREBELUM_CORE_URL=cerebelum-core:9090
      - DATABASE_URL=postgresql://user:pass@postgres:5432/zea_sport_db
      - CEREBELUM_WORKER_ID=zea-sport-worker-${HOSTNAME:-1}
    depends_on:
      - cerebelum-core
      - postgres
    volumes:
      - ./app:/app
    deploy:
      replicas: 2  # Múltiples workers para paralelismo

volumes:
  postgres_data:
  cerebelum_postgres_data:
```

### `app/workers/main.py`

```python
#!/usr/bin/env python3
"""
Worker principal que ejecuta workflows de ZEA Sport.
"""

import asyncio
import os
from cerebelum import Worker

# Importar todos los workflows
from app.workflows.athlete_onboarding import build_athlete_onboarding_workflow
from app.workflows.booking_request import build_booking_request_workflow
from app.workflows.session_completion import build_session_completion_workflow
from app.workflows.payment_report import build_payment_report_workflow


async def main():
    core_url = os.getenv('CEREBELUM_CORE_URL', 'localhost:9090')
    worker_id = os.getenv('CEREBELUM_WORKER_ID', 'zea-sport-worker-1')

    print(f"Starting worker: {worker_id}")
    print(f"Connecting to Core: {core_url}")

    worker = Worker(core_url=core_url, worker_id=worker_id)

    try:
        await worker.run()
    except KeyboardInterrupt:
        print("Worker stopped by user")
    except Exception as e:
        print(f"Worker error: {e}")
        raise


if __name__ == "__main__":
    asyncio.run(main())
```

---

## 🔧 Desarrollo Local

### 1. Levantar Cerebelum Core

```bash
# Opción A: Docker Compose (recomendado)
docker-compose up cerebelum-core postgres-cerebelum

# Opción B: Local (si tienes Elixir instalado)
cd /path/to/cerebelum-core
mix deps.get
mix ecto.create
mix ecto.migrate
mix run --no-halt
```

### 2. Levantar Worker

```bash
# Terminal separada
cd /path/to/your-fastapi-app
source venv/bin/activate
python -m app.workers.main
```

### 3. Levantar FastAPI

```bash
# Terminal separada
uvicorn app.main:app --reload --port 8000
```

### 4. Testear

```bash
# Registrar atleta
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "juan@email.com", "password": "secret123"}'

# Monitorear workflow
cd /path/to/cerebelum-core/examples/python-sdk
./cerebelum_cli.py list
./cerebelum_cli.py status <execution-id>
```

---

## 📊 Monitoreo y Debugging

### CLI de Cerebelum

```bash
# Instalar
cd /path/to/cerebelum-core/examples/python-sdk
pip install click
chmod +x cerebelum_cli.py

# Listar executions
./cerebelum_cli.py list

# Ver estado detallado
./cerebelum_cli.py status <execution-id>

# Monitorear en tiempo real
./cerebelum_cli.py watch <execution-id>

# Resumir workflow fallido
./cerebelum_cli.py resume <execution-id>

# Ver workflows activos
./cerebelum_cli.py active
```

### ExecutionClient (Programático)

```python
from cerebelum import ExecutionClient, ExecutionState

client = ExecutionClient(core_url="localhost:9090")

# Listar workflows activos
active = await client.list_active_workflows()
for exec in active:
    print(f"{exec.workflow_name}: {exec.progress_percentage}%")

# Ver estado detallado
status = await client.get_execution_status("exec-123")
print(f"Progress: {status.progress_percentage}%")
print(f"Current Step: {status.current_step_name}")

# Listar fallidos
failed, total, _ = await client.list_executions(
    status=ExecutionState.FAILED
)

client.close()
```

### Logging

```python
# En tus workflows, usa logging estándar
import logging

logger = logging.getLogger(__name__)

async def some_step(ctx, inputs):
    logger.info(f"Processing booking {inputs['booking_id']}")
    # ...
    logger.error(f"Failed to create booking: {error}")
```

---

## ❓ Preguntas Frecuentes

### ¿Cómo integro con mi aplicación FastAPI existente?

1. Instalar `cerebelum-sdk`
2. Definir workflows en `app/workflows/`
3. Importar tus repositorios existentes en los steps
4. Ejecutar workflows desde tus endpoints usando `DistributedExecutor`
5. Levantar workers que ejecuten los steps

### ¿Cómo accedo a mi base de datos PostgreSQL?

Importa tus repositorios existentes directamente en los steps. Los workers tienen acceso completo a tu DB.

### ¿Cerebelum reemplaza mi arquitectura?

NO. Cerebelum es un **complemento** para workflows asíncronos de larga duración. Tu arquitectura Clean Architecture con FastAPI sigue igual.

### ¿Necesito cambiar mi schema de DB?

NO. Cerebelum usa su propia DB separada solo para event sourcing. Tu DB no se modifica.

### ¿Qué pasa si Cerebelum Core se cae?

Cuando vuelve a levantarse, **automáticamente resucita workflows pausados** gracias a event sourcing. Los workflows continúan desde donde quedaron.

### ¿Cómo manejo workflows que esperan días?

Usa `ctx.request_approval()` con `timeout_ms`. El workflow quedará en estado `WAITING_FOR_APPROVAL` y continuará automáticamente cuando:
- Reciba aprobación (feedback del usuario)
- Timeout expire (auto-completa)

### ¿Puedo tener múltiples workers?

SÍ. Levanta múltiples procesos de workers para paralelismo. Cerebelum distribuye automáticamente los steps entre workers disponibles.

### ¿Cómo hago rollback si algo falla?

Si un step falla, el workflow completo falla y NO ejecuta steps siguientes. Implementa lógica de compensación si necesitas deshacer cambios ya hechos.

### ¿Event sourcing es suficiente para analytics?

Event sourcing te da auditoría completa. Para analytics específicos, consulta tus tablas normales de PostgreSQL (bookings, users, etc.).

---

## 📚 Referencias

- [Cerebelum Documentation](../../docs/)
- [Python SDK Reference](../RESUMEN_PYTHON_SDK.md)
- [ExecutionClient API](../EXECUTION_CLIENT_README.md)
- [CLI Guide](../CLI_README.md)
- [Long-Running Workflows](../../docs/long-running-workflows.md)

---

## 🎯 Próximos Pasos

1. ✅ Revisar los 4 ejemplos de workflows
2. ✅ Copiar `docker-compose.yml` a tu proyecto
3. ✅ Crear `app/workflows/` con tus workflows
4. ✅ Crear `app/workers/main.py` con tu worker
5. ✅ Modificar endpoints para ejecutar workflows
6. ✅ Levantar todo con `docker-compose up`
7. ✅ Testear workflows con el CLI

¡Listo para empezar! 🚀
