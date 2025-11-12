defmodule Cerebelum.Event do
  @moduledoc """
  Event schemas para Event Sourcing en Cerebelum.

  Este módulo es un **orquestador** que re-exporta todos los eventos.

  ## Arquitectura - Package by Feature

  Cada tipo de evento tiene su propio directorio:

  ```
  event/
  ├── workflow/
  │   ├── execution_started_event.ex
  │   ├── execution_completed_event.ex
  │   └── execution_failed_event.ex
  ├── step/
  │   ├── step_started_event.ex
  │   ├── step_completed_event.ex
  │   └── step_failed_event.ex
  └── checkpoint/
      └── checkpoint_created_event.ex
  ```

  ## Principios

  ### Package by Feature (no by Layer)
  - ✅ `event/workflow/` - Todos los eventos de workflow juntos
  - ✅ `event/step/` - Todos los eventos de step juntos
  - ✅ `event/checkpoint/` - Feature transversal de checkpoints
  - ❌ Un archivo monolítico con todos los eventos

  ### CERO Acoplamiento entre Features
  - Modificar `workflow/` → No afecta `step/`
  - Borrar `checkpoint/` → `rm -rf event/checkpoint/`
  - Agregar nuevo evento → Añadir en el directorio correspondiente

  ### Cohesión Máxima
  - TODO workflow está en `event/workflow/`
  - TODO step está en `event/step/`
  - Todo está donde lo esperas encontrar

  ## Tipos de Eventos

  - **Workflow Events**: `ExecutionStarted`, `ExecutionCompleted`, `ExecutionFailed`
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

  # Constructores - Delegan a los módulos individuales

  @doc "Crea un evento ExecutionStarted"
  @spec execution_started(String.t(), module(), map()) :: ExecutionStarted.t()
  def execution_started(execution_id, workflow_module, inputs) do
    ExecutionStarted.new(execution_id, workflow_module, inputs)
  end

  @doc "Crea un evento StepStarted"
  @spec step_started(String.t(), atom()) :: StepStarted.t()
  def step_started(execution_id, step_name) do
    StepStarted.new(execution_id, step_name)
  end

  @doc "Crea un evento StepCompleted"
  @spec step_completed(String.t(), atom(), any()) :: StepCompleted.t()
  def step_completed(execution_id, step_name, result) do
    StepCompleted.new(execution_id, step_name, result)
  end

  @doc "Crea un evento StepFailed"
  @spec step_failed(String.t(), atom(), any(), list() | nil) :: StepFailed.t()
  def step_failed(execution_id, step_name, error, stacktrace \\ nil) do
    StepFailed.new(execution_id, step_name, error, stacktrace)
  end

  @doc "Crea un evento ExecutionCompleted"
  @spec execution_completed(String.t(), any()) :: ExecutionCompleted.t()
  def execution_completed(execution_id, final_result) do
    ExecutionCompleted.new(execution_id, final_result)
  end

  @doc "Crea un evento ExecutionFailed"
  @spec execution_failed(String.t(), any(), atom()) :: ExecutionFailed.t()
  def execution_failed(execution_id, reason, failed_step) do
    ExecutionFailed.new(execution_id, reason, failed_step)
  end

  @doc "Crea un evento CheckpointCreated"
  @spec checkpoint_created(String.t(), atom(), any(), map()) :: CheckpointCreated.t()
  def checkpoint_created(execution_id, step_name, context, results_cache) do
    CheckpointCreated.new(execution_id, step_name, context, results_cache)
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
