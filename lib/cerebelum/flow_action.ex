# Definir structs primero
defmodule Cerebelum.FlowAction.Continue do
  @moduledoc """
  Acción que indica continuar al siguiente step del timeline.
  """

  @enforce_keys []
  defstruct []

  @type t :: %__MODULE__{}
end

defmodule Cerebelum.FlowAction.BackTo do
  @moduledoc """
  Acción que indica volver a un step anterior.

  Usado típicamente para retry patterns o loops hacia atrás.
  """

  @enforce_keys [:step]
  defstruct [:step]

  @type t :: %__MODULE__{
    step: atom()
  }
end

defmodule Cerebelum.FlowAction.SkipTo do
  @moduledoc """
  Acción que indica saltar a un step adelante.

  Usado para fast-forward o conditional branches.
  """

  @enforce_keys [:step]
  defstruct [:step]

  @type t :: %__MODULE__{
    step: atom()
  }
end

defmodule Cerebelum.FlowAction.Failed do
  @moduledoc """
  Acción que indica terminar la ejecución con error.

  Contiene la razón del fallo.
  """

  @enforce_keys [:reason]
  defstruct [:reason]

  @type t :: %__MODULE__{
    reason: any()
  }
end

# Módulo principal con helpers
defmodule Cerebelum.FlowAction do
  @moduledoc """
  Flow control actions para workflows.

  Estas acciones determinan cómo continúa la ejecución después de
  evaluar un `diverge()` o `branch()`.

  ## Acciones Disponibles

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

  # Constructores

  @doc "Crea una acción Continue"
  @spec continue() :: Continue.t()
  def continue, do: %Continue{}

  @doc "Crea una acción BackTo que vuelve a un step anterior"
  @spec back_to(atom()) :: BackTo.t()
  def back_to(step) when is_atom(step), do: %BackTo{step: step}

  @doc "Crea una acción SkipTo que salta a un step adelante"
  @spec skip_to(atom()) :: SkipTo.t()
  def skip_to(step) when is_atom(step), do: %SkipTo{step: step}

  @doc "Crea una acción Failed que termina la ejecución"
  @spec failed(any()) :: Failed.t()
  def failed(reason), do: %Failed{reason: reason}

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
