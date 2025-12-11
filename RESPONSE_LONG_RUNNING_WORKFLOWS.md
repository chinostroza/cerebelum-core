# Re: Best practices para polling/waiting en steps

**From:** Cerebelum Team
**To:** Development Team
**Date:** December 11, 2024
**Subject:** Long-running operations support - New SDK helpers

---

¡Hola equipo!

Gracias por la excelente pregunta sobre polling y waiting patterns. Nos da mucho gusto que estés usando Cerebelum para workflows de deployment automático! 🚀

Tenemos **muy buenas noticias**: acabamos de lanzar **helpers oficiales** en el SDK (v2.1.0) específicamente para este caso de uso. Tu approach actual funciona, pero ahora tenemos formas más idiomáticas y poderosas de manejarlo.

---

## ✨ Nuevos Helpers Disponibles (SDK v2.1.0)

Hemos agregado al SDK:

```python
from cerebelum import sleep, poll, retry, ProgressReporter
```

### 1️⃣ `poll()` - Para operaciones con latencia variable

**Tu caso de uso (Digital Ocean droplet):**

```python
from cerebelum import step, poll, Context

@step
async def create_droplet(context: Context, inputs: dict) -> dict:
    # Crear droplet
    droplet = digitalocean.Droplet(...)
    droplet.create()

    return {"droplet_id": droplet.id}

@step
async def wait_for_droplet_ip(context: Context, create_droplet: dict) -> dict:
    droplet_id = create_droplet["droplet_id"]

    # ✅ APPROACH RECOMENDADO - Usar poll()
    result = await poll(
        check_fn=lambda: manager.get_droplet(droplet_id),
        interval=5000,  # Check every 5 seconds
        max_attempts=30,  # Max 2.5 minutes
        success_condition=lambda d: d.ip_address is not None,
        on_attempt=lambda n, d: print(f"Waiting for IP... ({n}/30)")
    )

    return {"ip_address": result.ip_address}
```

**Ventajas sobre el approach manual:**

✅ **Más limpio** - Separa lógica de polling de lógica de negocio
✅ **Reusable** - Misma función para todos tus casos de polling
✅ **Flexible** - `success_condition` customizable
✅ **Timeouts** - Soporte para `max_attempts` y `timeout` total
✅ **Progress reporting** - Callback `on_attempt` para logs
✅ **Future-ready** - Cuando uses Core distribuido, se integra con workflow resurrection

---

### 2️⃣ `retry()` - Para failures transitorios

**Tu pregunta sobre retry automático:**

```python
from cerebelum import step, retry, Context

@step
async def connect_server(context: Context, wait_for_droplet_ip: dict) -> dict:
    ip = wait_for_droplet_ip["ip_address"]

    # ✅ RETRY CON EXPONENTIAL BACKOFF
    connection = await retry(
        fn=establish_ssh_connection,
        ip=ip,
        max_attempts=10,
        delay=5000,  # Start with 5s
        backoff=2.0,  # Double each time (5s, 10s, 20s, 40s...)
        on_error=SSHConnectionError,  # Only retry SSH errors
        on_attempt=lambda n, e: print(f"SSH retry {n}/10: {e}")
    )

    return {"connection": connection}

# Helper function
async def establish_ssh_connection(ip: str):
    """Connect via SSH - may fail transiently."""
    client = paramiko.SSHClient()
    client.connect(ip, username="root", timeout=10)
    return client
```

**Features:**

✅ **Exponential backoff** - Configurable con parámetro `backoff`
✅ **Selective retry** - Solo reintenta errores específicos con `on_error`
✅ **Progress callbacks** - Tracking de cada intento
✅ **Async/sync support** - Funciona con ambos tipos de funciones

---

### 3️⃣ `ProgressReporter` - Para reportar progreso

**Tu pregunta sobre `context.update_progress()`:**

```python
from cerebelum import step, ProgressReporter, Context, sleep

@step
async def long_deployment(context: Context, inputs: dict) -> dict:
    progress = ProgressReporter(context)

    progress.update(0, "Creating infrastructure...")
    await provision_infrastructure()

    progress.update(33, "Deploying application...")
    await deploy_app()

    progress.update(66, "Running migrations...")
    await run_migrations()

    progress.update(100, "Deployment complete!")

    return {"status": "deployed"}
```

**Output en consola:**

```
  [long_deployment] ████████░░░░░░░░░░░░ 33% - Deploying application...
```

**Futuro (con cerebelum-web):**

Cuando implementemos la UI web, estos progress updates se mostrarán en tiempo real en el dashboard! 📊

---

### 4️⃣ `sleep()` - Para workflows de larga duración

**Tu pregunta sobre pausar workflows:**

