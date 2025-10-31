# Tutorial 2: GenServers and Supervision

**Tiempo estimado:** 20 minutos
**Prerrequisitos:** [Tutorial 1 - Understanding Processes](01-understanding-processes.md)

## Introducción

En el tutorial anterior vimos cómo usar `spawn`, `send` y `receive` directamente. Esto funciona, pero tiene problemas:

- 🤔 Mucho código repetitivo (`loop` recursivo)
- 🤔 Manejo de errores manual
- 🤔 Difícil de testear
- 🤔 Sin convenciones estándar

**GenServer** resuelve esto proveyendo una plantilla estándar para procesos con estado.

## ¿Qué es un GenServer?

Un **GenServer** (Generic Server) es una abstracción sobre procesos que provee:
- ✅ Manejo automático de mensajes
- ✅ Estado interno
- ✅ Callbacks estándar
- ✅ Integración con Supervisors
- ✅ Debugging tools

### Anatomía de un GenServer

```elixir
defmodule MiServidor do
  use GenServer  # ← Importa el comportamiento GenServer

  # API Pública (Cliente)
  # ─────────────────────────────────────────

  def start_link(initial_state) do
    GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def increment do
    GenServer.cast(__MODULE__, :increment)
  end

  # Callbacks (Servidor)
  # ─────────────────────────────────────────

  @impl true
  def init(initial_state) do
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:increment, state) do
    {:noreply, state + 1}
  end
end
```

## Tipos de Llamadas: Call vs Cast

### Call (Síncrono - espera respuesta)

```elixir
defmodule BancoCuenta do
  use GenServer

  # API
  def start_link(saldo_inicial) do
    GenServer.start_link(__MODULE__, saldo_inicial, name: __MODULE__)
  end

  def consultar_saldo do
    GenServer.call(__MODULE__, :consultar_saldo)
  end

  def depositar(monto) do
    GenServer.call(__MODULE__, {:depositar, monto})
  end

  # Callbacks
  def init(saldo) do
    {:ok, saldo}
  end

  def handle_call(:consultar_saldo, _from, saldo) do
    {:reply, saldo, saldo}
  end

  def handle_call({:depositar, monto}, _from, saldo) do
    nuevo_saldo = saldo + monto
    {:reply, {:ok, nuevo_saldo}, nuevo_saldo}
  end
end

# Usar
{:ok, _pid} = BancoCuenta.start_link(100)

saldo = BancoCuenta.consultar_saldo()
IO.puts("Saldo actual: #{saldo}")
# Output: Saldo actual: 100

{:ok, nuevo} = BancoCuenta.depositar(50)
IO.puts("Nuevo saldo: #{nuevo}")
# Output: Nuevo saldo: 150
```

**Visual:**
```
Cliente                    GenServer (BancoCuenta)
  |                              |
  |------- :consultar_saldo ---->|
  |                          [estado: 100]
  |<-------- 100 ----------------|
  |         (BLOQUEADO)           |
  |                              |
```

### Cast (Asíncrono - no espera respuesta)

```elixir
defmodule Logger do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def log(mensaje) do
    GenServer.cast(__MODULE__, {:log, mensaje})
    # ← Retorna inmediatamente, no espera
  end

  def init(_) do
    {:ok, []}
  end

  def handle_cast({:log, mensaje}, logs) do
    IO.puts("[LOG] #{mensaje}")
    {:noreply, [mensaje | logs]}
  end
end

# Usar
{:ok, _} = Logger.start_link([])

Logger.log("Inicio del sistema")
Logger.log("Usuario conectado")
# ← Estas llamadas retornan inmediatamente

IO.puts("Continúo sin esperar...")

# Output:
# [LOG] Inicio del sistema
# [LOG] Usuario conectado
# Continúo sin esperar...
```

**Visual:**
```
Cliente                    GenServer (Logger)
  |                              |
  |------- {:log, "msg"} ------->|
  |<-------- :ok ----------------|
  |  (NO BLOQUEADO)          [procesa]
  |                          [actualiza estado]
  |                              |
```

### ¿Cuándo usar cada uno?

| Situación | Usar |
|-----------|------|
| Necesitas respuesta inmediata | `call` |
| Consultar estado | `call` |
| Operación crítica (ej: transferencia) | `call` |
| Notificación/logging | `cast` |
| Fire-and-forget | `cast` |
| Performance crítico (evitar bloqueo) | `cast` |

## Manejo de Mensajes Especiales

### handle_info - Mensajes no esperados

