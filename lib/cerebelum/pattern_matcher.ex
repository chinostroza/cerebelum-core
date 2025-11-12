defmodule Cerebelum.PatternMatcher do
  @moduledoc """
  Pattern matcher para evaluar patrones en `diverge()` y `branch()`.

  Soporta:
  - Atoms exactos: `:timeout`
  - Wildcards: `_` matchea cualquier valor
  - Tuples: `{:error, _}` matchea tuples con wildcards
  - Maps: `%{status: _}` matchea maps con wildcards
  - Nested structures: `{:error, {:validation, _}}`

  ## Ejemplos

      iex> patterns = [{:timeout, :retry}, {{:error, :_}, :failed}]
      iex> PatternMatcher.match(patterns, :timeout)
      {:ok, :retry}

      iex> PatternMatcher.match(patterns, {:error, :network})
      {:ok, :failed}

      iex> PatternMatcher.match(patterns, :unknown)
      :no_match
  """

  @doc """
  Evalúa una lista de patrones contra un valor.

  Retorna la acción asociada al primer patrón que matchee,
  o `:no_match` si ninguno matchea.

  ## Parámetros

  - `patterns` - Lista de `{pattern, action}` tuples
  - `value` - Valor a matchear

  ## Ejemplos

      iex> PatternMatcher.match([{:timeout, :retry}], :timeout)
      {:ok, :retry}

      iex> PatternMatcher.match([{:timeout, :retry}], :invalid)
      :no_match
  """
  @spec match([{pattern :: any(), action :: any()}], value :: any()) ::
          {:ok, any()} | :no_match
  def match([], _value), do: :no_match

  def match([{pattern, action} | rest], value) do
    if matches?(pattern, value) do
      {:ok, action}
    else
      match(rest, value)
    end
  end

  @doc """
  Verifica si un patrón matchea un valor.

  ## Ejemplos

      iex> PatternMatcher.matches?(:timeout, :timeout)
      true

      iex> PatternMatcher.matches?({:error, :_}, {:error, :network})
      true

      iex> PatternMatcher.matches?(:_, :anything)
      true
  """
  @spec matches?(pattern :: any(), value :: any()) :: boolean()
  # Wildcard siempre matchea
  def matches?(:_, _value), do: true

  # Atoms exactos
  def matches?(pattern, value) when is_atom(pattern) and is_atom(value) do
    pattern == value
  end

  # Tuples
  def matches?(pattern, value) when is_tuple(pattern) and is_tuple(value) do
    tuple_size(pattern) == tuple_size(value) and
      matches_tuple_elements?(
        Tuple.to_list(pattern),
        Tuple.to_list(value)
      )
  end

  # Maps
  def matches?(pattern, value) when is_map(pattern) and is_map(value) do
    Enum.all?(pattern, fn {key, pattern_value} ->
      Map.has_key?(value, key) and matches?(pattern_value, Map.get(value, key))
    end)
  end

  # Listas
  def matches?(pattern, value) when is_list(pattern) and is_list(value) do
    length(pattern) == length(value) and
      Enum.zip(pattern, value)
      |> Enum.all?(fn {p, v} -> matches?(p, v) end)
  end

  # Números, strings, etc - igualdad exacta
  def matches?(pattern, value) do
    pattern == value
  end

  # Helpers privados

  defp matches_tuple_elements?([], []), do: true

  defp matches_tuple_elements?([pattern_elem | p_rest], [value_elem | v_rest]) do
    matches?(pattern_elem, value_elem) and
      matches_tuple_elements?(p_rest, v_rest)
  end

  defp matches_tuple_elements?(_, _), do: false
end
