defmodule Cerebelum.Event.StepFailed do
  @moduledoc """
  Evento emitido cuando un step falla.

  **Feature: Step Events**
  **Directorio: event/step/**

  Este directorio contiene TODOS los eventos de steps:
  - StepStarted
  - StepCompleted
  - StepFailed
  """

  @enforce_keys [:execution_id, :step_name, :error, :occurred_at]
  defstruct [:execution_id, :step_name, :error, :stacktrace, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          step_name: atom(),
          error: any(),
          stacktrace: list() | nil,
          occurred_at: DateTime.t()
        }

  @doc "Crea un evento StepFailed"
  @spec new(String.t(), atom(), any(), list() | nil) :: t()
  def new(execution_id, step_name, error, stacktrace \\ nil) do
    %__MODULE__{
      execution_id: execution_id,
      step_name: step_name,
      error: error,
      stacktrace: stacktrace,
      occurred_at: DateTime.utc_now()
    }
  end
end
