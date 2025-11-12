defmodule Cerebelum.Event.StepStarted do
  @moduledoc """
  Evento emitido cuando un step inicia su ejecución.

  **Feature: Step Events**
  **Directorio: event/step/**

  Este directorio contiene TODOS los eventos de steps:
  - StepStarted
  - StepCompleted
  - StepFailed
  """

  @enforce_keys [:execution_id, :step_name, :occurred_at]
  defstruct [:execution_id, :step_name, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          step_name: atom(),
          occurred_at: DateTime.t()
        }

  @doc "Crea un evento StepStarted"
  @spec new(String.t(), atom()) :: t()
  def new(execution_id, step_name) do
    %__MODULE__{
      execution_id: execution_id,
      step_name: step_name,
      occurred_at: DateTime.utc_now()
    }
  end
end
