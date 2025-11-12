# Event Structs - Definir primero

defmodule Cerebelum.Event.ExecutionStarted do
  @moduledoc """
  Evento emitido cuando una ejecución de workflow inicia.
  """

  @enforce_keys [:execution_id, :workflow_module, :inputs, :occurred_at]
  defstruct [:execution_id, :workflow_module, :inputs, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          workflow_module: module(),
          inputs: map(),
          occurred_at: DateTime.t()
        }
end

defmodule Cerebelum.Event.StepStarted do
  @moduledoc """
  Evento emitido cuando un step inicia su ejecución.
  """

  @enforce_keys [:execution_id, :step_name, :occurred_at]
  defstruct [:execution_id, :step_name, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          step_name: atom(),
          occurred_at: DateTime.t()
        }
end

defmodule Cerebelum.Event.StepCompleted do
  @moduledoc """
  Evento emitido cuando un step termina exitosamente.
  """

  @enforce_keys [:execution_id, :step_name, :result, :occurred_at]
  defstruct [:execution_id, :step_name, :result, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          step_name: atom(),
          result: any(),
          occurred_at: DateTime.t()
        }
end

defmodule Cerebelum.Event.StepFailed do
  @moduledoc """
  Evento emitido cuando un step falla.
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
end

defmodule Cerebelum.Event.ExecutionCompleted do
  @moduledoc """
  Evento emitido cuando toda la ejecución termina exitosamente.
  """

  @enforce_keys [:execution_id, :final_result, :occurred_at]
  defstruct [:execution_id, :final_result, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          final_result: any(),
          occurred_at: DateTime.t()
        }
end

defmodule Cerebelum.Event.ExecutionFailed do
  @moduledoc """
  Evento emitido cuando toda la ejecución falla.
  """

  @enforce_keys [:execution_id, :reason, :failed_step, :occurred_at]
  defstruct [:execution_id, :reason, :failed_step, :occurred_at]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          reason: any(),
          failed_step: atom(),
          occurred_at: DateTime.t()
        }
end

defmodule Cerebelum.Event.CheckpointCreated do
  @moduledoc """
  Evento emitido cuando se crea un checkpoint (snapshot) del estado.

  Los checkpoints permiten optimizar el replay: en lugar de reproducir
  todos los eventos desde el inicio, podemos empezar desde el último checkpoint.
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
end

# Módulo principal con constructores y helpers
defmodule Cerebelum.Event do
  @moduledoc """
  Event schemas para Event Sourcing en Cerebelum.

  Estos eventos se persisten en el Event Store y permiten reconstruir
  el estado completo de una ejecución en cualquier momento.

  ## Tipos de Eventos

  - **Execution Events**: `ExecutionStarted`, `ExecutionCompleted`, `ExecutionFailed`
  - **Step Events**: `StepStarted`, `StepCompleted`, `StepFailed`
  - **Checkpoint Events**: `CheckpointCreated`

  ## Ejemplos

      iex> Event.execution_started("exec-123", MyWorkflow, %{order_id: "123"})
      %Cerebelum.Event.ExecutionStarted{
        execution_id: "exec-123",
        workflow_module: MyWorkflow,
        inputs: %{order_id: "123"},
        occurred_at: ~U[2024-01-15 10:30:00Z]
      }

      iex> Event.step_completed("exec-123", :validate_order, %{valid: true})
      %Cerebelum.Event.StepCompleted{...}
  """

  alias Cerebelum.Event.{
    ExecutionStarted,
    StepStarted,
    StepCompleted,
    StepFailed,
    ExecutionCompleted,
    ExecutionFailed,
    CheckpointCreated
  }

  @type t ::
          ExecutionStarted.t()
          | StepStarted.t()
          | StepCompleted.t()
          | StepFailed.t()
          | ExecutionCompleted.t()
          | ExecutionFailed.t()
          | CheckpointCreated.t()

  # Constructores

  @doc "Crea un evento ExecutionStarted"
  @spec execution_started(String.t(), module(), map()) :: ExecutionStarted.t()
  def execution_started(execution_id, workflow_module, inputs) do
    %ExecutionStarted{
      execution_id: execution_id,
      workflow_module: workflow_module,
      inputs: inputs,
      occurred_at: DateTime.utc_now()
    }
  end

  @doc "Crea un evento StepStarted"
  @spec step_started(String.t(), atom()) :: StepStarted.t()
  def step_started(execution_id, step_name) do
    %StepStarted{
      execution_id: execution_id,
      step_name: step_name,
      occurred_at: DateTime.utc_now()
    }
  end

  @doc "Crea un evento StepCompleted"
  @spec step_completed(String.t(), atom(), any()) :: StepCompleted.t()
  def step_completed(execution_id, step_name, result) do
    %StepCompleted{
      execution_id: execution_id,
      step_name: step_name,
      result: result,
      occurred_at: DateTime.utc_now()
    }
  end

  @doc "Crea un evento StepFailed"
  @spec step_failed(String.t(), atom(), any(), list() | nil) :: StepFailed.t()
  def step_failed(execution_id, step_name, error, stacktrace \\ nil) do
    %StepFailed{
      execution_id: execution_id,
      step_name: step_name,
      error: error,
      stacktrace: stacktrace,
      occurred_at: DateTime.utc_now()
    }
  end

  @doc "Crea un evento ExecutionCompleted"
  @spec execution_completed(String.t(), any()) :: ExecutionCompleted.t()
  def execution_completed(execution_id, final_result) do
    %ExecutionCompleted{
      execution_id: execution_id,
      final_result: final_result,
      occurred_at: DateTime.utc_now()
    }
  end

  @doc "Crea un evento ExecutionFailed"
  @spec execution_failed(String.t(), any(), atom()) :: ExecutionFailed.t()
  def execution_failed(execution_id, reason, failed_step) do
    %ExecutionFailed{
      execution_id: execution_id,
      reason: reason,
      failed_step: failed_step,
      occurred_at: DateTime.utc_now()
    }
  end

  @doc "Crea un evento CheckpointCreated"
  @spec checkpoint_created(String.t(), atom(), any(), map()) :: CheckpointCreated.t()
  def checkpoint_created(execution_id, step_name, context, results_cache) do
    %CheckpointCreated{
      execution_id: execution_id,
      step_name: step_name,
      context: context,
      results_cache: results_cache,
      occurred_at: DateTime.utc_now()
    }
  end

  # Type guards

  @doc "Verifica si es un evento de ejecución (execution-level)"
  @spec execution_event?(any()) :: boolean()
  def execution_event?(event) do
    match?(%ExecutionStarted{}, event) or
      match?(%ExecutionCompleted{}, event) or
      match?(%ExecutionFailed{}, event)
  end

  @doc "Verifica si es un evento de step"
  @spec step_event?(any()) :: boolean()
  def step_event?(event) do
    match?(%StepStarted{}, event) or
      match?(%StepCompleted{}, event) or
      match?(%StepFailed{}, event)
  end
end
