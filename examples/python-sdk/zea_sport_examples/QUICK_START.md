# ZEA Sport + Cerebelum - Quick Start Guide

Guía rápida para integrar Cerebelum en tu aplicación FastAPI en **30 minutos**.

---

## 📋 Pre-requisitos

- ✅ Python 3.10+
- ✅ Docker & Docker Compose
- ✅ Tu aplicación FastAPI existente
- ✅ PostgreSQL (tu DB existente)

---

## 🚀 Setup en 5 Pasos

### Paso 1: Copiar Archivos a Tu Proyecto (5 min)

```bash
# En tu proyecto FastAPI
cd /path/to/your-fastapi-app

# Crear estructura de directorios
mkdir -p app/workflows
mkdir -p app/workers

# Copiar archivos de ejemplo
cp /path/to/cerebelum-core/examples/python-sdk/zea_sport_examples/docker-compose.yml .
cp /path/to/cerebelum-core/examples/python-sdk/zea_sport_examples/worker_main.py app/workers/main.py
cp /path/to/cerebelum-core/examples/python-sdk/zea_sport_examples/01_athlete_onboarding.py app/workflows/

# Copiar .env de ejemplo
cat > .env << 'EOF'
# Tu DB existente
DATABASE_URL=postgresql://user:pass@localhost:5432/zea_sport_db

# Cerebelum
CEREBELUM_CORE_URL=localhost:9090
CEREBELUM_WORKER_ID=zea-sport-worker-1

# Environment
ENVIRONMENT=development
DEBUG=true
EOF
```

### Paso 2: Instalar Cerebelum SDK (2 min)

```bash
# Activar venv
source venv/bin/activate

# Instalar SDK
pip install cerebelum-sdk  # TODO: Cuando se publique

# O instalar desde repo:
cd /path/to/cerebelum-core/examples/python-sdk
pip install -e .

# Volver a tu proyecto
cd /path/to/your-fastapi-app
```

### Paso 3: Adaptar Worker a Tu Código (5 min)

Editar `app/workers/main.py`:

```python
# Descomentar y adaptar estas líneas:

# 1. Initialize database (línea ~57)
from app.database import init_db
await init_db(self.database_url)

# 2. Import workflows (línea ~73)
from app.workflows.athlete_onboarding import build_athlete_onboarding_workflow
# ... más workflows
```

### Paso 4: Levantar Servicios (5 min)

```bash
# Opción A: Docker Compose (recomendado)
docker-compose up -d

# Ver logs
docker-compose logs -f

# Verificar que todo está running:
# ✅ fastapi-app (puerto 8000)
# ✅ cerebelum-core (puerto 9090)
# ✅ cerebelum-worker-1 y worker-2
# ✅ postgres (puerto 5432)
# ✅ postgres-cerebelum (puerto 5433)
```

```bash
# Opción B: Local (sin Docker)

# Terminal 1: Cerebelum Core
cd /path/to/cerebelum-core
mix ecto.create && mix ecto.migrate
mix run --no-halt

# Terminal 2: Worker
cd /path/to/your-fastapi-app
python -m app.workers.main

# Terminal 3: FastAPI
uvicorn app.main:app --reload --port 8000
```

### Paso 5: Probar Primer Workflow (10 min)

**5.1. Modificar un endpoint para ejecutar workflow:**

Editar `app/api/endpoints/auth.py`:

```python
from fastapi import APIRouter
from cerebelum import DistributedExecutor
from app.workflows.athlete_onboarding import build_athlete_onboarding_workflow

router = APIRouter()

@router.post("/register")
async def register_user(data: RegisterData):
    # 1. Tu lógica existente (crear usuario)
    user = await create_user_in_db(data)

    # 2. NUEVO: Ejecutar workflow de onboarding
    executor = DistributedExecutor(core_url="localhost:9090")

    result = await executor.execute(
        build_athlete_onboarding_workflow(),
        {'user_id': user.id, 'email': user.email}
    )

    return {
        'user_id': user.id,
        'execution_id': result.execution_id,
        'message': 'Registration successful!'
    }
```

**5.2. Probar el endpoint:**

```bash
# Registrar un usuario
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "juan@test.com",
    "password": "secret123"
  }'

# Respuesta:
# {
#   "user_id": "user-123",
#   "execution_id": "abc-def-ghi-...",
#   "message": "Registration successful!"
# }
```

**5.3. Monitorear el workflow:**

```bash
# Instalar CLI
cd /path/to/cerebelum-core/examples/python-sdk
pip install click
chmod +x cerebelum_cli.py

# Ver workflows activos
./cerebelum_cli.py list

# Ver estado detallado
./cerebelum_cli.py status <execution-id>

# Monitorear en tiempo real
./cerebelum_cli.py watch <execution-id>
```

---

## ✅ Verificación

Después de los 5 pasos, deberías tener:

- [x] Cerebelum Core corriendo en `localhost:9090`
- [x] 2 Workers corriendo y conectados
- [x] FastAPI corriendo en `localhost:8000`
- [x] Workflow de onboarding funcionando
- [x] CLI mostrando executions

### Troubleshooting

