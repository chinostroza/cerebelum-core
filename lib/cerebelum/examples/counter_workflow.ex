defmodule Cerebelum.Examples.CounterWorkflow do
  @moduledoc """
  Ejemplo simple de workflow: Contador.

  Este workflow demuestra:
  - Timeline lineal básico
  - Pasar resultados entre steps
  - Acumulación de estado

  ## Flujo

  1. `initialize/1` - Inicializa el contador en 0
  2. `increment/2` - Incrementa el contador en 1
  3. `double/2` - Duplica el valor del contador
  4. `finalize/2` - Retorna el resultado final

  ## Uso

      context = Context.new(CounterWorkflow, %{})
      # Execute workflow...
      # Result: 2 (0 -> 1 -> 2)
  """

  use Cerebelum.Workflow

  workflow do
    timeline do
      initialize() |> increment() |> double() |> finalize()
    end
  end

  @doc """
  Inicializa el contador en 0.

  ## Parámetros

  - `context` - El contexto de ejecución

  ## Retorna

  `{:ok, 0}` - El contador inicial
  """
  def initialize(_context) do
    {:ok, 0}
  end

  @doc """
  Incrementa el contador en 1.

  ## Parámetros

  - `context` - El contexto de ejecución
  - `counter` - El valor actual del contador

  ## Retorna

  `{:ok, counter + 1}` - El contador incrementado
  """
  def increment(_context, {:ok, counter}) do
    {:ok, counter + 1}
  end

  @doc """
  Duplica el valor del contador.

  ## Parámetros

  - `context` - El contexto de ejecución
  - `_init` - Resultado de initialize (ignorado)
  - `counter` - Resultado de increment

  ## Retorna

  `{:ok, counter * 2}` - El contador duplicado
  """
  def double(_context, _init, {:ok, counter}) do
    {:ok, counter * 2}
  end

  @doc """
  Finaliza el workflow retornando el resultado.

  ## Parámetros

  - `context` - El contexto de ejecución
  - `_init` - Resultado de initialize (ignorado)
  - `_inc` - Resultado de increment (ignorado)
  - `result` - Resultado de double

  ## Retorna

  El valor final del contador
  """
  def finalize(_context, _init, _inc, {:ok, result}) do
    {:ok, result}
  end
end