```python
from cerebelum import step, sleep, Context
from datetime import timedelta

@step
async def send_reminder(context: Context, inputs: dict) -> dict:
    user_email = inputs["user_email"]

    # Send first reminder
    send_email(user_email, "Welcome!")

    # Sleep for 24 hours
    await sleep(timedelta(days=1))  # ⭐ Workflow-aware sleep

    # Send second reminder (continues after 24h)
    send_email(user_email, "Day 1 reminder")

    return {"reminders_sent": 2}
```

**Importante para tu use case:**

- **En modo local** (DSLLocalExecutor): Usa `asyncio.sleep()` normal
- **En modo distribuido** (con Core): El workflow puede **hibernar** y **resucitar**
  - Proceso se termina para ahorrar memoria
  - Estado se persiste en DB
  - Scheduler automático lo despierta después de 24h
  - Continúa exactamente donde quedó ✨

**Esto significa:**

✅ Workflows pueden "dormir" días/semanas
✅ Sobreviven a restarts del sistema
✅ Aprobaciones humanas que tardan días funcionan perfecto
✅ Deployments de 10-20 minutos son triviales

---

## 🔄 Refactorización Recomendada

### Antes (tu approach actual):

```python
@step
async def create_droplet(context: Context, inputs: dict) -> dict:
    droplet.create()

    # ❌ Polling manual en el step
    max_attempts = 30
    attempt = 0
    while attempt < max_attempts:
        droplet.load()
        if droplet.ip_address:
            break
        print(f"Esperando IP... ({attempt + 1}/{max_attempts})")
        time.sleep(5)
        attempt += 1

    if not droplet.ip_address:
        raise RuntimeError("Timeout esperando IP")

    return {"ip_address": droplet.ip_address}
```

### Después (approach recomendado):

```python
@step
async def create_droplet(context: Context, inputs: dict) -> dict:
    """Create droplet - returns immediately."""
    droplet.create()
    return {"droplet_id": droplet.id}

@step
async def wait_for_droplet_ip(context: Context, create_droplet: dict) -> dict:
    """Wait for IP using poll() helper - CLEAN & REUSABLE."""
    droplet_id = create_droplet["droplet_id"]

    # ✅ Limpio, declarativo, reusable
    result = await poll(
        check_fn=lambda: manager.get_droplet(droplet_id),
        interval=5000,
        max_attempts=30,
        success_condition=lambda d: d.ip_address is not None,
        on_attempt=lambda n, _: print(f"Waiting for IP... ({n}/30)")
    )

    return {"ip_address": result.ip_address}

@workflow
def droplet_deployment(wf):
    wf.timeline(create_droplet >> wait_for_droplet_ip >> configure_server)
```

**Por qué separar en steps?**

✅ **Composición** - Reutilizar `wait_for_droplet_ip` en otros workflows
✅ **Testing** - Testear creación y waiting independientemente
✅ **Observabilidad** - Ver duración de cada fase separadamente
✅ **Determinismo** - Event sourcing captura cada transición
✅ **Debugging** - Replay desde cualquier punto

---

## 📚 Otros Casos de Uso

### SSL Certificate (Let's Encrypt):

```python
@step
async def wait_for_ssl_cert(context: Context, request_cert: dict) -> dict:
    domain = request_cert["domain"]

    result = await poll(
        check_fn=lambda: check_cert_status(domain),
        interval=10000,  # Every 10 seconds
        timeout=timedelta(minutes=5),  # Max 5 minutes total
        success_condition=lambda r: r["status"] == "issued"
    )

    return result
```

### PostgreSQL Ready:

```python
@step
async def wait_for_postgres(context: Context, create_db: dict) -> dict:
    db_url = create_db["connection_string"]

    result = await poll(
        check_fn=lambda: test_db_connection(db_url),
        interval=2000,  # Every 2 seconds
        max_attempts=30,
        success_condition=lambda r: r.get("connectable") is True
    )

    return {"db_ready": True}
```

### CI/CD Build Complete:

```python
@step
async def wait_for_build(context: Context, trigger_build: dict) -> dict:
    build_id = trigger_build["build_id"]

    result = await poll(
        check_fn=lambda: get_build_status(build_id),
        interval=30000,  # Every 30 seconds
        max_attempts=60,  # Max 30 minutes
        success_condition=lambda b: b["status"] in ["success", "failure"],
        on_attempt=lambda n, b: print(f"Build status: {b['status']}")
    )

    if result["status"] == "failure":
        raise RuntimeError(f"Build failed: {result['error']}")

    return result
```

---

## 🎯 Ejemplo Completo

Hemos creado un ejemplo completo con todos los patterns:

**Ver:** `examples/python-sdk/08_long_running_workflows.py`

Incluye:
- ✅ Digital Ocean droplet deployment (tu use case)
- ✅ SSL certificate issuance
- ✅ Multi-day workflows con sleep
- ✅ Deployment completo con progress reporting
- ✅ Retry logic con exponential backoff

**Ejecutar:**

```bash
cd examples/python-sdk
python3 08_long_running_workflows.py
```

---

## 🚀 Roadmap Futuro

### Actualmente (SDK v2.1.0):