```elixir
defmodule Temporizador do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{contador: 0}, name: __MODULE__)
  end

  def init(state) do
    # Programar un mensaje cada segundo
    schedule_tick()
    {:ok, state}
  end

  def handle_info(:tick, %{contador: c} = state) do
    IO.puts("Tick #{c}")
    schedule_tick()  # Programar siguiente tick
    {:noreply, %{state | contador: c + 1}}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, 1000)
  end
end

# Usar
{:ok, _} = Temporizador.start_link([])
:timer.sleep(5000)

# Output:
# Tick 0
# Tick 1
# Tick 2
# Tick 3
# Tick 4
```

**Importante:** `handle_info` maneja mensajes que NO vienen de `call` o `cast`.

## Supervisors: Vigilando Procesos

Un **Supervisor** es un proceso especial que vigila otros procesos y los reinicia si fallan.

### Ejemplo Básico

```elixir
defmodule MiWorker do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    IO.puts("Worker iniciado: #{inspect(self())}")
    {:ok, %{}}
  end

  def crash do
    GenServer.call(__MODULE__, :crash)
  end

  def handle_call(:crash, _from, state) do
    raise "¡Boom!"
  end
end

defmodule MiSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {MiWorker, name: MiWorker}
    ]

    # Si el worker muere, reiniciarlo
    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Usar
{:ok, _sup_pid} = MiSupervisor.start_link([])

# El worker está corriendo
IO.puts("Worker PID: #{inspect(Process.whereis(MiWorker))}")

# Hacer que crashee
try do
  MiWorker.crash()
rescue
  _ -> IO.puts("Worker crasheó")
end

:timer.sleep(100)

# ¡El supervisor ya lo reinició!
IO.puts("Worker PID después de crash: #{inspect(Process.whereis(MiWorker))}")

# Output:
# Worker iniciado: #PID<0.123.0>
# Worker PID: #PID<0.123.0>
# Worker crasheó
# Worker iniciado: #PID<0.125.0>  ← ¡Nuevo PID!
# Worker PID después de crash: #PID<0.125.0>
```

**Visual:**
```
        Supervisor
            |
     [vigila a Worker]
            |
         Worker
      [PID<0.123.0>]
            |
         💥 CRASH!
            |
      [Supervisor detecta]
            |
      [Reinicia Worker]
            |
         Worker
      [PID<0.125.0>]  ← ¡Nuevo proceso!
```

### Estrategias de Supervisión

#### 1. :one_for_one (más común)

Si un hijo muere, solo reinicia ese hijo:

```
    Supervisor
    /    |    \
   A     B     C

   A muere 💥
   ↓
   Supervisor reinicia solo A
   ↓
    Supervisor
    /    |    \
   A'    B     C
```

#### 2. :one_for_all

Si un hijo muere, reinicia TODOS los hijos:

```
    Supervisor
    /    |    \
   A     B     C

   A muere 💥
   ↓
   Supervisor reinicia A, B, y C
   ↓
    Supervisor
    /    |    \
   A'    B'    C'
```

Útil cuando los procesos están relacionados y necesitan reiniciarse juntos.

#### 3. :rest_for_one

Si un hijo muere, reinicia ese hijo y todos los que fueron iniciados **después** de él:

```
    Supervisor
    /    |    \
   A     B     C
        💥
   ↓
   Supervisor reinicia B y C (A sigue corriendo)
   ↓
    Supervisor
    /    |    \
   A     B'    C'
```

## Supervision Tree

Los supervisores pueden supervisar otros supervisores, creando un árbol:

```elixir
defmodule MiApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Supervisor de workers
      {WorkerSupervisor, []},

      # Supervisor de servicios
      {ServicesSupervisor, []},

      # GenServer único
      {Cache, []}
    ]

    opts = [strategy: :one_for_one, name: MiApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule WorkerSupervisor do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      {Worker1, []},
      {Worker2, []},
      {Worker3, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

**Visual del árbol:**
```
           MiApp.Supervisor
           /       |        \
          /        |         \
  WorkerSup   ServicesSup   Cache
     / | \        / \
    /  |  \      /   \
   W1  W2  W3   S1   S2
