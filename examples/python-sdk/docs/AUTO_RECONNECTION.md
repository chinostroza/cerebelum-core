# Auto-Reconnection en Workers Distribuidos

## 🎯 Problema Resuelto

En ambientes productivos, los workers deben ser resilientes ante:
- ✅ Reinicios de Core
- ✅ Pérdidas temporales de red
- ✅ Timeouts de conexión
- ✅ Fallos transitorios

**Antes:** El worker fallaba y requería intervención manual para reiniciar.

**Ahora:** El worker se reconecta automáticamente con reintentos inteligentes.

---

## 🔧 Características

### 1. **Reconexión Automática**
El worker detecta desconexiones y se reconecta automáticamente sin intervención humana.

### 2. **Exponential Backoff**
Los reintentos usan delays crecientes para evitar saturar Core:
```
Intento 1: 1 segundo
Intento 2: 2 segundos
Intento 3: 4 segundos
Intento 4: 8 segundos
Intento 5: 16 segundos
...
Intento N: máximo 60 segundos
```

### 3. **Detección de Fallas**
- Monitorea heartbeats y polls
- Después de 3 fallos consecutivos → activa reconexión
- Distingue entre fallos temporales y permanentes

### 4. **Re-registro Automático**
Al reconectar:
1. ✅ Re-registra el worker con Core
2. ✅ Re-submite todos los workflows (blueprints)
3. ✅ Reanuda heartbeats
4. ✅ Reanuda polling de tareas

---

## 📖 Uso

### Configuración por Defecto (Recomendada)

```python
from cerebelum.distributed import Worker

worker = Worker(
    worker_id="my-worker",
    core_url="localhost:9090",
    # Auto-reconnect habilitado por defecto
)

# Registrar steps y workflows
worker.register_step("my_step", my_step_function)
worker.register_workflow(my_workflow)

# Iniciar worker (con auto-reconnection)
await worker.start()
```

**Comportamiento:**
- ✅ Reconexión automática habilitada
- ✅ Reintentos infinitos (no se rinde nunca)
- ✅ Backoff exponencial: 1s → 2s → 4s → ... → 60s (máx)

---

### Configuración Personalizada

```python
worker = Worker(
    worker_id="my-worker",
    core_url="localhost:9090",

    # Habilitar/deshabilitar auto-reconnect
    auto_reconnect=True,

    # Máximo de reintentos (0 = infinito)
    max_reconnect_attempts=10,

    # Delay inicial para backoff exponencial
    reconnect_base_delay=1.0,  # segundos

    # Delay máximo entre reintentos
    reconnect_max_delay=60.0,  # segundos
)
```

**Ejemplos de configuración:**

#### Producción (Resiliente)
```python
worker = Worker(
    worker_id="prod-worker",
    core_url="core.company.com:9090",
    auto_reconnect=True,
    max_reconnect_attempts=0,  # Nunca se rinde
    reconnect_max_delay=60.0,
)
```

#### Desarrollo (Falla Rápido)
```python
worker = Worker(
    worker_id="dev-worker",
    core_url="localhost:9090",
    auto_reconnect=True,
    max_reconnect_attempts=5,  # Solo 5 intentos
    reconnect_max_delay=10.0,  # Delays más cortos
)
```

#### Testing (Sin Auto-Reconnect)
```python
worker = Worker(
    worker_id="test-worker",
    core_url="localhost:9090",
    auto_reconnect=False,  # Falla inmediatamente
)
```

---

## 🎬 Escenarios

### Escenario 1: Core se reinicia

```
[Worker] ✅ Worker 'my-worker' registered successfully
[Worker] 📋 Polling for tasks...

[Core] (reinicia)

[Worker] ❌ Heartbeat error (1/3): UNAVAILABLE
[Worker] ❌ Heartbeat error (2/3): UNAVAILABLE
[Worker] ❌ Heartbeat error (3/3): UNAVAILABLE
[Worker] ⚠️  Connection lost, attempting to reconnect...
[Worker] 🔄 Reconnection attempt 1 in 1.0s...
[Worker] ❌ Registration failed: failed to connect to all addresses
[Worker] 🔄 Reconnection attempt 2 in 2.0s...
[Worker] ❌ Registration failed: failed to connect to all addresses
[Worker] 🔄 Reconnection attempt 3 in 4.0s...

[Core] (ya está listo)

[Worker] ✅ Worker 'my-worker' registered successfully
[Worker] ✅ Workflow 'my_workflow' blueprint submitted successfully
[Worker] ✅ Reconnected successfully after 3 attempts
[Worker] 📋 Polling for tasks...
```

### Escenario 2: Pérdida temporal de red

