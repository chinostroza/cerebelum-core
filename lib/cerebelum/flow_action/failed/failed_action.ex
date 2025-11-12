defmodule Cerebelum.FlowAction.Failed do
  @moduledoc """
  Acción que indica terminar la ejecución con error.

  Contiene la razón del fallo.

  **Feature: Failed Action**
  **Directorio: flow_action/failed/**

  Este directorio contiene TODO lo relacionado con la acción Failed.
  """

  @enforce_keys [:reason]
  defstruct [:reason]

  @type t :: %__MODULE__{
          reason: any()
        }

  @doc "Crea una acción Failed que termina la ejecución"
  @spec new(any()) :: t()
  def new(reason), do: %__MODULE__{reason: reason}
end
