# Native Elixir Workflow Example

Este ejemplo demuestra cómo crear y ejecutar workflows usando la sintaxis DSL nativa de Cerebelum en Elixir.

## Archivos

- **workflow.ex** - Módulo del workflow usando `use Cerebelum.Workflow` y DSL syntax
- **run.exs** - Script para ejecutar el workflow y mostrar resultados

## Cómo Ejecutar

Desde el directorio raíz del proyecto:

```bash
MIX_ENV=dev mix run examples/cerebelum-native-elixir/run.exs
```

El script:
1. Carga el workflow
2. Lo ejecuta a través de la API de Cerebelum
3. Espera a que complete
4. Muestra los resultados

## Workflow

Este workflow implementa un proceso de onboarding de usuarios con 3 pasos:

```
Input: %{user_id: 123}
  ↓
fetch_user → %{id: 123, name: "User123", email: "...", score: 85}
  ↓
check_eligibility → %{...score: 85, eligible: true}
  ↓
send_notification → "✉️  Notification sent to user123@example.com"
```

### Definición del Workflow

```elixir
workflow do
  timeline do
    fetch_user() |> check_eligibility() |> send_notification()
  end
end
```

### Pasos del Workflow

1. **fetch_user** - Obtiene datos del usuario
   - Input: `context` con `user_id` en inputs
   - Output: `{:ok, %{id, name, email, score}}`

2. **check_eligibility** - Verifica elegibilidad basado en score
   - Input: `context` + resultado de `fetch_user`
   - Output: `{:ok, %{...user, eligible: boolean}}`

3. **send_notification** - Envía notificación si es elegible
   - Input: `context` + resultado de `fetch_user` + resultado de `check_eligibility`
   - Output: `{:ok, message}`

## Características del DSL

- **Timeline**: Define el orden de ejecución usando pipe operator (`|>`)
- **Steps**: Funciones que reciben contexto + resultados de pasos anteriores
- **Data Flow**: Cada paso recibe automáticamente los resultados de todos los pasos previos
- **Pattern Matching**: Usa pattern matching de Elixir para destructurar resultados

## Diferencias con Python SDK

Este ejemplo usa la sintaxis nativa de Elixir, mientras que el Python SDK (`../examples/workflow_example.py`) usa la API de construcción de workflows del SDK de Python.

Ambos producen el mismo resultado, pero este ejemplo ejecuta directamente en Elixir sin necesidad de workers externos.
