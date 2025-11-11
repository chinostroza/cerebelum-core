# Tutorial 6: Construyendo el DSL - Parte 1: El Macro `workflow()`

**Tiempo estimado:** 45 minutos
**Prerrequisitos:** [Tutorial 5 - Workflow Code-First](05-workflow-code-first.md)

## Introducción

En este tutorial vas a **implementar el macro `workflow()`** desde cero. Al final, tendrás un módulo que permite escribir:

```elixir
defmodule MyWorkflow do
  use Cerebelum.Workflow

  workflow() do
    timeline() do
      start() |> process() |> done()
    end
  end
end
```

## Objetivos de Aprendizaje

- Entender cómo funcionan los macros en Elixir
- Implementar `use Cerebelum.Workflow`
- Crear module attributes para almacenar metadata
- Extraer información del AST en compile-time

## Paso 1: Setup del Proyecto

Primero, crea el proyecto Elixir:

```bash
cd /Users/dev/Documents/zea/cerebelum-io/
mix new cerebelum_core
cd cerebelum_core
```

Verifica que compile:

```bash
mix compile
```

## Paso 2: Entendiendo `__using__`

El macro `use Cerebelum.Workflow` se expande a `Cerebelum.Workflow.__using__/1`.

Crea el archivo `lib/cerebelum/workflow.ex`:

```elixir
defmodule Cerebelum.Workflow do
  @moduledoc """
  Macro principal para definir workflows.

  ## Ejemplo

      defmodule MyWorkflow do
        use Cerebelum.Workflow

        workflow() do
          timeline() do
            start() |> process() |> done()
          end
        end
      end
  """

  @doc """
  Macro que se ejecuta cuando haces `use Cerebelum.Workflow`.

  Este macro:
  1. Registra module attributes para guardar metadata
  2. Importa el DSL (timeline, diverge, branch)
  3. Define callbacks necesarios
  """
  defmacro __using__(_opts) do
    quote do
      # TODO: Implementar aquí
    end
  end
end
```

**🎯 Tu tarea:** Implementa `__using__/1` para que:
1. Registre un module attribute `@cerebelum_timeline`
2. Registre un module attribute `@cerebelum_diverges` (accumulate: true)
3. Registre un module attribute `@cerebelum_branches` (accumulate: true)
4. Importe el módulo DSL (que crearemos después)

<details>
<summary>💡 Pista</summary>

Usa `Module.register_attribute/3`:

```elixir
Module.register_attribute(__MODULE__, :cerebelum_timeline, accumulate: false)
Module.register_attribute(__MODULE__, :cerebelum_diverges, accumulate: true)
```
</details>

<details>
<summary>✅ Solución</summary>

```elixir
defmacro __using__(_opts) do
  quote do
    # Registrar attributes para metadata del workflow
    Module.register_attribute(__MODULE__, :cerebelum_timeline, accumulate: false)
    Module.register_attribute(__MODULE__, :cerebelum_diverges, accumulate: true)
    Module.register_attribute(__MODULE__, :cerebelum_branches, accumulate: true)

    # Importar el DSL
    import Cerebelum.Workflow.DSL

    # Callback que será llamado antes de compilar el módulo
    @before_compile Cerebelum.Workflow
  end
end
```
</details>

## Paso 3: El Callback `@before_compile`

El macro `@before_compile` se ejecuta justo antes de que el módulo termine de compilarse. Lo usaremos para generar la función `__workflow_metadata__/0`.

Agrega este código a `Cerebelum.Workflow`:

```elixir
defmacro __before_compile__(_env) do
  quote do
    @doc false
    def __workflow_metadata__ do
      %{
        timeline: @cerebelum_timeline,
        diverges: @cerebelum_diverges |> Enum.into(%{}),
        branches: @cerebelum_branches |> Enum.into(%{}),
        module: __MODULE__
      }
    end
  end
end
```

**🧪 Test:** Crea `test/cerebelum/workflow_test.exs`:

```elixir
defmodule Cerebelum.WorkflowTest do
  use ExUnit.Case, async: true

  defmodule TestWorkflow do
    use Cerebelum.Workflow

    # Por ahora vacío, solo testing del macro
  end

  test "workflow module has metadata function" do
    assert function_exported?(TestWorkflow, :__workflow_metadata__, 0)
  end

  test "metadata returns correct structure" do
    metadata = TestWorkflow.__workflow_metadata__()

    assert is_map(metadata)
    assert Map.has_key?(metadata, :timeline)
    assert Map.has_key?(metadata, :diverges)
    assert Map.has_key?(metadata, :branches)
    assert metadata.module == TestWorkflow
  end
end
```

Ejecuta:
```bash
mix test test/cerebelum/workflow_test.exs
```

## Paso 4: Implementar el DSL Básico

Crea `lib/cerebelum/workflow/dsl.ex`:

```elixir
defmodule Cerebelum.Workflow.DSL do
  @moduledoc """
  DSL para definir workflows con sintaxis Compose-style.
  """

  @doc """
  Macro principal que define un workflow.

  ## Ejemplo

      workflow() do
        timeline() do
          start() |> process() |> done()
        end
      end
  """
  defmacro workflow(do: block) do
    quote do
      # TODO: Parsear el bloque y extraer timeline/diverges/branches
      unquote(block)
    end
  end

  @doc """
  Macro que define la secuencia principal de steps.

  ## Ejemplo

      timeline() do
        start() |> process() |> finish() |> done()
      end
  """
  defmacro timeline(do: block) do
    # TODO: Parsear el pipeline y extraer la lista de funciones
    quote do
      unquote(block)
    end
  end
end
```

**🎯 Tu tarea:** Implementa `workflow/1` para que:
1. Extraiga el bloque `timeline()` del AST
2. Guarde la información en `@cerebelum_timeline`

**💡 Pista:** El AST de `timeline() do ... end` es:
```elixir
{:timeline, [line: 5], [[do: {...}]]}
```

<details>
<summary>✅ Solución Parcial</summary>

```elixir
defmacro workflow(do: block) do
  # Extraer el contenido del bloque
  # Por ahora, solo lo ejecutamos
  # En el próximo tutorial parsearemos el AST completo
  quote do
    unquote(block)
  end
end
```
</details>

## Paso 5: Parser Básico de `timeline()`

Ahora vamos a parsear el pipeline `start() |> process() |> done()`.

El AST de este pipeline es:
```elixir
{:|>, _,
  [{:|>, _, [
    {:start, _, []},
    {:process, _, []}
  ]},
  {:done, _, []}
]}
```

**🎯 Tu tarea:** Implementa una función `parse_pipeline/1` que convierta el AST en una lista de átomos:

```elixir
parse_pipeline(start() |> process() |> done())
# => [:start, :process, :done]
```

<details>
<summary>💡 Pista</summary>

```elixir
defp parse_pipeline({:|>, _, [left, right]}) do
  # Recursivamente parsear el lado izquierdo y agregar el derecho
  parse_pipeline(left) ++ [extract_function_name(right)]
end

defp parse_pipeline({function_name, _, _}) do
  # Caso base: una sola función
  [function_name]
end

defp extract_function_name({name, _, _}), do: name
```
</details>

<details>
<summary>✅ Solución Completa</summary>

```elixir
defmacro timeline(do: block) do
  # Parsear el pipeline y extraer los nombres de funciones
  steps = parse_pipeline(block)

  quote do
    # Guardar en module attribute
    @cerebelum_timeline unquote(steps)
  end
end

# Función helper (privada, no es macro)
defp parse_pipeline({:|>, _, [left, right]}) do
  parse_pipeline(left) ++ [extract_function_name(right)]
end

defp parse_pipeline(single_step) do
  [extract_function_name(single_step)]
end

defp extract_function_name({name, _, _}), do: name
defp extract_function_name(name) when is_atom(name), do: name
```
</details>

