defmodule Cerebelum.Workflow.DSL.Timeline.TimelineMacro do
  @moduledoc """
  Macro `timeline` para definir la secuencia de steps.

  **Feature: Timeline**
  **Directorio: dsl/timeline/**
  **Archivo: timeline_macro.ex**

  Este directorio contiene TODO lo relacionado con la feature "timeline":
  - timeline_macro.ex → La macro pública
  - timeline_parser.ex → El parser del AST

  ## Ejemplo

      timeline do
        step1() |> step2() |> step3()
      end
  """

  alias Cerebelum.Workflow.DSL.Timeline.TimelineParser

  @doc """
  Macro para definir la secuencia de steps del workflow.
  """
  defmacro timeline(do: pipeline) do
    steps = TimelineParser.parse_timeline_pipeline(pipeline)

    quote do
      @cerebelum_timeline unquote(steps)
    end
  end
end
