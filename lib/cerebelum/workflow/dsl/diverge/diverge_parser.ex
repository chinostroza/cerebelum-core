defmodule Cerebelum.Workflow.DSL.Diverge.DivergeParser do
  @moduledoc """
  Parser para el bloque `diverge`.

  **Feature: Diverge**
  **Directorio: dsl/diverge/**

  Módulo 100% autocontenido - No depende de otros parsers.

  ## Responsabilidad

  - Parsear patrones `pattern -> action`
  - Extraer step name de `:from`
  """

  @doc """
  Extrae el nombre del step de la opción `:from`.
  """
  @spec extract_step_name(keyword()) :: atom()
  def extract_step_name(opts) do
    extract_function_name(opts[:from])
  end

  @doc """
  Parsea un bloque de pattern matching.
  """
  @spec parse_match_block(Macro.t() | list()) :: [{Macro.t(), any()}]
  def parse_match_block(block) do
    clauses = normalize_clauses(block)

    Enum.map(clauses, fn {:->, _, [[pattern], action]} ->
      {pattern, action}
    end)
  end

  # Helpers privados
  defp normalize_clauses(block) when is_list(block), do: block
  defp normalize_clauses({:__block__, _, clauses}), do: clauses
  defp normalize_clauses(single_clause), do: [single_clause]

  defp extract_function_name({function_name, _, _args}) when is_atom(function_name) do
    function_name
  end

  defp extract_function_name(function_name) when is_atom(function_name) do
    function_name
  end
end
