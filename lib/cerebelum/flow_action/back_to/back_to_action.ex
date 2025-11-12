defmodule Cerebelum.FlowAction.BackTo do
  @moduledoc """
  Acción que indica volver a un step anterior.

  Usado típicamente para retry patterns o loops hacia atrás.

  **Feature: BackTo Action**
  **Directorio: flow_action/back_to/**

  Este directorio contiene TODO lo relacionado con la acción BackTo.
  """

  @enforce_keys [:step]
  defstruct [:step]

  @type t :: %__MODULE__{
          step: atom()
        }

  @doc "Crea una acción BackTo que vuelve a un step anterior"
  @spec new(atom()) :: t()
  def new(step) when is_atom(step), do: %__MODULE__{step: step}
end
