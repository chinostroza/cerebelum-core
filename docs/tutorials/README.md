# Cerebelum Core - Tutorials

Este directorio contiene tutoriales paso a paso para entender cómo funciona Cerebelum Core internamente.

## Serie: Fundamentos de Elixir/OTP y Event Sourcing

Si eres nuevo en Elixir/OTP o en Event Sourcing, estos tutoriales te guiarán desde los conceptos básicos hasta entender completamente cómo Cerebelum maneja workflows, fallos y recuperación.

### 1. [Understanding Processes](01-understanding-processes.md)
**Tiempo estimado:** 15 minutos

Aprende qué son los procesos en Elixir y cómo funcionan:
- Modelo de actores
- Memoria aislada
- Comunicación por mensajes
- Paralelismo masivo

### 2. [GenServers and Supervision](02-genservers-and-supervision.md)
**Tiempo estimado:** 20 minutos

Entiende los building blocks de OTP:
- Qué es un GenServer
- Cómo funcionan los Supervisors
- Supervision trees
- Restart strategies

### 3. [Event Sourcing Fundamentals](03-event-sourcing.md)
**Tiempo estimado:** 25 minutos

La clave para workflows resilientes:
- Por qué Event Sourcing vs State
- Cómo reconstruir estado desde eventos
- Event Store y persistencia
- Snapshots y optimización

### 4. [Fault Tolerance Model](04-fault-tolerance.md)
**Tiempo estimado:** 30 minutos

El modelo completo de manejo de fallos en Cerebelum:
- Tipos de fallos (controlados, crashes, timeouts)
- Estrategias de recuperación
- Retry policies
- Saga pattern para transacciones distribuidas
- Disaster recovery (VM crash, network partition)

### 5. [Workflow Code-First Approach](05-workflow-code-first.md)
**Tiempo estimado:** 20 minutos

Cómo escribir workflows con código Elixir:
- Funciones como nodos
- Compile-time validation
- Type safety con Dialyzer
- Testing workflows
- Debugging y time-travel

---

## Serie: Implementación Práctica (Hands-On)

Tutoriales donde **TÚ construyes** Cerebelum paso a paso.

### 6. [Construyendo el DSL - Parte 1](06-building-the-dsl-part-1.md)
**Tiempo estimado:** 45 minutos

Implementa el macro `workflow()` desde cero:
- El macro `__using__/1`
- Module attributes para metadata
- Parser de `timeline()`
- Validación en compile-time

### 7. Construyendo el DSL - Parte 2 *(Próximamente)*
**Tiempo estimado:** 50 minutos

Implementa `diverge()` y `branch()`:
- Parser de patrones de error
- Conditional branching
- Retry policies

### 8. Execution Engine Básico *(Próximamente)*
**Tiempo estimado:** 60 minutos

Implementa el ejecutor de workflows:
- GenServer para ejecutar workflows
- Context management
- Results cache

### 9. Event Sourcing Engine *(Próximamente)*
**Tiempo estimado:** 50 minutos

Implementa persistencia de eventos:
- Event Store con Ecto
- Replay de workflows
- Snapshots

### 10. Time-Travel Debugging *(Próximamente)*
**Tiempo estimado:** 40 minutos

Implementa debugging avanzado:
- Step-by-step execution
- State inspection
- Breakpoints

## Orden recomendado

**Para principiantes en Elixir:**
1 → 2 → 3 → 4 → 5

**Si ya conoces Elixir/OTP:**
3 → 4 → 5

**Si solo quieres escribir workflows:**
5 (y lee 4 cuando tengas problemas de fallos)

**Para implementar Cerebelum tú mismo (Hands-On):**
1 → 2 → 3 → 4 → 5 → **6 → 7 → 8 → 9 → 10**

**Si quieres saltar directo a la implementación:**
5 → **6 → 7 → 8 → 9 → 10**

## Recursos adicionales

- [Elixir School - OTP Concurrency](https://elixirschool.com/en/lessons/advanced/otp_concurrency)
- [Learn You Some Erlang - Supervisors](https://learnyousomeerlang.com/supervisors)
- [Event Sourcing - Martin Fowler](https://martinfowler.com/eaaDev/EventSourcing.html)
- [Temporal.io Docs](https://docs.temporal.io/) (inspiración para Cerebelum)

## Ejemplos completos

Todos los tutoriales incluyen ejemplos ejecutables que puedes encontrar en:
```
cerebelum-core/examples/tutorials/
```

Para ejecutar los ejemplos:
```bash
cd cerebelum-core
mix run examples/tutorials/01_processes.exs
mix run examples/tutorials/02_genservers.exs
# etc...
```
