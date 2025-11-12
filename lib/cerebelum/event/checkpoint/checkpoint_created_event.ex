defmodule Cerebelum.Event.CheckpointCreated do
  @moduledoc """
  Evento emitido cuando se crea un checkpoint (snapshot) del estado.

  Los checkpoints permiten optimizar el replay: en lugar de reproducir
  todos los eventos desde el inicio, podemos empezar desde el último checkpoint.

  **Feature: Checkpoint Events**
  **Directorio: event/checkpoint/**

  Este directorio contiene TODOS los eventos de checkpoints.
  Es una feature transversal que puede ser usada por workflows, sub-workflows, etc.
  """

  @enforce_keys [:execution_id, :step_name, :context, :results_cache, :occurred_at]
  defstruct [:execution_id, :step_name, :context, :results_cache, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          step_name: atom(),
          context: any(),
          results_cache: map(),
          occurred_at: DateTime.t()
        }

  @doc "Crea un evento CheckpointCreated"
  @spec new(String.t(), atom(), any(), map()) :: t()
  def new(execution_id, step_name, context, results_cache) do
    %__MODULE__{
      execution_id: execution_id,
      step_name: step_name,
      context: context,
      results_cache: results_cache,
      occurred_at: DateTime.utc_now()
    }
  end
end