## Paso 6: Test Completo

Actualiza el test:

```elixir
defmodule Cerebelum.WorkflowTest do
  use ExUnit.Case, async: true

  defmodule SimpleWorkflow do
    use Cerebelum.Workflow

    workflow() do
      timeline() do
        start() |> process() |> finish() |> done()
      end
    end

    def start(input), do: input
    def process(_ctx, _prev), do: %{}
    def finish(_ctx, _prev), do: %{}
  end

  test "timeline is extracted correctly" do
    metadata = SimpleWorkflow.__workflow_metadata__()

    assert metadata.timeline == [:start, :process, :finish, :done]
  end
end
```

Ejecuta:
```bash
mix test test/cerebelum/workflow_test.exs
```

## Paso 7: Validación en Compile-Time

Ahora vamos a validar que las funciones del timeline existan.

Agrega a `Cerebelum.Workflow`:

```elixir
defmacro __before_compile__(env) do
  # Obtener el timeline del module attribute
  timeline = Module.get_attribute(env.module, :cerebelum_timeline)

  # Validar que todas las funciones existan
  Enum.each(timeline, fn function_name ->
    # Verificar que la función esté definida
    unless function_defined?(env.module, function_name) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: """
        Function #{function_name}/1 or #{function_name}/2 is not defined in #{inspect(env.module)}.

        Timeline requires: #{inspect(timeline)}
        """
    end
  end)

  # Generar __workflow_metadata__/0
  quote do
    def __workflow_metadata__ do
      %{
        timeline: unquote(timeline),
        diverges: @cerebelum_diverges |> Enum.into(%{}),
        branches: @cerebelum_branches |> Enum.into(%{}),
        module: __MODULE__
      }
    end
  end
end

defp function_defined?(module, function_name) do
  # Excluir :start y :done que son especiales
  if function_name in [:start, :done] do
    true
  else
    # Verificar si existe función con arity 1 o 2
    function_exported?(module, function_name, 1) or
      function_exported?(module, function_name, 2)
  end
end
```

**🧪 Test de validación:**

```elixir
test "compile error if function not defined" do
  code = """
  defmodule InvalidWorkflow do
    use Cerebelum.Workflow

    workflow() do
      timeline() do
        start() |> non_existent() |> done()
      end
    end

    def start(input), do: input
  end
  """

  assert_raise CompileError, ~r/Function non_existent/, fn ->
    Code.eval_string(code)
  end
end
```

## Resumen

Has implementado:

✅ El macro `use Cerebelum.Workflow`
✅ Module attributes para metadata
✅ El macro `workflow() do ... end`
✅ El parser de `timeline()`
✅ Validación en compile-time

**Código final completo:** ~100 líneas

## Siguiente Tutorial

En el [Tutorial 7](07-building-the-dsl-part-2.md) implementaremos:
- `diverge()` para manejo de errores
- `branch()` para condicionales
- `retry()` con opciones avanzadas

## Ejercicio Extra

Implementa un validador que detecte ciclos en el timeline:

```elixir
timeline() do
  start() |> process() |> process() |> done()
  # Warning: process appears twice
end
```

<details>
<summary>Ver solución</summary>

```elixir
defp validate_no_duplicates(timeline) do
  duplicates = timeline
    |> Enum.frequencies()
    |> Enum.filter(fn {_step, count} -> count > 1 end)
    |> Enum.map(fn {step, _} -> step end)

  unless Enum.empty?(duplicates) do
    IO.warn("Steps appear multiple times in timeline: #{inspect(duplicates)}")
  end
end
```
</details>

## Referencias

- [Elixir Macros Guide](https://elixir-lang.org/getting-started/meta/macros.html)
- [Meta-programming Elixir (Book)](https://pragprog.com/titles/cmelixir/metaprogramming-elixir/)
- [Module.register_attribute/3](https://hexdocs.pm/elixir/Module.html#register_attribute/3)
