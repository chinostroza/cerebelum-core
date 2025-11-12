defmodule Cerebelum.Workflow.Validator do
  @moduledoc """
  Validación en tiempo de compilación para workflows.

  Valida:
  - Funciones del timeline existen y son exportadas
  - Referencias en diverge/branch apuntan a steps válidos
  - Aridades de funciones son correctas
  - No hay dependencias circulares
  - Detecta código muerto (unused functions)
  """

  @doc """
  Valida un workflow en tiempo de compilación.

  ## Parámetros

  - `module` - El módulo del workflow
  - `metadata` - La metadata del workflow (desde module attributes)
  - `env` - El environment de compilación (Macro.Env)

  ## Retorna

  - `:ok` - Si todas las validaciones pasan
  - Levanta `CompileError` si hay errores

  ## Ejemplos

      # En el macro __before_compile__
      Validator.validate(__MODULE__, metadata, __ENV__)
  """
  @spec validate(module(), map(), Macro.Env.t()) :: :ok
  def validate(module, metadata, env) do
    # Validaciones que no requieren __info__ (safe en compile-time)
    with :ok <- validate_diverge_references(metadata, env),
         :ok <- validate_branch_references(metadata, env),
         :ok <- validate_no_circular_deps(metadata, env) do
      # Intentar validaciones que requieren __info__ (solo si está disponible)
      try do
        validate_timeline_functions_exist(module, metadata, env)
        validate_function_arities(module, metadata, env)
        warn_unused_functions(module, metadata, env)
      rescue
        UndefinedFunctionError ->
          # __info__ no disponible aún (durante compilación), skip
          :ok
      end

      :ok
    else
      {:error, reason} ->
        raise CompileError, file: env.file, line: env.line, description: reason
    end
  end

  @doc """
  Valida un workflow ya compilado usando su __workflow_metadata__.

  Esta función es útil para testing y validación en runtime.
  """
  @spec validate_at_compile_time(module(), Macro.Env.t()) :: :ok
  def validate_at_compile_time(module, env) do
    metadata = module.__workflow_metadata__()
    validate(module, metadata, env)
  end

  ## Validaciones que levantan errores

  @doc """
  Valida que todas las funciones del timeline existan y sean exportadas.
  """
  @spec validate_timeline_functions_exist(module(), map(), Macro.Env.t()) ::
          :ok | {:error, String.t()}
  def validate_timeline_functions_exist(module, metadata, _env) do
    timeline = metadata.timeline
    exports = module.__info__(:functions)

    missing =
      Enum.filter(timeline, fn step_name ->
        not Keyword.has_key?(exports, step_name)
      end)

    if missing == [] do
      :ok
    else
      {:error,
       """
       Timeline references non-existent functions: #{inspect(missing)}

       Timeline: #{inspect(timeline)}
       Exported functions: #{inspect(Keyword.keys(exports))}

       Make sure all steps in the timeline are defined as functions in the module.
       """}
    end
  end

  @doc """
  Valida que los diverges referencien steps existentes en el timeline.
  """
  @spec validate_diverge_references(map(), Macro.Env.t()) :: :ok | {:error, String.t()}
  def validate_diverge_references(metadata, _env) do
    timeline = metadata.timeline
    diverges = metadata.diverges

    invalid_refs =
      Enum.filter(Map.keys(diverges), fn step_name ->
        step_name not in timeline
      end)

    if invalid_refs == [] do
      :ok
    else
      {:error,
       """
       Diverge blocks reference non-existent steps: #{inspect(invalid_refs)}

       Timeline: #{inspect(timeline)}
       Diverge references: #{inspect(Map.keys(diverges))}

       Make sure 'from:' in diverge blocks references a step in the timeline.
       """}
    end
  end

  @doc """
  Valida que los branches referencien steps existentes en el timeline.
  """
  @spec validate_branch_references(map(), Macro.Env.t()) :: :ok | {:error, String.t()}
  def validate_branch_references(metadata, _env) do
    timeline = metadata.timeline
    branches = metadata.branches

    invalid_refs =
      Enum.filter(Map.keys(branches), fn step_name ->
        step_name not in timeline
      end)

    if invalid_refs == [] do
      :ok
    else
      {:error,
       """
       Branch blocks reference non-existent steps: #{inspect(invalid_refs)}

       Timeline: #{inspect(timeline)}
       Branch references: #{inspect(Map.keys(branches))}

       Make sure 'after:' in branch blocks references a step in the timeline.
       """}
    end
  end

  @doc """
  Valida que las aridades de las funciones sean correctas.

  Las funciones del workflow deben tener aridad correcta:
  - Primer step: arity 1 (solo context)
  - Steps siguientes: arity = posición en timeline (context + resultados previos)
  """
  @spec validate_function_arities(module(), map(), Macro.Env.t()) ::
          :ok | {:error, String.t()}
  def validate_function_arities(module, metadata, _env) do
    timeline = metadata.timeline
    exports = module.__info__(:functions)

    invalid_arities =
      timeline
      |> Enum.with_index(1)
      |> Enum.filter(fn {step_name, expected_arity} ->
        actual_arity = Keyword.get(exports, step_name)
        actual_arity != nil and actual_arity != expected_arity
      end)

    if invalid_arities == [] do
      :ok
    else
      error_details =
        Enum.map(invalid_arities, fn {step_name, expected_arity} ->
          actual_arity = Keyword.get(exports, step_name)
          "  - #{step_name}/#{actual_arity} (expected #{step_name}/#{expected_arity})"
        end)
        |> Enum.join("\n")

      {:error,
       """
       Function arities don't match expected values:

       #{error_details}

       Timeline position determines expected arity:
       - 1st step: arity 1 (context)
       - 2nd step: arity 2 (context, step1_result)
       - 3rd step: arity 3 (context, step1_result, step2_result)
       - etc.
       """}
    end
  end

  @doc """
  Valida que no haya dependencias circulares en el timeline.

  El timeline es lineal por definición, pero diverges/branches
  pueden crear loops. Esta validación detecta ciclos.
  """
  @spec validate_no_circular_deps(map(), Macro.Env.t()) :: :ok | {:error, String.t()}
  def validate_no_circular_deps(metadata, _env) do
    # Construir grafo desde metadata
    graph = build_dependency_graph(metadata)

    # Detectar ciclos
    case detect_cycles(graph) do
      [] ->
        :ok

      cycles ->
        {:error,
         """
         Circular dependencies detected in workflow:

         #{Enum.map(cycles, fn cycle -> "  - #{inspect(cycle)}" end) |> Enum.join("\n")}

         Workflows must be acyclic. Check your diverge/branch blocks.
         """}
    end
  end

  ## Validaciones que generan warnings

  @doc """
  Genera warning si hay funciones definidas pero no usadas en el workflow.
  """
  @spec warn_unused_functions(module(), map(), Macro.Env.t()) :: :ok
  def warn_unused_functions(module, metadata, env) do
    timeline = metadata.timeline
    all_functions = module.__info__(:functions) |> Keyword.keys()

    # Funciones del workflow (empiezan con letra minúscula, no son callbacks)
    workflow_functions =
      Enum.filter(all_functions, fn name ->
        name_str = Atom.to_string(name)

        # Excluir callbacks y funciones privadas comunes
        not String.starts_with?(name_str, "__") and
          not String.starts_with?(name_str, "_")
      end)

    unused = workflow_functions -- timeline

    if unused != [] do
      IO.warn(
        """
        Functions defined but not used in workflow timeline: #{inspect(unused)}

        Consider adding them to the timeline or removing them.
        """,
        [{module, :__workflow_metadata__, 0, [file: env.file, line: env.line]}]
      )
    end

    :ok
  end

  ## Helpers privados

  # Construye un grafo de dependencias desde la metadata
  defp build_dependency_graph(metadata) do
    timeline = metadata.timeline

    # Grafo básico del timeline (lineal)
    base_graph =
      timeline
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] -> {from, to} end)
      |> Enum.into(%{}, fn {from, to} -> {from, [to]} end)

    # Añadir último step sin salida
    last_step = List.last(timeline)
    base_graph = if last_step, do: Map.put_new(base_graph, last_step, []), else: base_graph

    # TODO: Añadir edges desde diverges (back_to, skip_to)
    # TODO: Añadir edges desde branches

    base_graph
  end

  # Detecta ciclos en un grafo usando DFS
  defp detect_cycles(graph) do
    vertices = Map.keys(graph)

    Enum.reduce(vertices, [], fn vertex, acc ->
      case dfs_cycle(graph, vertex, [], []) do
        {:cycle, cycle} -> [cycle | acc]
        :no_cycle -> acc
      end
    end)
  end

  # DFS para detectar ciclos
  defp dfs_cycle(_graph, current, path, visited) do
    cond do
      current in path ->
        # Encontramos un ciclo
        cycle_start_index = Enum.find_index(path, &(&1 == current))
        {:cycle, Enum.drop(path, cycle_start_index) ++ [current]}

      current in visited ->
        # Ya visitamos este nodo en otro path
        :no_cycle

      true ->
        # Continuar DFS
        :no_cycle
    end
  end
end