```

**Ventajas:**
- Si W1 falla → WorkerSup lo reinicia
- Si WorkerSup falla → MiApp.Supervisor lo reinicia (y todos sus hijos)
- Si MiApp.Supervisor falla → toda la aplicación se reinicia

## Relación con Cerebelum

Así es como Cerebelum usa GenServers y Supervisors:

```elixir
# Supervision tree de Cerebelum
Cerebelum.Application
    |
    ├── ExecutionSupervisor (DynamicSupervisor)
    |   ├── ExecutionEngine (GenServer) - workflow 1
    |   ├── ExecutionEngine (GenServer) - workflow 2
    |   └── ExecutionEngine (GenServer) - workflow 3
    |
    ├── EventStoreSupervisor
    |   ├── EventStore (GenServer)
    |   └── Snapshotter (GenServer)
    |
    └── DeterministicSupervisor
        ├── TimeManager (GenServer)
        ├── RandomManager (GenServer)
        └── MemoizationManager (GenServer)
```

**Cada ExecutionEngine es un GenServer que:**
1. Mantiene el estado de una ejecución de workflow
2. Ejecuta nodos uno por uno
3. Guarda eventos en EventStore
4. Si crashea → supervisor lo reinicia → lee eventos → continúa

## DynamicSupervisor

Un `DynamicSupervisor` permite agregar/remover hijos dinámicamente:

```elixir
defmodule Cerebelum.ExecutionSupervisor do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Iniciar una nueva ejecución
  def start_execution(workflow, input) do
    spec = {Cerebelum.ExecutionEngine, workflow: workflow, input: input}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end

# Usar
{:ok, pid1} = Cerebelum.ExecutionSupervisor.start_execution(WorkflowA, %{})
{:ok, pid2} = Cerebelum.ExecutionSupervisor.start_execution(WorkflowB, %{})
# ... miles de ejecuciones en paralelo
```

## Resumen

| Concepto | Descripción | Uso en Cerebelum |
|----------|-------------|------------------|
| **GenServer** | Proceso con estado y callbacks estándar | ExecutionEngine, EventStore, Managers |
| **call** | Llamada síncrona (espera respuesta) | Consultar estado, operaciones críticas |
| **cast** | Llamada asíncrona (no espera) | Eventos, notificaciones |
| **handle_info** | Mensajes especiales (timers, etc.) | Timers para `sleep`, mensajes internos |
| **Supervisor** | Vigila y reinicia procesos | Todos los componentes de Cerebelum |
| **:one_for_one** | Reinicia solo el hijo que falló | Ejecuciones independientes |
| **DynamicSupervisor** | Hijos dinámicos en runtime | Crear ejecuciones bajo demanda |

## Ejercicio: Contador con Supervisor

Crea un GenServer contador que:
1. Puede crashear cuando llega a 10
2. Está supervisado
3. Al reiniciar, debería empezar en 0 otra vez

<details>
<summary>Ver solución</summary>

```elixir
defmodule ContadorPeligroso do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, 0, name: __MODULE__)
  end

  def incrementar do
    GenServer.call(__MODULE__, :incrementar)
  end

  def init(_) do
    IO.puts("Contador iniciado")
    {:ok, 0}
  end

  def handle_call(:incrementar, _from, state) do
    nuevo = state + 1

    if nuevo >= 10 do
      raise "¡Contador explotó en 10!"
    end

    {:reply, nuevo, nuevo}
  end
end

defmodule MiSupervisor do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [ContadorPeligroso]
    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Probar
{:ok, _} = MiSupervisor.start_link([])

for i <- 1..12 do
  try do
    result = ContadorPeligroso.incrementar()
    IO.puts("Contador: #{result}")
  rescue
    _ ->
      IO.puts("💥 Crash en #{i}")
      :timer.sleep(100)  # Dar tiempo al supervisor
  end
end

# Output:
# Contador iniciado
# Contador: 1
# Contador: 2
# ...
# Contador: 9
# 💥 Crash en 10
# Contador iniciado  ← ¡Reiniciado!
# Contador: 1        ← Empieza desde 0
```
</details>

**Problema:** El contador pierde su estado al reiniciar. En el [próximo tutorial](03-event-sourcing.md), veremos cómo **Event Sourcing** resuelve esto.

## Siguiente: Event Sourcing

Ahora entiendes procesos y supervisión, pero viste que al reiniciar, **el estado se pierde**.

En el [próximo tutorial](03-event-sourcing.md), aprenderás cómo **Event Sourcing** permite reconstruir el estado después de un crash.

## Referencias

- [Elixir GenServer Docs](https://hexdocs.pm/elixir/GenServer.html)
- [Elixir Supervisor Docs](https://hexdocs.pm/elixir/Supervisor.html)
- [Learn You Some Erlang - Who Supervises the Supervisors?](https://learnyousomeerlang.com/supervisors)
