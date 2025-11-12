defmodule Cerebelum.Event.ExecutionCompleted do
  @moduledoc """
  Evento emitido cuando toda la ejecución termina exitosamente.

  **Feature: Workflow Events**
  **Directorio: event/workflow/**

  Este directorio contiene TODOS los eventos de workflow (execution-level):
  - ExecutionStarted
  - ExecutionCompleted
  - ExecutionFailed
  """

  @enforce_keys [:execution_id, :final_result, :occurred_at]
  defstruct [:execution_id, :final_result, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          final_result: any(),
          occurred_at: DateTime.t()
        }

  @doc "Crea un evento ExecutionCompleted"
  @spec new(String.t(), any()) :: t()
  def new(execution_id, final_result) do
    %__MODULE__{
      execution_id: execution_id,
      final_result: final_result,
      occurred_at: DateTime.utc_now()
    }
  end
end
