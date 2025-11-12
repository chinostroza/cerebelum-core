defmodule Cerebelum.FlowAction do
  @moduledoc """
  Flow control actions para workflows.

  Este módulo es un **orquestador** que re-exporta todas las flow actions.

  ## Arquitectura - Package by Feature

  Cada acción tiene su propio directorio:

  ```
  flow_action/
  ├── continue/
  │   └── continue_action.ex
  ├── back_to/
  │   └── back_to_action.ex
  ├── skip_to/
  │   └── skip_to_action.ex
  └── failed/
      └── failed_action.ex
  ```

  ## Principios

  ### Package by Feature (no by Layer)
  - ✅ `flow_action/continue/` - Feature completa autocontenida
  - ✅ `flow_action/back_to/` - Feature completa autocontenida
  - ✅ `flow_action/skip_to/` - Feature completa autocontenida
  - ✅ `flow_action/failed/` - Feature completa autocontenida
  - ❌ Un archivo monolítico con todas las acciones

  ### CERO Acoplamiento entre Features
  - Modificar `continue/` → No afecta `back_to/`
  - Borrar `skip_to/` → `rm -rf flow_action/skip_to/`
  - Agregar nueva acción → `mkdir flow_action/nueva_accion/`

  ### Cohesión Máxima
  - TODO continue está en `flow_action/continue/`
  - TODO back_to está en `flow_action/back_to/`
  - Todo está donde lo esperas encontrar

  ## Acciones Disponibles

  Estas acciones determinan cómo continúa la ejecución después de
  evaluar un `diverge()` o `branch()`.

  - `Continue` - Continuar al siguiente step del timeline
  - `BackTo` - Volver a un step anterior (ej: retry)
  - `SkipTo` - Saltar a un step adelante (ej: fast-forward)
  - `Failed` - Terminar ejecución con error

  ## Ejemplos

      iex> FlowAction.continue()
      %Cerebelum.FlowAction.Continue{}

      iex> FlowAction.back_to(:validate_order)
      %Cerebelum.FlowAction.BackTo{step: :validate_order}

      iex> FlowAction.failed(:timeout)
      %Cerebelum.FlowAction.Failed{reason: :timeout}
  """

  alias Cerebelum.FlowAction.{Continue, BackTo, SkipTo, Failed}

  @type t :: Continue.t() | BackTo.t() | SkipTo.t() | Failed.t()

  # Constructores - Delegan a los módulos individuales

  @doc "Crea una acción Continue"
  @spec continue() :: Continue.t()
  def continue, do: Continue.new()

  @doc "Crea una acción BackTo que vuelve a un step anterior"
  @spec back_to(atom()) :: BackTo.t()
  def back_to(step) when is_atom(step), do: BackTo.new(step)

  @doc "Crea una acción SkipTo que salta a un step adelante"
  @spec skip_to(atom()) :: SkipTo.t()
  def skip_to(step) when is_atom(step), do: SkipTo.new(step)

  @doc "Crea una acción Failed que termina la ejecución"
  @spec failed(any()) :: Failed.t()
  def failed(reason), do: Failed.new(reason)

  # Type guards

  @doc "Verifica si un término es una FlowAction"
  @spec is_flow_action?(any()) :: boolean()
  def is_flow_action?(term) do
    match?(%Continue{}, term) or
      match?(%BackTo{}, term) or
      match?(%SkipTo{}, term) or
      match?(%Failed{}, term)
  end

  @doc "Verifica si es una acción Continue"
  @spec continue?(any()) :: boolean()
  def continue?(%Continue{}), do: true
  def continue?(_), do: false

  @doc "Verifica si es una acción BackTo"
  @spec back_to?(any()) :: boolean()
  def back_to?(%BackTo{}), do: true
  def back_to?(_), do: false

  @doc "Verifica si es una acción SkipTo"
  @spec skip_to?(any()) :: boolean()
  def skip_to?(%SkipTo{}), do: true
  def skip_to?(_), do: false

  @doc "Verifica si es una acción Failed"
  @spec failed?(any()) :: boolean()
  def failed?(%Failed{}), do: true
  def failed?(_), do: false
end
