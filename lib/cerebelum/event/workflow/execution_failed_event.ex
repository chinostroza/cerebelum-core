defmodule Cerebelum.Event.ExecutionFailed do
  @moduledoc """
  Evento emitido cuando toda la ejecución falla.

  **Feature: Workflow Events**
  **Directorio: event/workflow/**

  Este directorio contiene TODOS los eventos de workflow (execution-level):
  - ExecutionStarted
  - ExecutionCompleted
  - ExecutionFailed
  """

  @enforce_keys [:execution_id, :reason, :failed_step, :occurred_at]
  defstruct [:execution_id, :reason, :failed_step, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          reason: any(),
          failed_step: atom(),
          occurred_at: DateTime.t()
        }

  @doc "Crea un evento ExecutionFailed"
  @spec new(String.t(), any(), atom()) :: t()
  def new(execution_id, reason, failed_step) do
    %__MODULE__{
      execution_id: execution_id,
      reason: reason,
      failed_step: failed_step,
      occurred_at: DateTime.utc_now()
    }
  end
end
