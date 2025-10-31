# Tutorial 1: Understanding Processes

**Tiempo estimado:** 15 minutos

## Introducción

Elixir/Erlang tiene un modelo de concurrencia único basado en el **Modelo de Actores**. Antes de entender cómo Cerebelum maneja workflows, necesitas entender cómo funcionan los procesos.

## ¿Qué es un Proceso?

Un proceso en Elixir es una **unidad de ejecución independiente** con:
- Su propia memoria (no comparte nada con otros procesos)
- Su propio mailbox (buzón de mensajes)
- Su propia vida (puede morir sin afectar a otros)

### Analogía: Oficina con empleados

Imagina una oficina donde cada empleado es un proceso:

```
Empleado A          Empleado B          Empleado C
┌─────────┐        ┌─────────┐        ┌─────────┐
│📝 Memoria│        │📝 Memoria│        │📝 Memoria│
│  Privada │        │  Privada │        │  Privada │
├─────────┤        ├─────────┤        ├─────────┤
│📬 Buzón │        │📬 Buzón │        │📬 Buzón │
│  Email  │        │  Email  │        │  Email  │
└─────────┘        └─────────┘        └─────────┘
```

- Cada empleado tiene su propio escritorio (memoria)
- No pueden ver el escritorio del otro
- Se comunican enviando emails (mensajes)
- Si uno se enferma, los demás siguen trabajando

## Creando tu Primer Proceso

### Ejemplo 1: Proceso simple

```elixir
# Crear un proceso que imprime un mensaje
pid = spawn(fn ->
  IO.puts("¡Hola desde el proceso #{inspect(self())}!")
  :timer.sleep(1000)
  IO.puts("Proceso terminado")
end)

IO.puts("Proceso creado con PID: #{inspect(pid)}")
IO.puts("El proceso principal continúa...")

# Output:
# Proceso creado con PID: #PID<0.123.0>
# El proceso principal continúa...
# ¡Hola desde el proceso #PID<0.123.0>!
# Proceso terminado
```

**Puntos clave:**
- `spawn/1` crea un nuevo proceso
- Retorna un PID (Process ID) como `#PID<0.123.0>`
- El proceso hijo corre **en paralelo** con el principal
- Cada proceso tiene su propio `self()` (su PID)

### Ejemplo 2: Comunicación entre procesos

```elixir
# Proceso que recibe mensajes
pid = spawn(fn ->
  receive do
    {:saludar, nombre} ->
      IO.puts("¡Hola #{nombre}!")

    {:sumar, a, b} ->
      IO.puts("#{a} + #{b} = #{a + b}")

    other ->
      IO.puts("Mensaje desconocido: #{inspect(other)}")
  end
end)

# Enviar mensajes al proceso
send(pid, {:saludar, "Alice"})
send(pid, {:sumar, 5, 3})
send(pid, {:despedir})

# Output:
# ¡Hola Alice!
# (El proceso ya terminó después del primer mensaje)
```

**Problema:** El proceso solo maneja **un mensaje** y muere.

### Ejemplo 3: Proceso con loop (maneja múltiples mensajes)

```elixir
defmodule Calculadora do
  def loop do
    receive do
      {:sumar, a, b, caller} ->
        send(caller, {:resultado, a + b})
        loop()  # ¡Recursión! Vuelve a esperar mensajes

      {:restar, a, b, caller} ->
        send(caller, {:resultado, a - b})
        loop()

      :terminar ->
        IO.puts("Calculadora terminando...")
        # No llama a loop(), proceso termina
    end
  end
end

# Iniciar el proceso
pid = spawn(fn -> Calculadora.loop() end)

# Enviar mensajes
send(pid, {:sumar, 10, 5, self()})

# Recibir respuesta
receive do
  {:resultado, res} -> IO.puts("Resultado: #{res}")
end

send(pid, {:restar, 10, 5, self()})

receive do
  {:resultado, res} -> IO.puts("Resultado: #{res}")
end

send(pid, :terminar)

# Output:
# Resultado: 15
# Resultado: 5
# Calculadora terminando...
```

**Puntos clave:**
- `loop()` recursivo permite manejar múltiples mensajes
- `receive` bloquea hasta recibir un mensaje
- Los procesos son **muy livianos** (puedes tener millones)

## Aislamiento de Memoria

```elixir
# Estado en el proceso principal
contador_principal = 0

# Crear un proceso hijo
spawn(fn ->
  # ¡Esto NO comparte memoria con el padre!
  contador_hijo = 100
  IO.puts("Hijo: #{contador_hijo}")
end)

IO.puts("Principal: #{contador_principal}")

# Output:
# Hijo: 100
# Principal: 0
```

**Importante:** Cada proceso tiene su propia memoria. No hay variables compartidas (no hay race conditions).

## Procesos en Paralelo

