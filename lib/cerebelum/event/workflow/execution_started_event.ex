defmodule Cerebelum.Event.ExecutionStarted do
  @moduledoc """
  Evento emitido cuando una ejecución de workflow inicia.

  **Feature: Workflow Events**
  **Directorio: event/workflow/**

  Este directorio contiene TODOS los eventos de workflow (execution-level):
  - ExecutionStarted
  - ExecutionCompleted
  - ExecutionFailed
  """

  @enforce_keys [:execution_id, :workflow_module, :inputs, :occurred_at]
  defstruct [:execution_id, :workflow_module, :inputs, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          workflow_module: module(),
          inputs: map(),
          occurred_at: DateTime.t()
        }

  @doc "Crea un evento ExecutionStarted"
  @spec new(String.t(), module(), map()) :: t()
  def new(execution_id, workflow_module, inputs) do
    %__MODULE__{
      execution_id: execution_id,
      workflow_module: workflow_module,
      inputs: inputs,
      occurred_at: DateTime.utc_now()
    }
  end
end
