defmodule Cerebelum.Workflow.Introspection do
  @moduledoc """
  Introspección profunda de funciones de workflow usando BEAM bytecode.

  Extrae:
  - Patrones de parámetros
  - Atom keys desde map patterns
  - Context parameter
  - Guards
  """

  @doc """
  Introspecciona los parámetros de una función.

  ## Parámetros

  - `module` - El módulo del workflow
  - `function_name` - Nombre de la función
  - `arity` - Aridad de la función

  ## Retorna

  - `{:ok, params_info}` - Info sobre los parámetros
  - `{:error, reason}` - Si no se puede introspeccionar

  ## Ejemplos

      iex> Introspection.introspect_params(MyWorkflow, :step1, 1)
      {:ok, %{context: true, dependencies: []}}

      iex> Introspection.introspect_params(MyWorkflow, :step2, 2)
      {:ok, %{context: true, dependencies: [:step1]}}
  """
  @spec introspect_params(module(), atom(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def introspect_params(module, function_name, arity) do
    case get_abstract_code(module) do
      {:ok, abstract_code} ->
        case find_function(abstract_code, function_name, arity) do
          {:ok, function_ast} ->
            {:ok, extract_params_info(function_ast)}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Obtiene el abstract code (AST) del bytecode de un módulo.

  ## Parámetros

  - `module` - El módulo a introspeccionar

  ## Retorna

  - `{:ok, abstract_code}` - El AST del módulo
  - `{:error, reason}` - Si no está disponible (ej: compilado sin debug_info)
  """
  @spec get_abstract_code(module()) :: {:ok, term()} | {:error, term()}
  def get_abstract_code(module) do
    # Primero intentar obtener directamente del módulo cargado
    case :code.get_object_code(module) do
      {^module, beam_binary, _filename} ->
        # Leer el abstract code del binary
        case :beam_lib.chunks(beam_binary, [:abstract_code]) do
          {:ok, {^module, [{:abstract_code, {_version, abstract_code}}]}} ->
            {:ok, abstract_code}

          {:error, :beam_lib, {:missing_chunk, _, :abstract_code}} ->
            {:error, :no_debug_info}

          {:error, reason} ->
            {:error, reason}
        end

      :error ->
        {:error, :module_not_loaded}
    end
  end

  @doc """
  Encuentra la definición de una función en el abstract code.

  ## Parámetros

  - `abstract_code` - AST del módulo
  - `function_name` - Nombre de la función
  - `arity` - Aridad de la función

  ## Retorna

  - `{:ok, function_ast}` - AST de la función
  - `{:error, :not_found}` - Si no existe
  """
  @spec find_function(list(), atom(), non_neg_integer()) :: {:ok, term()} | {:error, :not_found}
  def find_function(abstract_code, function_name, arity) do
    result =
      Enum.find_value(abstract_code, fn
        {:function, _line, ^function_name, ^arity, clauses} ->
          {:ok, clauses}

        _ ->
          nil
      end)

    case result do
      nil -> {:error, :not_found}
      found -> found
    end
  end

  @doc """
  Extrae información sobre los parámetros desde el AST de una función.

  ## Parámetros

  - `function_clauses` - Cláusulas de la función (puede tener múltiples pattern matches)

  ## Retorna

  Map con:
  - `:context` - Si el primer parámetro es context (siempre true en workflows)
  - `:dependencies` - Lista de atoms extraídos de map patterns
  - `:clauses` - Número de cláusulas

  ## Ejemplos

      # Para: def step(context, %{prev: _})
      %{context: true, dependencies: [:prev], clauses: 1}

      # Para: def step(context)
      %{context: true, dependencies: [], clauses: 1}
  """
  @spec extract_params_info(list()) :: map()
  def extract_params_info(clauses) do
    # Tomar la primera cláusula para análisis
    # (en workflows, típicamente solo hay una cláusula por función)
    first_clause = List.first(clauses) || []

    dependencies = extract_dependencies_from_clause(first_clause)

    %{
      context: true,  # Siempre esperamos context como primer parámetro
      dependencies: dependencies,
      clauses: length(clauses)
    }
  end

  # Helpers privados

  # Extrae dependencias (atoms) de una cláusula de función
  defp extract_dependencies_from_clause({:clause, _line, params, _guards, _body}) do
    # Típicamente params es [context, map_pattern] o solo [context]
    case params do
      [_context] ->
        # Solo context, sin dependencias
        []

      [_context, map_pattern] ->
        # Extraer atoms del map pattern
        extract_atoms_from_pattern(map_pattern)

      [_context | rest] ->
        # Más de 2 params - extraer de todos excepto el primero
        rest
        |> Enum.flat_map(&extract_atoms_from_pattern/1)
        |> Enum.uniq()
    end
  end

  defp extract_dependencies_from_clause(_), do: []

  # Extrae atoms desde un patrón (especialmente map patterns)
  defp extract_atoms_from_pattern({:map, _line, fields}) do
    Enum.flat_map(fields, fn
      {:map_field_exact, _line, {:atom, _line2, key}, _value} ->
        [key]

      _ ->
        []
    end)
  end

  # Variable simple (ej: `result`, `step1`)
  defp extract_atoms_from_pattern({:var, _line, name}) do
    # Convertir nombre de variable a atom
    # Ej: 'step1' -> :step1
    [name |> Atom.to_string() |> String.downcase() |> String.to_atom()]
  rescue
    _ -> []
  end

  # Match pattern (_)
  defp extract_atoms_from_pattern({:match, _line, pattern, _value}) do
    extract_atoms_from_pattern(pattern)
  end

  # Otros patrones
  defp extract_atoms_from_pattern(_), do: []
end
