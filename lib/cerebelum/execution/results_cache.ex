defmodule Cerebelum.Execution.ResultsCache do
  @moduledoc """
  Manages the results cache for workflow execution.

  The cache stores step results as a mapping from step name (atom) to result.
  It is immutable - all operations return a new cache.

  ## Examples

      cache = ResultsCache.new()
      cache = ResultsCache.put(cache, :step1, {:ok, "result"})
      {:ok, result} = ResultsCache.get(cache, :step1)
      #=> {:ok, {:ok, "result"}}
  """

  @type t :: %{atom() => term()}

  @doc """
  Creates a new empty results cache.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> map_size(cache)
      0
  """
  @spec new() :: t()
  def new, do: %{}

  @doc """
  Stores a result for a step.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> cache = Cerebelum.Execution.ResultsCache.put(cache, :step1, {:ok, "result"})
      iex> Cerebelum.Execution.ResultsCache.has?(cache, :step1)
      true
  """
  @spec put(t(), atom(), term()) :: t()
  def put(cache, step_name, result) when is_atom(step_name) do
    Map.put(cache, step_name, result)
  end

  @doc """
  Retrieves a result by step name.

  Returns `{:ok, result}` if found, `:error` if not found.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> cache = Cerebelum.Execution.ResultsCache.put(cache, :step1, "value")
      iex> Cerebelum.Execution.ResultsCache.get(cache, :step1)
      {:ok, "value"}

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> Cerebelum.Execution.ResultsCache.get(cache, :missing)
      :error
  """
  @spec get(t(), atom()) :: {:ok, term()} | :error
  def get(cache, step_name) when is_atom(step_name) do
    Map.fetch(cache, step_name)
  end

  @doc """
  Retrieves a result by step name, raising if not found.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> cache = Cerebelum.Execution.ResultsCache.put(cache, :step1, "value")
      iex> Cerebelum.Execution.ResultsCache.get!(cache, :step1)
      "value"
  """
  @spec get!(t(), atom()) :: term()
  def get!(cache, step_name) when is_atom(step_name) do
    Map.fetch!(cache, step_name)
  end

  @doc """
  Checks if a result exists for a step.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> cache = Cerebelum.Execution.ResultsCache.put(cache, :step1, "value")
      iex> Cerebelum.Execution.ResultsCache.has?(cache, :step1)
      true
      iex> Cerebelum.Execution.ResultsCache.has?(cache, :step2)
      false
  """
  @spec has?(t(), atom()) :: boolean()
  def has?(cache, step_name) when is_atom(step_name) do
    Map.has_key?(cache, step_name)
  end

  @doc """
  Takes multiple results from the cache.

  Returns a new map with only the specified keys.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> cache = cache
      ...>   |> Cerebelum.Execution.ResultsCache.put(:step1, "a")
      ...>   |> Cerebelum.Execution.ResultsCache.put(:step2, "b")
      ...>   |> Cerebelum.Execution.ResultsCache.put(:step3, "c")
      iex> taken = Cerebelum.Execution.ResultsCache.take(cache, [:step1, :step3])
      iex> map_size(taken)
      2
      iex> taken[:step1]
      "a"
      iex> taken[:step3]
      "c"
  """
  @spec take(t(), [atom()]) :: t()
  def take(cache, step_names) when is_list(step_names) do
    Map.take(cache, step_names)
  end

  @doc """
  Clears the cache, returning an empty cache.

  Useful for replay scenarios.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> cache = Cerebelum.Execution.ResultsCache.put(cache, :step1, "value")
      iex> cache = Cerebelum.Execution.ResultsCache.clear(cache)
      iex> map_size(cache)
      0
  """
  @spec clear(t()) :: t()
  def clear(_cache), do: new()

  @doc """
  Returns the number of results in the cache.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> cache = cache
      ...>   |> Cerebelum.Execution.ResultsCache.put(:step1, "a")
      ...>   |> Cerebelum.Execution.ResultsCache.put(:step2, "b")
      iex> Cerebelum.Execution.ResultsCache.size(cache)
      2
  """
  @spec size(t()) :: non_neg_integer()
  def size(cache), do: map_size(cache)

  @doc """
  Converts the cache to a list of {step_name, result} tuples.

  ## Examples

      iex> cache = Cerebelum.Execution.ResultsCache.new()
      iex> cache = Cerebelum.Execution.ResultsCache.put(cache, :step1, "value")
      iex> list = Cerebelum.Execution.ResultsCache.to_list(cache)
      iex> length(list)
      1
      iex> {:step1, "value"} in list
      true
  """
  @spec to_list(t()) :: [{atom(), term()}]
  def to_list(cache), do: Map.to_list(cache)
end
