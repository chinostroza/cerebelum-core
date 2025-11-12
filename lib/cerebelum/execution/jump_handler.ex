defmodule Cerebelum.Execution.JumpHandler do
  @moduledoc """
  Maneja los saltos (jumps) en el timeline del workflow.

  Los saltos permiten:
  - **back_to**: Volver a un step anterior (ej: retry, loops)
  - **skip_to**: Saltar a un step adelante (ej: skip logic, fast-forward)

  ## Protecciones

  - **Infinite Loop Detection**: Máximo 1000 iteraciones
  - **Timeline Validation**: El step destino debe existir en el timeline
  - **Results Cache**: Se limpia en back_to, se preserva en skip_to

  ## Arquitectura

  El JumpHandler:
  1. Valida que el step destino existe en el timeline
  2. Actualiza el índice del step actual
  3. Maneja el results cache según el tipo de salto
  4. Detecta loops infinitos

  ## Uso

      alias Cerebelum.Execution.JumpHandler

      # Back to (retry)
      case JumpHandler.jump_to_step(data, :back_to, :validate_order) do
        {:ok, new_data} ->
          # data actualizado con nuevo índice y cache limpio

        {:error, :step_not_found} ->
          # Step no existe en timeline

        {:error, :infinite_loop} ->
          # Demasiadas iteraciones
      end

      # Skip to (fast-forward)
      case JumpHandler.jump_to_step(data, :skip_to, :send_notification) do
        {:ok, new_data} ->
          # data actualizado, cache intacto
      end
  """

  alias Cerebelum.Execution.Engine.Data

  require Logger

  @max_iterations 1000

  @doc """
  Ejecuta un salto a un step específico en el timeline.

  ## Parámetros

  - `data` - Engine.Data con el estado actual de la ejecución
  - `jump_type` - `:back_to` o `:skip_to`
  - `target_step` - Nombre del step destino

  ## Retorna

  - `{:ok, new_data}` - Data actualizado con nuevo índice
  - `{:error, :step_not_found}` - Step no existe en timeline
  - `{:error, :infinite_loop}` - Demasiadas iteraciones (> #{@max_iterations})

  ## Ejemplos

      iex> timeline = [:step1, :step2, :step3]
      iex> data = %{timeline: timeline, current_step_index: 2, iteration: 0, results: %{}}
      iex> {:ok, new_data} = JumpHandler.jump_to_step(data, :back_to, :step1)
      iex> new_data.current_step_index
      0
      iex> new_data.iteration
      1
  """
  @spec jump_to_step(Data.t(), :back_to | :skip_to, atom()) ::
          {:ok, Data.t()} | {:error, :step_not_found | :infinite_loop}
  def jump_to_step(data, :back_to, target_step) do
    with {:ok, target_index} <- find_step_index(data.timeline, target_step),
         :ok <- check_iteration_limit(data.iteration + 1) do
      # Limpiar cache de resultados de steps después del target
      new_results = clear_results_after(data.results, data.timeline, target_index)

      new_data =
        data
        |> Data.update_current_step_index(target_index)
        |> Data.update_results(new_results)
        |> Data.increment_iteration()

      Logger.info(
        "Jumping back to #{target_step} (index: #{target_index}), iteration: #{new_data.iteration}"
      )

      {:ok, new_data}
    end
  end

  def jump_to_step(data, :skip_to, target_step) do
    with {:ok, target_index} <- find_step_index(data.timeline, target_step) do
      new_data = Data.update_current_step_index(data, target_index)

      Logger.info("Skipping to #{target_step} (index: #{target_index})")

      {:ok, new_data}
    end
  end

  @doc """
  Encuentra el índice de un step en el timeline.

  ## Parámetros

  - `timeline` - Lista de steps
  - `step_name` - Nombre del step a buscar

  ## Retorna

  - `{:ok, index}` - Índice del step (base 0)
  - `{:error, :step_not_found}` - Step no existe

  ## Ejemplos

      iex> JumpHandler.find_step_index([:step1, :step2, :step3], :step2)
      {:ok, 1}

      iex> JumpHandler.find_step_index([:step1, :step2], :step_not_found)
      {:error, :step_not_found}
  """
  @spec find_step_index([atom()], atom()) :: {:ok, non_neg_integer()} | {:error, :step_not_found}
  def find_step_index(timeline, step_name) do
    case Enum.find_index(timeline, &(&1 == step_name)) do
      nil ->
        Logger.error("Step #{step_name} not found in timeline: #{inspect(timeline)}")
        {:error, :step_not_found}

      index ->
        {:ok, index}
    end
  end

  @doc """
  Limpia los resultados de steps posteriores al índice dado.

  Esto es necesario en back_to para que los steps se re-ejecuten.

  ## Parámetros

  - `results` - Mapa de resultados actual
  - `timeline` - Lista de steps
  - `from_index` - Índice desde donde limpiar (inclusivo)

  ## Retorna

  - Nuevo mapa de resultados sin los steps posteriores

  ## Ejemplos

      iex> timeline = [:step1, :step2, :step3]
      iex> results = %{step1: :result1, step2: :result2, step3: :result3}
      iex> JumpHandler.clear_results_after(results, timeline, 1)
      %{step1: :result1}
  """
  @spec clear_results_after(map(), [atom()], non_neg_integer()) :: map()
  def clear_results_after(results, timeline, from_index) do
    # Obtener steps que deben mantenerse (antes del from_index)
    steps_to_keep =
      timeline
      |> Enum.take(from_index)
      |> MapSet.new()

    # Filtrar resultados
    results
    |> Enum.filter(fn {step_name, _value} ->
      MapSet.member?(steps_to_keep, step_name)
    end)
    |> Enum.into(%{})
  end

  @doc """
  Verifica que no se haya excedido el límite de iteraciones.

  ## Parámetros

  - `iteration` - Número de iteración actual

  ## Retorna

  - `:ok` - Dentro del límite
  - `{:error, :infinite_loop}` - Límite excedido

  ## Ejemplos

      iex> JumpHandler.check_iteration_limit(10)
      :ok

      iex> JumpHandler.check_iteration_limit(1001)
      {:error, :infinite_loop}
  """
  @spec check_iteration_limit(non_neg_integer()) :: :ok | {:error, :infinite_loop}
  def check_iteration_limit(iteration) when iteration > @max_iterations do
    Logger.error("Infinite loop detected: iteration #{iteration} > #{@max_iterations}")
    {:error, :infinite_loop}
  end

  def check_iteration_limit(_iteration), do: :ok

  @doc """
  Retorna el límite máximo de iteraciones permitidas.
  """
  @spec max_iterations() :: pos_integer()
  def max_iterations, do: @max_iterations
end
