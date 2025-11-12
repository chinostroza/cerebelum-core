defmodule Cerebelum.Workflow.DSL do
  @moduledoc """
  DSL para definir workflows en Cerebelum.

  Provee las macros `workflow`, `timeline`, `diverge`, y `branch`
  para construir workflows de forma declarativa.

  ## Ejemplo

      workflow do
        timeline do
          validate_order() |> process_payment() |> ship_order()
        end

        diverge from: validate_order() do
          {:error, :out_of_stock} -> back_to(:check_inventory)
          {:error, _} -> :failed
        end

        branch after: process_payment(), on: result do
          result.amount > 1000 -> :high_value_path
          true -> :standard_path
        end
      end
  """

  @doc """
  Macro principal que parsea el bloque del workflow.

  Extrae y procesa los bloques `timeline`, `diverge`, y `branch`.
  """
  defmacro workflow(do: block) do
    # Parsear el bloque del workflow
    {timeline_block, diverge_blocks, branch_blocks} = parse_workflow_block(block)

    quote do
      # Procesar timeline
      unquote(timeline_block)

      # Procesar diverges
      unquote_splicing(diverge_blocks)

      # Procesar branches
      unquote_splicing(branch_blocks)
    end
  end

  @doc """
  Macro para definir la secuencia de steps del workflow.

  Acepta un pipeline de funciones separadas por `|>`.

  ## Ejemplo

      timeline do
        step1() |> step2() |> step3()
      end
  """
  defmacro timeline(do: pipeline) do
    steps = parse_timeline_pipeline(pipeline)

    quote do
      @cerebelum_timeline unquote(steps)
    end
  end

  @doc """
  Macro para definir pattern matching en el resultado de un step.

  Usado para error handling y retry logic.

  ## Ejemplo

      diverge from: validate_order() do
        :timeout -> :retry
        {:error, :out_of_stock} -> back_to(:check_inventory)
        {:error, _} -> :failed
      end
  """
  defmacro diverge(opts, do: block) do
    step_name = extract_function_name(opts[:from])

    # Quote el bloque completo para preservar los patrones
    patterns_quoted = Macro.escape(parse_match_block(block))

    quote do
      @cerebelum_diverges {unquote(step_name), unquote(patterns_quoted)}
    end
  end

  @doc """
  Macro para conditional branching basado en evaluación de condiciones.

  Usado para lógica de negocio condicional.

  ## Ejemplo

      branch after: process_payment(), on: result do
        result.amount > 1000 -> :high_value_path
        result.amount > 100 -> :medium_value_path
        true -> :standard_path
      end
  """
  defmacro branch(opts, do: block) do
    step_name = extract_function_name(opts[:after])
    variable = opts[:on]

    # Quote el bloque completo para preservar las condiciones
    conditions_quoted = Macro.escape(parse_condition_block(block, variable))

    quote do
      @cerebelum_branches {unquote(step_name), unquote(conditions_quoted)}
    end
  end

  # Helpers privados

  @doc false
  def parse_workflow_block(block) do
    # El block puede ser:
    # 1. Un solo elemento (ej: solo timeline)
    # 2. Un bloque {:__block__, _, [expr1, expr2, ...]}

    exprs =
      case block do
        {:__block__, _, expressions} -> expressions
        single_expr -> [single_expr]
      end

    # Separar en timeline, diverges, y branches
    {timeline, diverges, branches} =
      Enum.reduce(exprs, {nil, [], []}, fn expr, {tl, divs, brs} ->
        case expr do
          {:timeline, _, _} = timeline_expr ->
            {timeline_expr, divs, brs}

          {:diverge, _, _} = diverge_expr ->
            {tl, [diverge_expr | divs], brs}

          {:branch, _, _} = branch_expr ->
            {tl, divs, [branch_expr | brs]}

          _ ->
            {tl, divs, brs}
        end
      end)

    {timeline, Enum.reverse(diverges), Enum.reverse(branches)}
  end

  @doc false
  def parse_timeline_pipeline(pipeline) do
    pipeline
    |> extract_pipeline_steps()
    |> Enum.map(&extract_function_name/1)
  end

  # Extrae los steps de un pipeline a |> b |> c
  defp extract_pipeline_steps({:|>, _, [left, right]}) do
    # Pipeline: recursivamente extraer
    extract_pipeline_steps(left) ++ [right]
  end

  defp extract_pipeline_steps(single_call) do
    # Solo una llamada
    [single_call]
  end

  @doc false
  def extract_function_name({function_name, _, _args}) when is_atom(function_name) do
    # Llamada de función: validate_order() -> :validate_order
    function_name
  end

  def extract_function_name(function_name) when is_atom(function_name) do
    # Atom directo: :step1 -> :step1
    function_name
  end

  @doc false
  def parse_match_block(block) do
    # El block puede ser:
    # 1. Una lista de cláusulas (cuando viene del AST directo)
    # 2. Un __block__ con cláusulas
    # 3. Una sola cláusula

    clauses =
      cond do
        is_list(block) ->
          # Ya es una lista de cláusulas
          block

        match?({:__block__, _, _}, block) ->
          # Bloque con múltiples cláusulas
          {:__block__, _, cls} = block
          cls

        true ->
          # Una sola cláusula
          [block]
      end

    Enum.map(clauses, fn {:->, _, [[pattern], action]} ->
      {pattern, action}
    end)
  end

  @doc false
  def parse_condition_block(block, variable) do
    # Similar a parse_match_block, pero las condiciones son expresiones AST
    clauses =
      cond do
        is_list(block) ->
          # Ya es una lista de cláusulas
          block

        match?({:__block__, _, _}, block) ->
          # Bloque con múltiples cláusulas
          {:__block__, _, cls} = block
          cls

        true ->
          # Una sola cláusula
          [block]
      end

    Enum.map(clauses, fn {:->, _, [[condition], action]} ->
      # Reemplazar la variable en la condición con el AST correcto
      condition_ast = inject_variable(condition, variable)
      {condition_ast, action}
    end)
  end

  # Inyectar la variable en el AST de la condición
  defp inject_variable(ast, _variable) do
    # Por ahora, simplemente retornar el AST tal cual
    # En una implementación completa, aquí reemplazaríamos referencias
    # a la variable con el valor correcto
    ast
  end
end