```elixir
# Crear 5 procesos que corren en paralelo
for i <- 1..5 do
  spawn(fn ->
    :timer.sleep(Enum.random(100..500))
    IO.puts("Proceso #{i} terminó")
  end)
end

:timer.sleep(1000)

# Output (orden aleatorio):
# Proceso 3 terminó
# Proceso 1 terminó
# Proceso 5 terminó
# Proceso 2 terminó
# Proceso 4 terminó
```

## ¿Por qué es Importante para Cerebelum?

En Cerebelum, **cada workflow execution es un proceso**:

```elixir
# Usuario ejecuta un workflow
execution_id = Cerebelum.start_workflow(MyWorkflow, %{user_id: 123})

# Internamente, Cerebelum hace:
pid = spawn(fn ->
  ExecutionEngine.run(MyWorkflow, %{user_id: 123}, execution_id)
end)

# Ahora tienes:
# - 1 proceso para la ejecución del workflow
# - Memoria aislada (no afecta otros workflows)
# - Si este workflow falla, otros continúan
```

**Beneficios:**
- ✅ Miles de workflows en paralelo
- ✅ Aislamiento (un workflow no puede romper otro)
- ✅ Fallos controlados (supervisors - próximo tutorial)

## Monitoreo de Procesos

```elixir
# Crear un proceso que va a fallar
pid = spawn(fn ->
  :timer.sleep(1000)
  raise "¡Error!"
end)

# Monitorear el proceso
ref = Process.monitor(pid)

# Esperar notificación
receive do
  {:DOWN, ^ref, :process, ^pid, reason} ->
    IO.puts("El proceso murió por: #{inspect(reason)}")
end

# Output:
# El proceso murió por: {%RuntimeError{message: "¡Error!"}, ...}
```

**Esto es la base de los Supervisors** (próximo tutorial).

## Resumen

| Concepto | Descripción | Ejemplo |
|----------|-------------|---------|
| **Proceso** | Unidad de ejecución independiente | `spawn(fn -> ... end)` |
| **PID** | Identificador único de proceso | `#PID<0.123.0>` |
| **send/2** | Enviar mensaje a un proceso | `send(pid, :mensaje)` |
| **receive** | Recibir mensajes (bloquea) | `receive do ... end` |
| **Aislamiento** | Cada proceso tiene memoria privada | No hay variables compartidas |
| **Monitor** | Observar cuando un proceso muere | `Process.monitor(pid)` |

## Ejercicios

### Ejercicio 1: Contador

Crea un proceso que:
1. Empieza en 0
2. Puede recibir `:incrementar` o `:decrementar`
3. Puede recibir `{:consultar, caller_pid}` y responde con el valor actual

<details>
<summary>Ver solución</summary>

```elixir
defmodule Contador do
  def loop(valor) do
    receive do
      :incrementar ->
        loop(valor + 1)

      :decrementar ->
        loop(valor - 1)

      {:consultar, caller} ->
        send(caller, {:valor, valor})
        loop(valor)
    end
  end
end

# Usar
pid = spawn(fn -> Contador.loop(0) end)

send(pid, :incrementar)
send(pid, :incrementar)
send(pid, {:consultar, self()})

receive do
  {:valor, v} -> IO.puts("Valor: #{v}")
end
# Output: Valor: 2
```
</details>

### Ejercicio 2: Worker Pool

Crea 3 procesos "trabajadores" que procesan números (multiplican por 2). El proceso principal envía números a los trabajadores y recibe resultados.

<details>
<summary>Ver solución</summary>

```elixir
defmodule Worker do
  def loop do
    receive do
      {:trabajo, numero, caller} ->
        resultado = numero * 2
        :timer.sleep(100)  # Simular trabajo
        send(caller, {:resultado, resultado})
        loop()
    end
  end
end

# Crear 3 workers
workers = for _ <- 1..3 do
  spawn(fn -> Worker.loop() end)
end

# Enviar trabajo
for {numero, worker} <- Enum.zip(1..6, Stream.cycle(workers)) do
  send(worker, {:trabajo, numero, self()})
end

# Recolectar resultados
for _ <- 1..6 do
  receive do
    {:resultado, res} -> IO.puts("Resultado: #{res}")
  end
end
```
</details>

## Siguiente: GenServers

Los procesos son el building block básico, pero trabajar directamente con `spawn`, `send` y `receive` es tedioso.

En el [próximo tutorial](02-genservers-and-supervision.md), aprenderás sobre **GenServers**: una abstracción que simplifica la creación de procesos con estado.

## Referencias

- [Elixir Guides - Processes](https://elixir-lang.org/getting-started/processes.html)
- [Erlang - The Zen of Erlang](https://ferd.ca/the-zen-of-erlang.html)
- [Saša Jurić - The Soul of Erlang and Elixir](https://www.youtube.com/watch?v=JvBT4XBdoUE)
