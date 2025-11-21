# 🎓 Cerebelum Python SDK - Tutorial Completo

**Aprende Cerebelum desde cero hasta workflows avanzados**

Este tutorial te guía paso a paso, desde conceptos básicos hasta workflows complejos de producción. Cada archivo es un tutorial independiente que construye sobre el anterior.

---

## 📚 Tabla de Contenidos

1. [Quick Start](#-quick-start)
2. [Tutorial Paso a Paso](#-tutorial-paso-a-paso)
3. [Modos de Ejecución](#-modos-de-ejecución)
4. [Ejemplos Avanzados](#-ejemplos-avanzados)
5. [Conceptos Clave](#-conceptos-clave)
6. [Tips y Troubleshooting](#-tips-y-troubleshooting)

---

## 🚀 Quick Start

**¿Primera vez con Cerebelum? Empieza aquí:**

```bash
cd examples/python-sdk
python3 01_hello_world.py
```

**Tiempo:** 3 minutos | **Nivel:** 🟢 Principiante

---

## 📖 Tutorial Paso a Paso

Sigue estos tutoriales **en orden**. Cada uno construye sobre el anterior:

### Tutorial 01: Hello World
**Archivo:** `01_hello_world.py`
**Tiempo:** 3 minutos | **Dificultad:** 🟢

**Aprenderás:**
- ✅ Decorador `@step` - define pasos del workflow
- ✅ Decorador `@workflow` - compone los pasos
- ✅ `Context` - información del workflow
- ✅ Ejecución básica con `await workflow.execute()`

**Ejecutar:**
```bash
python3 01_hello_world.py
```

**Código ejemplo:**
```python
@step
async def greet(context: Context, inputs: dict):
    name = inputs.get("name", "World")
    return f"Hello, {name}!"  # Auto-wrapped to {"ok": "Hello, ..."}

@workflow
def hello_workflow(wf):
    wf.timeline(greet)

# Ejecutar
result = await hello_workflow.execute({"name": "Alice"})
```

---

### Tutorial 02: Dependencies
**Archivo:** `02_dependencies.py`
**Tiempo:** 5 minutos | **Dificultad:** 🟢

**Requisito:** Completar Tutorial 01

**Aprenderás:**
- ✅ Dependencias entre steps
- ✅ Inyección automática de resultados
- ✅ Composición con operador `>>`
- ✅ Flujo de datos entre steps

**Ejecutar:**
```bash
python3 02_dependencies.py
```

**Código ejemplo:**
```python
@step
async def fetch_user(context, inputs):
    return {"id": 123, "name": "Alice"}

@step
async def send_email(context, fetch_user: dict):  # ← Dependencia!
    user = fetch_user  # Recibe resultado automáticamente
    print(f"Email sent to {user['name']}")
    return {"sent": True}

@workflow
def my_workflow(wf):
    wf.timeline(fetch_user >> send_email)  # >> conecta steps
```

**🔑 Punto Clave:** El nombre del parámetro (`fetch_user`) debe coincidir con el nombre del step.

---

### Tutorial 03: Parallel Execution
**Archivo:** `03_parallel_execution.py`
**Tiempo:** 7 minutos | **Dificultad:** 🟡

**Requisito:** Completar Tutorials 01-02

**Aprenderás:**
- ✅ Sintaxis de lista `[step_a, step_b]` para paralelismo
- ✅ Cuándo usar ejecución paralela
- ✅ Combinar resultados de steps paralelos
- ✅ Visualizar el flujo de ejecución

**Ejecutar:**
```bash
python3 03_parallel_execution.py
```

**Código ejemplo:**
```python
@workflow
def my_workflow(wf):
    wf.timeline(
        get_data >>
        [process_a, process_b, process_c] >>  # 🔥 PARALELO!
        combine_results
    )
```

**🔑 Punto Clave:** Steps en `[]` se ejecutan EN PARALELO, no secuencialmente.

**Comparación:**
```
Secuencial: A → B → C → D (tiempo total: 4s)
Paralelo:   A → [B,C,D] → E (tiempo total: 2s)
                 ︿︿︿
              simultáneo
```

---

### Tutorial 04: Error Handling
**Archivo:** `04_error_handling.py`
**Tiempo:** 8 minutos | **Dificultad:** 🟡

**Requisito:** Completar Tutorials 01-03

**Aprenderás:**
- ✅ Auto-wrapping de excepciones
- ✅ Usar excepciones nativas de Python (`raise`)
- ✅ NO necesitas `return {"error": ...}`
- ✅ Código más limpio y Pythonic

**Ejecutar:**
```bash
python3 04_error_handling.py
```

**Código ejemplo:**

**❌ ANTES (verbose):**
```python
@step
async def validate(context, inputs):
    try:
        age = inputs["age"]
        if age < 18:
            return {"error": "too_young"}  # Manual
        return {"ok": {"age": age}}  # Manual
    except Exception as e:
        return {"error": str(e)}  # Manual
```

**✅ AHORA (clean):**
```python
@step
async def validate(context, inputs):
    age = inputs["age"]
    if age < 18:
        raise ValueError("too_young")  # ✅ Pythonic!
    return {"age": age}  # ✅ Auto-wrapped!
```

**🔑 Punto Clave:**
- `raise Exception` → automáticamente convertido a `{"error": "mensaje"}`
- `return value` → automáticamente convertido a `{"ok": value}`

---

### Tutorial 05: Complete Example
**Archivo:** `05_complete_example.py`
**Tiempo:** 15 minutos | **Dificultad:** 🟡

**Requisito:** Completar Tutorials 01-04

**Aprenderás:**
- ✅ Workflow completo real (8 steps)
- ✅ Aplicar todo lo aprendido
- ✅ Ejecución paralela en workflow real
- ✅ Flujo de datos complejo

**Ejecutar:**
```bash
python3 05_complete_example.py
```

**Escenario:** Sistema de procesamiento de pedidos e-commerce
1. `authenticate_user` - Autenticación
2. `fetch_order` - Obtener pedido
3. `validate_inventory` - Validar stock
4. `calculate_tax` - Calcular impuestos
5. `process_payment` - Procesar pago
6. **[PARALELO]** `send_confirmation_email` + `update_order_status`
7. `finalize_order` - Finalizar

**Resultado:**
```
✅ Workflow completed successfully!
  - Order ID: ORD-2024-001
  - Payment ID: PAY-XXXXXXXX
  - Amount: $1165.97
  - Status: confirmed
```

---

### Tutorial 06: Distributed Mode (Servidor + Cliente)
**Archivos:** `06_distributed_server.py` + `06_execute_workflow.py`
**Tiempo:** 15 minutos | **Dificultad:** 🟡

**Requisito:** Completar Tutorials 01-05

**Aprenderás:**
- ✅ Modo DISTRIBUIDO (producción) - con Core/Workers
- ✅ Cómo levantar un worker server
- ✅ Cómo ejecutar workflows remotamente
- ✅ Arquitectura cliente-servidor

**Setup:**
```bash
# Terminal 1: Inicia Core
cd ../../ && mix run --no-halt

# Terminal 2: Inicia Worker Server
python3 06_distributed_server.py

# Terminal 3: Ejecuta workflows
python3 06_execute_workflow.py hello_workflow Alice
```

**Código ejemplo - Server (`06_distributed_server.py`):**
```python
# Define workflows
@step
async def greet(context: Context, inputs: dict):
    name = inputs.get("name", "World")
    return {"message": f"Hello, {name}!"}

@workflow
def hello_workflow(wf):
    wf.timeline(greet)

# Ejecutar en modo distribuido (nunca retorna - servidor)
await hello_workflow.execute(
    inputs={"name": "Initial"},
    distributed=True  # 🔥 Modo servidor!
)
```

**Código ejemplo - Client (`06_execute_workflow.py`):**
```python
from cerebelum.distributed import DistributedExecutor

# Crear executor
executor = DistributedExecutor(
    core_url="localhost:9090",
    worker_id="python-executor"
)

# Ejecutar workflow remoto
result = await executor.execute(
    workflow="hello_workflow",  # ID del workflow registrado
    input_data={"name": "Alice"}
)

print(f"Execution ID: {result.execution_id}")
```

**Comparación:**

| Aspecto | LOCAL | DISTRIBUIDO |
|---------|-------|-------------|
| Core needed? | ❌ No | ✅ Yes |
| Workers needed? | ❌ No | ✅ Yes |
| Setup | 🟢 Simple | 🟡 Medium |
| Speed | 🟢 Fast | 🟡 Network delay |
| Scalability | ❌ Single process | ✅ Distributed |
| Use case | Dev/Test | Production |

**🔑 Puntos Clave:**
- El **server** se ejecuta con `distributed=True` y nunca retorna (corre hasta Ctrl+C)
- El **client** usa `DistributedExecutor` para enviar ejecuciones a Core
- Puedes ejecutar múltiples workflows desde el mismo cliente
- Puedes tener múltiples workers procesando en paralelo

**🎉 Felicitaciones!** Has completado todos los tutoriales básicos.

---

### Tutorial 07: Enterprise Onboarding - Distributed Complex Workflow
**Archivos:** `07_distributed_server.py` + `07_execute_workflow.py`
**Tiempo:** 25 minutos | **Dificultad:** 🔴

**Requisito:** Completar Tutorials 01-06

**Aprenderás:**
- ✅ Workflows complejos distribuidos con 12+ steps
- ✅ 3 niveles de paralelismo coordinado
- ✅ Dependencias complejas entre steps
- ✅ Simulación de integraciones reales (Slack, GitHub, Email, etc.)
- ✅ Arquitectura de workflow empresarial en modo distribuido

**Setup (3 terminales):**
```bash
# Terminal 1: Inicia Core
cd ../../ && mix run --no-halt

# Terminal 2: Inicia Worker Server
python3 07_distributed_server.py

# Terminal 3: Ejecuta onboarding
python3 07_execute_workflow.py "Jane Doe" "jane.doe@company.com" "Engineering" "Developer"
```

**Escenario:** Sistema completo de onboarding de usuario empresarial

**Estructura del workflow:**
```
authenticate → validate_user_data →

FASE 1 (Provisioning - Paralelo):
├─ create_user_account       (Sistema de identidad)
├─ setup_workspace            (Directorio personal)
└─ provision_tools            (Email, Calendar, Chat)
       ↓
FASE 2 (Configuration - Paralelo):
├─ setup_permissions          (Permisos basados en rol)
├─ configure_integrations     (Slack, GitHub, Jira)
└─ create_documentation       (Docs personalizadas)
       ↓
FASE 3 (Notifications - Paralelo):
├─ send_welcome_email         (Email con credenciales)
├─ notify_team                (Notificación en Slack)
└─ schedule_onboarding_calls  (Agendar reuniones)
       ↓
finalize_onboarding           (Reporte final)
```

**Código ejemplo - Server (`07_distributed_server.py`):**
```python
# Define todos los 12 steps del onboarding
@step
async def authenticate(context: Context, inputs: dict):
    # Autenticar admin...
    return {"admin_id": ..., "admin_name": ...}

@step
async def validate_user_data(context: Context, inputs: dict):
    # Validar datos del nuevo usuario...
    return {"user_id": ..., "validated_data": ...}

# ... 10 steps más ...

@workflow
def enterprise_onboarding_workflow(wf):
    wf.timeline(
        authenticate >> validate_user_data >>
        [create_user_account, setup_workspace, provision_tools] >>
        [setup_permissions, configure_integrations, create_documentation] >>
        [send_welcome_email, notify_team, schedule_onboarding_calls] >>
        finalize_onboarding
    )

# Ejecutar en modo distribuido (servidor)
await enterprise_onboarding_workflow.execute(
    inputs={...},
    distributed=True  # 🔥 Modo servidor!
)
```

**Código ejemplo - Client (`07_execute_workflow.py`):**
```python
from cerebelum.distributed import DistributedExecutor

# Crear executor
executor = DistributedExecutor(
    core_url="localhost:9090",
    worker_id="python-onboarding-executor"
)

# Ejecutar onboarding remoto
result = await executor.execute(
    workflow="enterprise_onboarding_workflow",
    input_data={
        "admin_id": "ADM-001",
        "admin_token": "valid-admin-token",
        "user_data": {
            "name": "Jane Doe",
            "email": "jane.doe@company.com",
            "department": "Engineering",
            "role": "Developer"
        }
    }
)
```

**Ejemplos de uso:**
```bash
# Developer
python3 07_execute_workflow.py "Jane Doe" "jane@company.com" "Engineering" "Developer"

# Manager
python3 07_execute_workflow.py "John Smith" "john@company.com" "Sales" "Manager"

# Designer
python3 07_execute_workflow.py "Alice Wong" "alice@company.com" "Design" "Designer"

# Analyst
python3 07_execute_workflow.py "Bob Chen" "bob@company.com" "Analytics" "Analyst"
```

**Resultado (visible en Terminal 2 - Worker):**
```
✅ ONBOARDING COMPLETED!
   User: Jane Doe (jane@company.com)
   Role: Developer | Dept: Engineering
   Account: ACC-USR-...
   Execution: abc-123-def-456
```

**🔑 Puntos Clave:**
- **Modo distribuido completo** - Core + Worker + Client
- **3 fases paralelas** ejecutándose de forma coordinada
- **Dependencias complejas** - cada fase depende de las anteriores
- **Simulación realista** - delays que imitan servicios reales
- **Múltiples usuarios** - procesa varios onboardings simultáneamente
- **Escalable** - múltiples workers pueden procesar en paralelo

**💡 Nota:** También disponible versión local para desarrollo:
```bash
python3 07_enterprise_onboarding_local.py
```

**🎉 Felicitaciones!** Has completado todos los tutoriales - desde básicos hasta avanzados distribuidos.

---

## 🔄 Modos de Ejecución - Resumen

Cerebelum tiene **DOS MODOS** de ejecución:

### 1️⃣ LOCAL (Por Defecto) - Desarrollo

```python
result = await workflow.execute({"input": "data"})
```

**Características:**
- ✅ Sin Core (no necesitas `docker compose up`)
- ✅ Sin Workers (todo en el mismo proceso)
- ✅ Setup instantáneo
- 🎯 **Perfecto para:** Desarrollo, testing, debugging, aprendizaje

**Todos los tutoriales usan modo LOCAL**

### 2️⃣ DISTRIBUIDO (Opcional) - Producción

```python
result = await workflow.execute(
    {"input": "data"},
    use_local=False  # 🔥 Activa modo distribuido
)
```

**Características:**
- ⚠️ Requiere Core corriendo (`docker compose up`)
- ⚠️ Requiere Workers registrados
- ✅ Escalable (múltiples workers)
- 🎯 **Perfecto para:** Producción, sistemas distribuidos

**Ver Tutorial 06 (archivos 06_distributed_server.py y 06_execute_workflow.py)**

---

## 💡 Conceptos Clave

### Auto-Wrapping

**No necesitas escribir:**
```python
return {"ok": value}
return {"error": "message"}
```

**Solo escribe:**
```python
return value  # Auto-wrapped a {"ok": value}
raise ValueError("message")  # Auto-caught a {"error": "message"}
```

### Dependencies (Inyección Automática)

**Declaras dependencias con nombres de parámetros:**
```python
@step
async def step_b(context, step_a: dict):  # ← Depende de step_a
    data = step_a  # Recibe resultado automáticamente
```

**El nombre debe coincidir con el nombre del step.**

### Parallel Syntax

**Lista `[]` = ejecución paralela:**
```python
wf.timeline(
    step1 >>
    [step2, step3, step4] >>  # Estos 3 en paralelo
    step5
)
```

### Context

**Información del workflow actual:**
```python
context.execution_id   # ID único de ejecución
context.workflow_name  # Nombre del workflow
context.step_name      # Nombre del step actual
context.attempt        # Número de intento (si hay retries)
```

---

## 🆘 Tips y Troubleshooting

### Tips Generales

1. **Siempre usa `async def`** para los steps
2. **Primer parámetro siempre `context`**
3. **Nombres de parámetros = dependencias**
4. **Return directamente** - no envuelvas en `{"ok": ...}`
5. **Usa `raise` para errores** - no retornes `{"error": ...}`
6. **Lista `[]` para paralelismo** explícito

### Errores Comunes

**❌ "Step functions must be async"**
```python
# Mal
def my_step(context, inputs):  # Falta async

# Bien
async def my_step(context, inputs):
```

**❌ "First parameter must be 'context'"**
```python
# Mal
async def my_step(inputs):

# Bien
async def my_step(context: Context, inputs):
```

**❌ "Step X depends on Y which is not yet registered"**
```python
# Mal: typo en nombre
async def process(context, fetch_usr: dict):  # fetch_usr != fetch_user

# Bien
async def process(context, fetch_user: dict):
```

**❌ "Connection refused" (modo distribuido)**
```bash
# Core no está corriendo
# Solución 1: Inicia Core
docker compose up -d

# Solución 2: Usa modo LOCAL
result = await workflow.execute(inputs)  # use_local=True es default
```

### Debugging

**Ver qué step está ejecutando:**
```python
@step
async def my_step(context, inputs):
    print(f"[{context.step_name}] Processing...")  # ← Útil para debug
```

**Ver execution_id:**
```python
result = await workflow.execute(inputs)
print(f"Execution: {result.execution_id}")
```

---

## 📊 Resumen del Tutorial

**Has aprendido:**

| Tutorial | Concepto | Tiempo | Dificultad |
|----------|----------|--------|------------|
| 01 | Hello World | 3 min | 🟢 |
| 02 | Dependencies | 5 min | 🟢 |
| 03 | Parallel Execution | 7 min | 🟡 |
| 04 | Error Handling | 8 min | 🟡 |
| 05 | Complete Example | 15 min | 🟡 |
| 06 | Distributed Mode (Server + Client) | 15 min | 🟡 |
| 07 | Enterprise Onboarding (Distributed) | 25 min | 🔴 |

**Total:** ~80 minutos | De principiante a avanzado

---

## 🚀 Próximos Pasos

1. ✅ Completa todos los tutoriales en orden (01-06)
2. 📖 Lee [`CHANGELOG.md`](./CHANGELOG.md) para ver todas las mejoras
3. 🔍 Documentación detallada: [`docs/IMPROVEMENTS.md`](./docs/IMPROVEMENTS.md)
4. 🧪 Ejecuta los tests: `python3 -m pytest cerebelum/`
5. 🛠️ Construye tu propio workflow!

---

## 🎯 Flujo Recomendado

```
Día 1: Tutoriales 01-02 (conceptos básicos)
Día 2: Tutorial 03 (paralelismo)
Día 3: Tutorial 04 (errores)
Día 4: Tutorial 05 (ejemplo completo)
Día 5: Tutorial 06 (modo distribuido - server + client)
Día 6: Tutorial 07 (workflow complejo empresarial)
```

---

**¿Preguntas?** Lee los comentarios en cada archivo tutorial - están llenos de explicaciones detalladas.

**Versión:** DSL v1.2.0
**Última actualización:** 2025-11-21

---

**¡Feliz aprendizaje con Cerebelum! 🎉**
