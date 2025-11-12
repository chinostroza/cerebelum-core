defmodule Cerebelum.Event.StepCompleted do
  @moduledoc """
  Evento emitido cuando un step termina exitosamente.

  **Feature: Step Events**
  **Directorio: event/step/**

  Este directorio contiene TODOS los eventos de steps:
  - StepStarted
  - StepCompleted
  - StepFailed
  """

  @enforce_keys [:execution_id, :step_name, :result, :occurred_at]
  defstruct [:execution_id, :step_name, :result, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          step_name: atom(),
          result: any(),
          occurred_at: DateTime.t()
        }

  @doc "Crea un evento StepCompleted"
  @spec new(String.t(), atom(), any()) :: t()
  def new(execution_id, step_name, result) do
    %__MODULE__{
      execution_id: execution_id,
      step_name: step_name,
      result: result,
      occurred_at: DateTime.utc_now()
    }
  end
end
