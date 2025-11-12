defmodule Cerebelum.Context do
  @moduledoc """
  Context que fluye por toda la ejecución de un workflow.

  El Context es inmutable y contiene toda la información necesaria
  para ejecutar un workflow: identificadores, estado actual, inputs,
  y metadata.

  ## Ejemplo

      iex> ctx = Context.new(MyWorkflow, %{order_id: "123"})
      iex> ctx = Context.advance_to_step(ctx, :validate_order)
      iex> ctx.current_step
      :validate_order
  """

  @enforce_keys [:execution_id, :workflow_module, :workflow_version, :started_at]
  defstruct [
    # Obligatorios
    :execution_id,
    :workflow_module,
    :workflow_version,
    :started_at,

    # Opcionales con defaults
    inputs: %{},
    current_step: nil,
    retry_count: 0,
    iteration: 0,
    tags: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
    execution_id: String.t(),
    workflow_module: module(),
    workflow_version: String.t(),
    started_at: DateTime.t(),
    inputs: map(),
    current_step: atom() | nil,
    retry_count: non_neg_integer(),
    iteration: non_neg_integer(),
    tags: list(atom()),
    metadata: map()
  }

  @doc """
  Crea un nuevo Context para una ejecución de workflow.

  ## Parámetros

  - `workflow_module` - Módulo del workflow (ej: `ProcessOrder`)
  - `inputs` - Map con los inputs iniciales
  - `opts` - Keyword list con opciones:
    - `:workflow_version` - Versión del workflow (default: hash del módulo)

  ## Ejemplos

      iex> Context.new(MyWorkflow, %{order_id: "123"})
      %Context{workflow_module: MyWorkflow, inputs: %{order_id: "123"}, ...}

      iex> Context.new(MyWorkflow, %{}, workflow_version: "v1.2.3")
      %Context{workflow_version: "v1.2.3", ...}
  """
  @spec new(module(), map(), keyword()) :: t()
  def new(workflow_module, inputs, opts \\ []) do
    %__MODULE__{
      execution_id: generate_uuid(),
      workflow_module: workflow_module,
      workflow_version: Keyword.get(opts, :workflow_version, compute_version(workflow_module)),
      started_at: DateTime.utc_now(),
      inputs: inputs
    }
  end

  @doc """
  Avanza el contexto al siguiente step.

  ## Ejemplos

      iex> ctx = Context.new(MyWorkflow, %{})
      iex> ctx = Context.advance_to_step(ctx, :validate_order)
      iex> ctx.current_step
      :validate_order
  """
  @spec advance_to_step(t(), atom()) :: t()
  def advance_to_step(context, step_name) do
    %{context | current_step: step_name}
  end

  @doc """
  Incrementa el contador de reintentos.

  ## Ejemplos

      iex> ctx = Context.new(MyWorkflow, %{})
      iex> ctx = Context.increment_retry(ctx)
      iex> ctx.retry_count
      1
  """
  @spec increment_retry(t()) :: t()
  def increment_retry(context) do
    %{context | retry_count: context.retry_count + 1}
  end

  @doc """
  Incrementa el contador de iteraciones.

  ## Ejemplos

      iex> ctx = Context.new(MyWorkflow, %{})
      iex> ctx = Context.increment_iteration(ctx)
      iex> ctx.iteration
      1
  """
  @spec increment_iteration(t()) :: t()
  def increment_iteration(context) do
    %{context | iteration: context.iteration + 1}
  end

  @doc """
  Agrega un tag al contexto (sin duplicados).

  ## Ejemplos

      iex> ctx = Context.new(MyWorkflow, %{})
      iex> ctx = Context.add_tag(ctx, :urgent)
      iex> :urgent in ctx.tags
      true
  """
  @spec add_tag(t(), atom()) :: t()
  def add_tag(context, tag) do
    if tag in context.tags do
      context
    else
      %{context | tags: [tag | context.tags]}
    end
  end

  @doc """
  Agrega metadata al contexto.

  ## Ejemplos

      iex> ctx = Context.new(MyWorkflow, %{})
      iex> ctx = Context.put_metadata(ctx, :user_id, "user-123")
      iex> ctx.metadata[:user_id]
      "user-123"
  """
  @spec put_metadata(t(), atom(), any()) :: t()
  def put_metadata(context, key, value) do
    %{context | metadata: Map.put(context.metadata, key, value)}
  end

  # Privadas

  defp generate_uuid do
    # Generar UUID v4 simple
    <<u0, u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15>> =
      :crypto.strong_rand_bytes(16)

    :io_lib.format(
      "~2.16.0b~2.16.0b~2.16.0b~2.16.0b-~2.16.0b~2.16.0b-~2.16.0b~2.16.0b-~2.16.0b~2.16.0b-~2.16.0b~2.16.0b~2.16.0b~2.16.0b~2.16.0b~2.16.0b",
      [u0, u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15]
    )
    |> to_string()
  end

  defp compute_version(module) do
    # Por ahora retornar "default"
    # En el futuro, calcular SHA256 del bytecode
    "default-#{module}"
  end
end
