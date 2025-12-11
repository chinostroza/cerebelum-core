# Respuesta: Pausar workflow y esperar condición asíncrona

**De:** Carlos Hinostroza Droguett (c@zea.cl)
**Fecha:** 2024-12-09
**Asunto:** Re: Digital Ocean droplet IP polling - Approach recomendado

---

Hola equipo,

¡Excelente pregunta! Este es un patrón muy común. Tengo **buenas y malas noticias**:

## ✅ Buenas Noticias

**Cerebelum Core tiene todo lo necesario:**
- ✅ Sleep/wait no bloqueante (state machine)
- ✅ Approval/HITL con timeouts
- ✅ Retry mechanism con diverge
- ✅ Status polling API

**Malas noticias:**
- ❌ El Python SDK v1.2 **NO expone** estas features (aún)

## 🎯 Solución Recomendada (HOY)

Para tu caso específico de Digital Ocean, usa **un step dedicado para polling**:

```python
from cerebelum import step, workflow, Context
import asyncio

@step
async def create_droplet(context: Context, inputs: dict) -> dict:
    """Crear droplet - retorna inmediatamente"""
    droplet = digital_ocean_client.droplets.create(...)
    return {"droplet_id": droplet.id, "status": "creating"}

@step
async def wait_for_droplet_ready(context: Context, create_droplet: dict) -> dict:
    """Step dedicado a polling - espera IP disponible"""
    droplet_id = create_droplet["droplet_id"]

    # Polling con timeout
    max_attempts = 30  # 30 * 3s = 90s max
    for attempt in range(1, max_attempts + 1):
        print(f"[{attempt}/{max_attempts}] Checking droplet {droplet_id}...")

        droplet = digital_ocean_client.droplets.get(droplet_id)

        # Verificar si tiene IP y está activo
        if droplet.status == "active" and droplet.ip_address:
            return {
                "droplet_id": droplet_id,
                "ip": droplet.ip_address,
                "ready": True,
                "attempts": attempt
            }

        await asyncio.sleep(3)  # Espera entre polls

    # Timeout
    raise TimeoutError(f"Droplet {droplet_id} IP not ready after 90s")

@step
async def verify_ssh_access(context: Context, wait_for_droplet_ready: dict) -> dict:
    """Verificar SSH accesible - con retry"""
    ip = wait_for_droplet_ready["ip"]

    for attempt in range(1, 11):  # 10 intentos
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(ip, username="root", timeout=5)
            ssh.close()
            return {"ip": ip, "ssh_ready": True}
        except Exception as e:
            if attempt == 10:
                raise ConnectionError(f"SSH not ready: {e}")
            await asyncio.sleep(5)

@step
async def configure_server(context: Context, verify_ssh_access: dict) -> dict:
    """Configurar - SSH ya garantizado"""
    ip = verify_ssh_access["ip"]
    # ... tu configuración
    return {"configured": True}

@workflow
def deploy_workflow(wf):
    wf.timeline(
        create_droplet >>
        wait_for_droplet_ready >>  # ← Polling step
        verify_ssh_access >>       # ← Verification step
        configure_server
    )
```

## ✨ ¿Por qué este approach?

1. **Separación de responsabilidades**
   - `create_droplet` → Crear recurso (rápido)
   - `wait_for_droplet_ready` → Polling hasta condición cumplida
   - `verify_ssh_access` → Verificar acceso
   - `configure_server` → Ejecutar configuración

2. **Ventajas:**
   - ✅ Funciona **hoy** sin modificar el SDK
   - ✅ Cada step es testeable independientemente
   - ✅ Logs claros de progreso
   - ✅ Fácil debuggear si falla
   - ✅ Puedes ajustar timeouts por step

3. **Comparado con tu código actual:**
   ```python
   # ❌ Tu approach actual (todo en un step):
   @step
   async def create_droplet(...):
       droplet = create(...)
       while not has_ip(droplet_id):  # Bloquea el step
           time.sleep(5)
       return {...}

   # ✅ Approach recomendado (steps separados):
   create_droplet >> wait_for_ready >> verify >> configure
   ```

## 🚀 Roadmap: Python SDK v2.0 (Q1 2025)

Estamos trabajando en soporte nativo:

```python
# Feature 1: Sleep decorator
@step
@sleep(seconds=60)
async def wait_time(context, inputs):
    return inputs

# Feature 2: Poll decorator
@step
@poll(condition=lambda r: r.get("ip") is not None, interval=5, max_attempts=20)
async def wait_for_ip(context, create_droplet):
    droplet = get_droplet(create_droplet["droplet_id"])
    return {"ip": droplet.ip_address}  # Re-ejecuta si ip es None

# Feature 3: Approval decorator
@step
@approval(type="manual", timeout_minutes=60)
async def wait_approval(context, inputs):
    return {"approved": True}
```

## 📚 Recursos

He creado una **guía completa** con:
- ✅ 3 approaches diferentes (con código completo)
- ✅ Helper reutilizable para polling
- ✅ Retry con backoff exponencial
- ✅ Explicación de capacidades del Core
- ✅ Roadmap de features futuras

**Guía completa:** `docs/async-operations-guide.md`

## 💡 Casos de Uso Similares

| Caso | Patrón |
|------|--------|
| CI/CD build | `trigger_build >> poll_build_status >> deploy` |
| DB provisioning | `create_db >> poll_db_ready >> migrate` |
| SSL certificate | `request_cert >> poll_cert_issued >> configure` |
| Health checks | `deploy >> poll_health >> notify` |

## 📞 Contacto

Si necesitas más ayuda o tienes preguntas:
- **Email:** c@zea.cl
- **GitHub:** https://github.com/cerebelum-io/cerebelum-core/issues

---

**En resumen:**

Tu caso de uso es **totalmente válido** y Cerebelum lo soporta. Por ahora usa **steps dedicados para polling** (funciona perfecto). En SDK v2.0 tendrás decorators nativos más elegantes.

¡Gracias por el feedback! Esto nos ayuda a priorizar features. 🚀

**Carlos**
