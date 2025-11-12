defmodule Cerebelum.FlowAction.Continue do
  @moduledoc """
  Acción que indica continuar al siguiente step del timeline.

  **Feature: Continue Action**
  **Directorio: flow_action/continue/**

  Este directorio contiene TODO lo relacionado con la acción Continue.
  """

  @enforce_keys []
  defstruct []

  @type t :: %__MODULE__{}

  @doc "Crea una acción Continue"
  @spec new() :: t()
  def new, do: %__MODULE__{}
end
