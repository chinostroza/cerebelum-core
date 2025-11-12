defmodule Cerebelum.Workflow.DSL.Workflow.WorkflowMacro do
  @moduledoc """
  Macro `workflow` para definir el bloque completo del workflow.

  **Feature: Workflow**
  **Directorio: dsl/workflow/**
  **Archivo: workflow_macro.ex**

  Este directorio contiene TODO lo relacionado con la feature "workflow":
  - workflow_macro.ex → La macro pública
  - workflow_parser.ex → El parser del AST

  ## Responsabilidad

  - Parsear el bloque `workflow do ... end`
  - Delegar a timeline, diverge, branch macros

  ## Ejemplo

      workflow do
        timeline do
          step1() |> step2() |> step3()
        end

        diverge from: step1() do
          :timeout -> :retry
        end

        branch after: step2(), on: result do
          result > 0.5 -> :high
          true -> :low
        end
      end
  """

  alias Cerebelum.Workflow.DSL.Workflow.WorkflowParser

  @doc """
  Macro principal que parsea el bloque del workflow.
  """
  defmacro workflow(do: block) do
    {timeline_block, diverge_blocks, branch_blocks} = WorkflowParser.parse_workflow_block(block)

    quote do
      unquote(timeline_block)
      unquote_splicing(diverge_blocks)
      unquote_splicing(branch_blocks)
    end
  end
end
