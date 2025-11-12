defmodule Cerebelum.ResultsCache do
  @moduledoc """
  Cache inmutable para almacenar resultados de steps en un workflow.

  El ResultsCache es un Map simple que almacena los resultados de cada step
  ejecutado, permitiendo que steps posteriores accedan a resultados previos.

  ## Ejemplo

      iex> cache = ResultsCache.new()
      iex> cache = ResultsCache.put(cache, :start, %{order_id: "123"})
      iex> cache = ResultsCache.put(cache, :validate, %{valid: true})
      iex> ResultsCache.get(cache, :start)
      {:ok, %{order_id: "123"}}

  ## Uso en Workflows

  Con la sintaxis final, cada step recibe el cache completo:

      def validate_order(ctx, %{start: start_result}) do
        # start_result viene del ResultsCache
        order_id = start_result.order_id
        # ...
      end
  """

  @type t :: %{optional(atom()) => any()}

  @doc """
  Crea un nuevo ResultsCache vacío.

  ## Ejemplo

      iex> ResultsCache.new()
      %{}
  """
  @spec new() :: t()
  def new, do: %{}

  @doc """
  Almacena el resultado de un step en el cache.

  ## Ejemplos

      iex> cache = ResultsCache.new()
      iex> cache = ResultsCache.put(cache, :start, %{order_id: "123"})
      iex> cache[:start]
      %{order_id: "123"}

      iex> cache = ResultsCache.new()
      iex> cache = cache |> ResultsCache.put(:start, %{v: 1}) |> ResultsCache.put(:validate, %{v: 2})
      iex> cache[:validate]
      %{v: 2}
  """
  @spec put(t(), atom(), any()) :: t()
  def put(cache, step_name, result) do
    Map.put(cache, step_name, result)
  end

  @doc """
  Obtiene el resultado de un step.

  Retorna `{:ok, result}` si existe, `:error` si no.

  ## Ejemplos

      iex> cache = ResultsCache.new() |> ResultsCache.put(:start, %{value: 42})
      iex> ResultsCache.get(cache, :start)
      {:ok, %{value: 42}}

      iex> cache = ResultsCache.new()
      iex> ResultsCache.get(cache, :nonexistent)
      :error
  """
  @spec get(t(), atom()) :: {:ok, any()} | :error
  def get(cache, step_name) do
    case Map.fetch(cache, step_name) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  @doc """
  Obtiene el resultado de un step, lanzando excepción si no existe.

  ## Ejemplos

      iex> cache = ResultsCache.new() |> ResultsCache.put(:start, %{value: 42})
      iex> ResultsCache.get!(cache, :start)
      %{value: 42}

      iex> cache = ResultsCache.new()
      iex> ResultsCache.get!(cache, :nonexistent)
      ** (KeyError) key :nonexistent not found in: %{}
  """
  @spec get!(t(), atom()) :: any()
  def get!(cache, step_name) do
    Map.fetch!(cache, step_name)
  end

  @doc """
  Verifica si un step ha sido ejecutado.

  ## Ejemplos

      iex> cache = ResultsCache.new() |> ResultsCache.put(:start, %{})
      iex> ResultsCache.has_step?(cache, :start)
      true

      iex> cache = ResultsCache.new()
      iex> ResultsCache.has_step?(cache, :start)
      false
  """
  @spec has_step?(t(), atom()) :: boolean()
  def has_step?(cache, step_name) do
    Map.has_key?(cache, step_name)
  end

  @doc """
  Obtiene todos los resultados hasta un step específico (inclusive).

  Útil para pasar solo los resultados relevantes a un step.

  ## Parámetros

  - `cache` - El cache completo
  - `step_name` - El step hasta el cual obtener resultados
  - `steps_order` - Lista ordenada de steps del timeline

  ## Ejemplos

      iex> cache = ResultsCache.new()
      ...>   |> ResultsCache.put(:start, %{v: 1})
      ...>   |> ResultsCache.put(:validate, %{v: 2})
      ...>   |> ResultsCache.put(:charge, %{v: 3})
      iex> ResultsCache.get_up_to(cache, :validate, [:start, :validate, :charge])
      %{start: %{v: 1}, validate: %{v: 2}}
  """
  @spec get_up_to(t(), atom(), list(atom())) :: t()
  def get_up_to(cache, step_name, steps_order) do
    case Enum.find_index(steps_order, &(&1 == step_name)) do
      nil ->
        # Step no encontrado en el order, retornar vacío
        %{}

      index ->
        # Tomar steps hasta ese índice (inclusive)
        steps_to_include = Enum.take(steps_order, index + 1)

        # Filtrar cache para incluir solo esos steps
        Map.take(cache, steps_to_include)
    end
  end

  @doc """
  Retorna la lista de steps que han sido ejecutados.

  ## Ejemplos

      iex> cache = ResultsCache.new()
      ...>   |> ResultsCache.put(:start, %{})
      ...>   |> ResultsCache.put(:validate, %{})
      iex> ResultsCache.executed_steps(cache)
      [:start, :validate]  # O [:validate, :start] (orden no garantizado)
  """
  @spec executed_steps(t()) :: list(atom())
  def executed_steps(cache) do
    Map.keys(cache)
  end
end
