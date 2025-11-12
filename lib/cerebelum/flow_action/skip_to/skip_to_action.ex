defmodule Cerebelum.FlowAction.SkipTo do
  @moduledoc """
  Acción que indica saltar a un step adelante.

  Usado para fast-forward o conditional branches.

  **Feature: SkipTo Action**
  **Directorio: flow_action/skip_to/**

  Este directorio contiene TODO lo relacionado con la acción SkipTo.
  """

  @enforce_keys [:step]
  defstruct [:step]

  @type t :: %__MODULE__{
          step: atom()
        }

  @doc "Crea una acción SkipTo que salta a un step adelante"
  @spec new(atom()) :: t()
  def new(step) when is_atom(step), do: %__MODULE__{step: step}
end
