defmodule Cerebelum.Workflow.DSL.Branch.BranchMacro do
  @moduledoc """
  Macro `branch` para conditional branching.

  **Feature: Branch**
  **Directorio: dsl/branch/**

  Este directorio contiene TODO lo relacionado con la feature "branch":
  - macro.ex → La macro pública
  - parser.ex → El parser del AST

  ## Ejemplo

      branch after: calculate(), on: result do
        result > 0.8 -> :high
        true -> :low
      end
  """

  alias Cerebelum.Workflow.DSL.Branch.BranchParser

  @doc """
  Macro para conditional branching basado en condiciones.
  """
  defmacro branch(opts, do: block) do
    step_name = BranchParser.extract_step_name(opts)
    variable = opts[:on]
    conditions_quoted = Macro.escape(BranchParser.parse_condition_block(block, variable))

    quote do
      @cerebelum_branches {unquote(step_name), unquote(conditions_quoted)}
    end
  end
end
