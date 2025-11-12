defmodule Cerebelum.Workflow.DSL.Branch.BranchParser do
  @moduledoc """
  Parser para el bloque `branch`.

  **Feature: Branch**
  **Directorio: dsl/branch/**

  Módulo 100% autocontenido - No depende de otros parsers.

  ## Responsabilidad

  - Parsear condiciones `condition -> action`
  - Extraer step name de `:after`
  - Capturar variable de `:on`
  """

  @doc """
  Extrae el nombre del step de la opción `:after`.
  """
  @spec extract_step_name(keyword()) :: atom()
  def extract_step_name(opts) do
    extract_function_name(opts[:after])
  end

  @doc """
  Parsea un bloque de condiciones.
  """
  @spec parse_condition_block(Macro.t() | list(), atom()) :: [{Macro.t(), any()}]
  def parse_condition_block(block, variable) do
    clauses = normalize_clauses(block)

    Enum.map(clauses, fn {:->, _, [[condition], action]} ->
      condition_ast = inject_variable(condition, variable)
      {condition_ast, action}
    end)
  end

  # Helpers privados
  defp normalize_clauses(block) when is_list(block), do: block
  defp normalize_clauses({:__block__, _, clauses}), do: clauses
  defp normalize_clauses(single_clause), do: [single_clause]

  defp inject_variable(ast, _variable), do: ast

  defp extract_function_name({function_name, _, _args}) when is_atom(function_name) do
    function_name
  end

  defp extract_function_name(function_name) when is_atom(function_name) do
    function_name
  end
end