```
[Worker] 📋 Received task: process_data (execution: abc-123)
[Worker] ✅ Task completed: process_data

(pérdida de red por 5 segundos)

[Worker] ❌ Poll error (1/3): UNAVAILABLE
[Worker] ❌ Poll error (2/3): UNAVAILABLE
[Worker] ❌ Poll error (3/3): UNAVAILABLE
[Worker] ⚠️  Connection lost, attempting to reconnect...
[Worker] 🔄 Reconnection attempt 1 in 1.0s...

(red se recupera)

[Worker] ✅ Worker 'my-worker' registered successfully
[Worker] ✅ Reconnected successfully after 1 attempts
[Worker] 📋 Polling for tasks...
[Worker] 📋 Received task: process_data (execution: def-456)
```

### Escenario 3: Core nunca vuelve (max attempts)

```
[Worker] ⚠️  Connection lost, attempting to reconnect...
[Worker] 🔄 Reconnection attempt 1 in 1.0s...
[Worker] ❌ Registration failed
[Worker] 🔄 Reconnection attempt 2 in 2.0s...
[Worker] ❌ Registration failed
...
[Worker] 🔄 Reconnection attempt 10 in 60.0s...
[Worker] ❌ Registration failed
[Worker] ❌ Max reconnection attempts (10) reached, stopping worker
[Worker] 🛑 Stopping worker...
[Worker] ✅ Worker 'my-worker' stopped
```

---

## 🔍 Logs y Monitoreo

### Logs Importantes

**Conexión exitosa:**
```
✅ Worker 'my-worker' registered successfully
✅ Workflow 'my_workflow' blueprint submitted successfully
```

**Detección de falla:**
```
❌ Heartbeat error (3/3): UNAVAILABLE
⚠️  Connection lost, attempting to reconnect...
```

**Reconexión en progreso:**
```
🔄 Reconnection attempt 3 in 4.0s...
```

**Reconexión exitosa:**
```
✅ Reconnected successfully after 3 attempts
```

**Reconexión fallida (max attempts):**
```
❌ Max reconnection attempts (10) reached, stopping worker
```

### Métricas Sugeridas

Para monitorear en producción:
- `reconnection_attempts` - Contador de intentos de reconexión
- `reconnection_successes` - Reconexiones exitosas
- `reconnection_failures` - Reconexiones fallidas (max attempts)
- `time_disconnected` - Tiempo total desconectado

---

## ✅ Mejores Prácticas

### 1. **Producción**
```python
# Configuración resiliente para producción
worker = Worker(
    worker_id=f"prod-worker-{os.getenv('POD_NAME')}",
    core_url=os.getenv("CORE_URL"),
    auto_reconnect=True,
    max_reconnect_attempts=0,  # Nunca se rinde
    reconnect_max_delay=60.0,
)
```

### 2. **Múltiples Workers**
- Usa `worker_id` único para cada worker
- Considera prefijos: `prod-worker-1`, `prod-worker-2`, etc.
- Permite múltiples workers procesando en paralelo

### 3. **Idempotencia**
- Los steps deben ser idempotentes
- Core puede reenviar tareas después de reconexión
- Maneja duplicados apropiadamente

### 4. **Logging**
```python
import logging

logging.basicConfig(level=logging.INFO)
# El Worker usa print(), considera agregar logging structurado
```

### 5. **Health Checks**
```python
# En tu deployment (Kubernetes, Docker, etc.)
# Health check: verificar que worker esté conectado
if worker.connected:
    return 200  # Healthy
else:
    return 503  # Not ready
```

---

## 🔧 Troubleshooting

### Worker no se reconecta

**Síntoma:** Worker dice "Auto-reconnect disabled"

**Solución:** Verifica que `auto_reconnect=True`:
```python
worker = Worker(..., auto_reconnect=True)
```

### Worker se rinde muy rápido

**Síntoma:** "Max reconnection attempts (5) reached"

**Solución:** Aumenta `max_reconnect_attempts` o usa 0 (infinito):
```python
worker = Worker(..., max_reconnect_attempts=0)
```

### Delays muy largos entre reintentos

**Síntoma:** "Reconnection attempt 10 in 60.0s..."

**Solución:** Reduce `reconnect_max_delay`:
```python
worker = Worker(..., reconnect_max_delay=30.0)
```

### Core nunca acepta reconexión

**Problema:** Core podría tener problemas o estar saturado

**Diagnóstico:**
1. Verifica logs de Core
2. Verifica conectividad de red: `telnet core-url 9090`
3. Verifica que Core esté corriendo: `ps aux | grep beam`

---

## 🎉 Beneficios

### Para Operaciones
- ✅ Menos intervención manual
- ✅ Mayor uptime de workers
- ✅ Recuperación automática de fallos transitorios
- ✅ Reinicio de Core sin downtime de workers

### Para Desarrollo
- ✅ Reinicia Core sin reiniciar workers
- ✅ Mejor experiencia de desarrollo
- ✅ Testing de resilencia más fácil

### Para Producción
- ✅ Alta disponibilidad
- ✅ Tolerancia a fallos de red
- ✅ Escalamiento horizontal más sencillo
- ✅ Mantenimiento de Core sin downtime

---

**Versión:** 1.0.0
**Última actualización:** 2025-11-21