✅ `poll()`, `retry()`, `sleep()`, `ProgressReporter` funcionan en **modo local**
✅ Workflows corren completamente en tu proceso Python
✅ Ideal para desarrollo y workflows cortos (<1 hora)

### Próximamente (cuando uses Core distribuido):

Cuando conectes al Core de Elixir (opcional):

✅ **Workflow Resurrection** - Sobrevive a restarts del sistema
✅ **Process Hibernation** - Workflows largos liberan memoria automáticamente
✅ **Distributed Execution** - Workers en múltiples máquinas
✅ **Web UI** - Dashboard en tiempo real (cerebelum-web)
✅ **Observability** - Métricas de Prometheus (cerebelum-observability)

**Tu código NO cambia** - Los helpers funcionan en ambos modos! 🎉

---

## 📖 Documentación Completa

### API Reference:

```python
async def poll(
    check_fn: Callable,
    *,
    interval: int = 5000,  # ms between checks
    max_attempts: int = 30,
    timeout: Optional[Union[int, timedelta]] = None,
    success_condition: Optional[Callable[[Any], bool]] = None,
    on_attempt: Optional[Callable[[int, Any], None]] = None
) -> Any
```

```python
async def retry(
    fn: Callable,
    *args,
    max_attempts: int = 3,
    delay: int = 1000,  # ms
    backoff: float = 1.0,
    on_error: Optional[type[Exception]] = None,
    on_attempt: Optional[Callable[[int, Optional[Exception]], None]] = None,
    **kwargs
) -> Any
```

```python
async def sleep(duration: Union[int, float, timedelta]) -> None
# int/float: milliseconds
# timedelta: time delta object
```

---

## 🤔 Preguntas Respondidas

> **1. ¿Es este el approach recomendado?**

Tu approach funciona correctamente, pero ahora recomendamos usar `poll()` por:
- Más limpio y declarativo
- Reusable across workflows
- Future-ready para resurrection
- Mejor separación de concerns

> **2. Retry mechanism: ¿El SDK tiene soporte para retry automático?**

✅ **Sí!** Usa la función `retry()`:

```python
result = await retry(
    fn=connect_server,
    max_attempts=10,
    delay=5000,
    on_error=SSHConnectionError
)
```

> **3. Progress reporting: ¿Hay alguna forma de reportar progreso sin `print()`?**

✅ **Sí!** Usa `ProgressReporter`:

```python
progress = ProgressReporter(context)
progress.update(50, "Halfway done...")
```

Actualmente imprime a stdout, pero cuando uses cerebelum-web se mostrará en UI!

> **4. Pausar y reanudar workflows de 10-20 minutos**

✅ **Sí!** Usa `sleep()`:

```python
await sleep(timedelta(minutes=15))
```

En modo local: async sleep normal
En modo distribuido: workflow resurrection automático

---

## 💡 Best Practices

### 1. Separar steps para polling

```python
# ✅ GOOD - Separado en steps
create_resource >> wait_for_resource >> configure_resource

# ❌ AVOID - Todo en un step
create_and_wait_resource >> configure_resource
```

### 2. Usar success_condition específica

```python
# ✅ GOOD - Condición específica
success_condition=lambda d: d.ip_address is not None

# ❌ AVOID - Condición vaga
success_condition=lambda d: d  # Cualquier truthy value
```

### 3. Timeout razonable

```python
# ✅ GOOD - Timeout total + max attempts
poll(
    check_fn=...,
    interval=5000,
    max_attempts=30,  # 2.5 minutes
    timeout=timedelta(minutes=3)  # Backup timeout
)
```

### 4. Progress callbacks informativos

```python
# ✅ GOOD - Progreso útil
on_attempt=lambda n, r: print(f"Attempt {n}: status={r['status']}")

# ❌ AVOID - Sin información
on_attempt=lambda n, r: print(f"Attempt {n}")
```

---

## 🎉 Conclusión

**Tu approach actual funciona perfectamente**, pero con estos nuevos helpers puedes:

✅ Código más limpio y mantenible
✅ Reutilizar lógica de polling/retry
✅ Better separation of concerns
✅ Progress reporting built-in
✅ Future-ready para cuando uses Core distribuido

**Update recomendado:**

```bash
# Actualizar SDK
cd examples/python-sdk
git pull origin main

# Tu código actual sigue funcionando
# Pero ahora puedes usar los helpers!
```

**¿Preguntas o dudas?**

No dudes en preguntar! Estamos muy activos y nos encanta el feedback. 🚀

**Links útiles:**

- 📘 Ejemplo completo: `examples/python-sdk/08_long_running_workflows.py`
- 📖 Docs: `docs/async-operations-guide.md`
- 💬 GitHub Discussions: [cerebelum-io/cerebelum-core/discussions](https://github.com/cerebelum-io/cerebelum-core/discussions)

---

Gracias por usar Cerebelum! 🧠✨

**Equipo Cerebelum**
c@zea.cl
