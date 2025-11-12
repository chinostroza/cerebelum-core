defmodule Cerebelum.Workflow.DSL.Workflow.WorkflowParser do
  @moduledoc """
  Parser para el bloque `workflow` completo.

  **Feature: Workflow**
  **Directorio: dsl/workflow/**
  **Archivo: workflow_parser.ex**

  Módulo 100% autocontenido - No depende de otros parsers.

  ## Responsabilidad

  - Parsear el bloque `workflow do ... end`
  - Separar en timeline, diverges, y branches
  """

  @doc """
  Parsea el bloque completo del workflow.

  Separa en: `{timeline_ast | nil, [diverge_ast], [branch_ast]}`
  """
  @spec parse_workflow_block(Macro.t()) :: {Macro.t() | nil, [Macro.t()], [Macro.t()]}
  def parse_workflow_block(block) do
    exprs = normalize_block(block)

    {timeline, diverges, branches} =
      Enum.reduce(exprs, {nil, [], []}, fn expr, {tl, divs, brs} ->
        case expr do
          {:timeline, _, _} = timeline_expr -> {timeline_expr, divs, brs}
          {:diverge, _, _} = diverge_expr -> {tl, [diverge_expr | divs], brs}
          {:branch, _, _} = branch_expr -> {tl, divs, [branch_expr | brs]}
          _ -> {tl, divs, brs}
        end
      end)

    {timeline, Enum.reverse(diverges), Enum.reverse(branches)}
  end

  # Helpers privados
  defp normalize_block({:__block__, _, expressions}), do: expressions
  defp normalize_block(single_expr), do: [single_expr]
end
