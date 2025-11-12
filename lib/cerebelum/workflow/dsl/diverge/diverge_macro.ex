defmodule Cerebelum.Workflow.DSL.Diverge.DivergeMacro do
  @moduledoc """
  Macro `diverge` para pattern matching en resultados de steps.

  **Feature: Diverge**
  **Directorio: dsl/diverge/**

  Este directorio contiene TODO lo relacionado con la feature "diverge":
  - macro.ex → La macro pública
  - parser.ex → El parser del AST

  ## Ejemplo

      diverge from: validate_order() do
        :timeout -> :retry
        {:error, _} -> :failed
      end
  """

  alias Cerebelum.Workflow.DSL.Diverge.DivergeParser

  @doc """
  Macro para definir pattern matching en el resultado de un step.
  """
  defmacro diverge(opts, do: block) do
    step_name = DivergeParser.extract_step_name(opts)
    patterns_quoted = Macro.escape(DivergeParser.parse_match_block(block))

    quote do
      @cerebelum_diverges {unquote(step_name), unquote(patterns_quoted)}
    end
  end
end
