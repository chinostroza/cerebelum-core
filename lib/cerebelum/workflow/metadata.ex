defmodule Cerebelum.Workflow.Metadata do
  @moduledoc """
  Extrae y analiza metadata de workflows.

  Proporciona funciones para:
  - Extraer metadata completa de un workflow
  - Construir el grafo de dependencias entre steps
  - Introspección de funciones y sus parámetros
  """

  @doc """
  Extrae toda la metadata de un workflow module.

  ## Parámetros

  - `module` - El módulo del workflow (ej: `MyWorkflow`)

  ## Retorna

  Un map con:
  - `:module` - El módulo del workflow
  - `:timeline` - Lista ordenada de steps
  - `:diverges` - Map de diverge definitions
  - `:branches` - Map de branch definitions
  - `:version` - Version hash del bytecode
  - `:functions` - Map de metadata por función
  - `:graph` - Grafo de dependencias

  ## Ejemplos

      iex> Metadata.extract(MyWorkflow)
      %{
        module: MyWorkflow,
        timeline: [:step1, :step2, :step3],
        diverges: %{...},
        branches: %{...},
        version: "abc123...",
        functions: %{...},
        graph: %{...}
      }
  """
  @spec extract(module()) :: map()
  def extract(module) do
    metadata = module.__workflow_metadata__()

    %{
      module: module,
      timeline: metadata.timeline,
      diverges: metadata.diverges,
      branches: metadata.branches,
      version: metadata.version,
      functions: extract_functions(module, metadata.timeline),
      graph: build_graph(metadata)
    }
  end

  @doc """
  Extrae información sobre las funciones del timeline.

  ## Parámetros

  - `module` - El módulo del workflow
  - `timeline` - Lista de steps del timeline

  ## Retorna

  Map de `step_name => function_info`
  """
  @spec extract_functions(module(), [atom()]) :: %{atom() => map()}
  def extract_functions(module, timeline) do
    Enum.map(timeline, fn function_name ->
      {function_name, introspect_function(module, function_name)}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Introspecciona una función específica del workflow.

  ## Parámetros

  - `module` - El módulo del workflow
  - `function_name` - El nombre de la función (atom)

  ## Retorna

  Map con:
  - `:arity` - Aridad de la función
  - `:exported?` - Si la función está exportada
  - `:exists?` - Si la función existe en el módulo
  """
  @spec introspect_function(module(), atom()) :: map()
  def introspect_function(module, function_name) do
    # Buscar la función en las exports del módulo
    exports = module.__info__(:functions)

    case List.keyfind(exports, function_name, 0) do
      {^function_name, arity} ->
        %{
          name: function_name,
          arity: arity,
          exported?: true,
          exists?: true
        }

      nil ->
        %{
          name: function_name,
          arity: nil,
          exported?: false,
          exists?: false
        }
    end
  end

  @doc """
  Construye un grafo de dependencias desde la metadata del workflow.

  El grafo representa las transiciones posibles entre steps:
  - Timeline: step1 -> step2 -> step3
  - Diverge: stepX -> [:retry, :failed, :continue]
  - Branch: stepY -> [:high_path, :low_path]

  ## Parámetros

  - `metadata` - Metadata del workflow (de `__workflow_metadata__/0`)

  ## Retorna

  Map representando el grafo:
  ```
  %{
    step_name => %{
      next: [next_steps],
      diverge_actions: [...],
      branch_actions: [...]
    }
  }
  ```
  """
  @spec build_graph(map()) :: map()
  def build_graph(metadata) do
    timeline = metadata.timeline
    diverges = metadata.diverges
    branches = metadata.branches

    # Construir grafo desde el timeline (flujo lineal)
    graph = build_timeline_graph(timeline)

    # Añadir edges desde diverges
    graph = add_diverge_edges(graph, diverges)

    # Añadir edges desde branches
    graph = add_branch_edges(graph, branches)

    graph
  end

  # Helpers privados

  defp build_timeline_graph([]), do: %{}
  defp build_timeline_graph([_single]), do: %{}

  defp build_timeline_graph(timeline) do
    timeline
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [current, next] ->
      {current, %{next: [next], diverge_actions: [], branch_actions: []}}
    end)
    |> Enum.into(%{})
    |> Map.put(List.last(timeline), %{next: [], diverge_actions: [], branch_actions: []})
  end

  defp add_diverge_edges(graph, diverges) do
    Enum.reduce(diverges, graph, fn {step_name, patterns}, acc ->
      # Extraer todas las acciones posibles de los patrones
      actions = extract_actions_from_patterns(patterns)

      Map.update(acc, step_name, %{next: [], diverge_actions: actions, branch_actions: []}, fn existing ->
        %{existing | diverge_actions: actions}
      end)
    end)
  end

  defp add_branch_edges(graph, branches) do
    Enum.reduce(branches, graph, fn {step_name, conditions}, acc ->
      # Extraer todas las acciones posibles de las condiciones
      actions = extract_actions_from_conditions(conditions)

      Map.update(acc, step_name, %{next: [], diverge_actions: [], branch_actions: actions}, fn existing ->
        %{existing | branch_actions: actions}
      end)
    end)
  end

  defp extract_actions_from_patterns(patterns) do
    Enum.map(patterns, fn {_pattern, action} -> action end)
    |> Enum.uniq()
  end

  defp extract_actions_from_conditions(conditions) do
    Enum.map(conditions, fn {_condition, action} -> action end)
    |> Enum.uniq()
  end
end
