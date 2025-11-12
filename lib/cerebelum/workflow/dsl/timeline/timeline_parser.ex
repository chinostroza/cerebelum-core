defmodule Cerebelum.Workflow.DSL.Timeline.TimelineParser do
  @moduledoc """
  Parser para el bloque `timeline`.

  **Feature: Timeline**
  **Directorio: dsl/timeline/**

  Módulo 100% autocontenido - No depende de otros parsers.

  ## Responsabilidad

  - Parsear pipeline `step1() |> step2() |> step3()`
  - Convertir a lista de atoms
  """

  @doc """
  Parsea el pipeline del timeline en una lista de steps.
  """
  @spec parse_timeline_pipeline(Macro.t()) :: [atom()]
  def parse_timeline_pipeline(pipeline) do
    pipeline
    |> extract_pipeline_steps()
    |> Enum.map(&extract_function_name/1)
  end

  # Helpers privados
  defp extract_pipeline_steps({:|>, _, [left, right]}) do
    extract_pipeline_steps(left) ++ [right]
  end

  defp extract_pipeline_steps(single_call), do: [single_call]

  defp extract_function_name({function_name, _, _args}) when is_atom(function_name) do
    function_name
  end

  defp extract_function_name(function_name) when is_atom(function_name) do
    function_name
  end
end