**Worker no se conecta:**
```bash
# Verificar que Core está corriendo
curl http://localhost:9090
# O ver logs:
docker-compose logs cerebelum-core
```

**Error de DB en worker:**
```bash
# Verificar DATABASE_URL
echo $DATABASE_URL

# Verificar que PostgreSQL está corriendo
psql $DATABASE_URL -c "SELECT 1"
```

**Workflow no aparece en CLI:**
```bash
# Verificar logs del worker
docker-compose logs cerebelum-worker-1

# O si corre local:
python -m app.workers.main
# Debería mostrar: "Worker ready! Waiting for tasks..."
```

---

## 🎯 Próximos Pasos

Una vez que tienes el onboarding funcionando:

### 1. Agregar Más Workflows

```bash
# Copiar ejemplos adicionales
cp /path/to/zea_sport_examples/02_booking_request.py app/workflows/
cp /path/to/zea_sport_examples/03_session_completion.py app/workflows/
cp /path/to/zea_sport_examples/04_payment_report.py app/workflows/

# Importarlos en worker
# Editar app/workers/main.py, método import_workflows()
```

### 2. Integrar en Más Endpoints

```python
# app/api/endpoints/bookings.py
from app.workflows.booking_request import build_booking_request_workflow

@router.post("/bookings")
async def create_booking(data: BookingRequest):
    executor = DistributedExecutor(core_url="localhost:9090")
    result = await executor.execute(build_booking_request_workflow(), ...)
    return {'booking_id': result.output['booking_id']}

# app/api/endpoints/sessions.py
from app.workflows.session_completion import build_session_completion_workflow

@router.post("/bookings/{id}/complete")
async def complete_session(id: str, data: CompleteData):
    executor = DistributedExecutor(core_url="localhost:9090")
    result = await executor.execute(build_session_completion_workflow(), ...)
    return {'execution_id': result.execution_id}
```

### 3. Monitoreo en Producción

```python
# Agregar endpoint de health check
@app.get("/health/workflows")
async def workflow_health():
    from cerebelum import ExecutionClient

    client = ExecutionClient(core_url="localhost:9090")

    # Ver workflows activos
    active = await client.list_active_workflows()

    return {
        'status': 'healthy',
        'active_workflows': len(active),
        'workflows': [{'id': w.execution_id, 'name': w.workflow_name} for w in active]
    }
```

### 4. Dashboard de Admin (Opcional)

```python
# app/api/endpoints/admin.py
from cerebelum import ExecutionClient, ExecutionState

@router.get("/admin/workflows")
async def list_workflows(
    status: str = None,
    workflow: str = None,
    limit: int = 50
):
    client = ExecutionClient(core_url="localhost:9090")

    status_filter = ExecutionState[status] if status else None

    executions, total, has_more = await client.list_executions(
        workflow_name=workflow,
        status=status_filter,
        limit=limit
    )

    return {
        'executions': [
            {
                'id': e.execution_id,
                'workflow': e.workflow_name,
                'status': e.status.value,
                'progress': e.progress_percentage,
                'current_step': e.current_step_name
            }
            for e in executions
        ],
        'total': total,
        'has_more': has_more
    }
```

---

## 📚 Documentación Completa

Una vez que tengas el setup básico funcionando, revisa:

1. **README.md** - Guía completa de integración
2. **RESPUESTAS_PREGUNTAS.md** - Respuestas a tus 6 preguntas
3. **Ejemplos de Workflows** - 4 workflows completos
   - `01_athlete_onboarding.py`
   - `02_booking_request.py`
   - `03_session_completion.py`
   - `04_payment_report.py`

---

## 💡 Tips

### Desarrollo Local

```bash
# Hot reload de workflows:
# 1. Editar workflow en app/workflows/
# 2. Reiniciar worker: Ctrl+C y volver a correr
# 3. Ejecutar workflow desde endpoint

# Ver logs en tiempo real:
docker-compose logs -f cerebelum-worker-1

# Restart solo un servicio:
docker-compose restart cerebelum-worker-1
```

### Testing

```bash
# Test de integración
pytest tests/test_workflows.py -v

# Test manual con curl
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "test@test.com", "password": "test123"}'
```

### Production Checklist

- [ ] Cambiar passwords de DB en `.env`
- [ ] Configurar `SECRET_KEY_BASE` en Cerebelum Core
- [ ] Ajustar número de workers según carga
- [ ] Configurar monitoreo (Prometheus, Grafana)
- [ ] Setup de logs centralizados
- [ ] Habilitar HTTPS en FastAPI
- [ ] Configurar backups de PostgreSQL (ambos DBs)

---

## 🆘 Ayuda

Si tienes problemas:

1. Revisa logs: `docker-compose logs -f`
2. Verifica health: `curl http://localhost:9090/health`
3. Usa CLI: `./cerebelum_cli.py list`
4. Revisa **RESPUESTAS_PREGUNTAS.md** para casos comunes

---

¡Listo para empezar! 🚀

**Tiempo total:** ~30 minutos
**Complejidad:** Media
**Resultado:** Workflows funcionando en tu app FastAPI
