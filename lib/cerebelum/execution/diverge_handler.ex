defmodule Cerebelum.Execution.DivergeHandler do
  @moduledoc """
  Maneja la evaluación de bloques `diverge` durante la ejecución de workflows.

  Los bloques diverge se usan para manejo de errores y control de flujo
  basado en el resultado de un step. Típicamente se usan para:

  - Retry en caso de timeout
  - Fail early en errores críticos
  - Skip steps en ciertas condiciones

  ## Ejemplo de Diverge

      diverge from: fetch_data() do
        :timeout -> :retry
        {:error, :network} -> :retry
        {:error, _} -> :failed
      end

  ## Arquitectura

  El DivergeHandler:
  1. Revisa si hay un diverge definido para el step actual
  2. Evalúa el patrón del resultado contra las cláusulas diverge
  3. Retorna la acción correspondiente (continue, back_to, failed)

  ## Uso

      alias Cerebelum.Execution.DivergeHandler

      # Después de ejecutar un step
      result = {:error, :timeout}
      step_name = :fetch_data

      case DivergeHandler.evaluate(workflow_metadata, step_name, result) do
        {:continue, _} ->
          # Continuar al siguiente step

        {:back_to, target_step} ->
          # Volver a step anterior (retry)

        {:failed, reason} ->
          # Terminar ejecución con error

        :no_diverge ->
          # No hay diverge definido, continuar normal
      end
  """

  alias Cerebelum.{PatternMatcher, FlowAction}

  require Logger

  @doc """
  Evalúa el bloque diverge para un step, si existe.

  ## Parámetros

  - `workflow_metadata` - Metadata del workflow que contiene los diverges
  - `step_name` - Nombre del step que acaba de ejecutarse
  - `step_result` - Resultado del step

  ## Retorna

  - `{:continue, nil}` - Continuar al siguiente step (acción continue)
  - `{:back_to, target_step}` - Volver a un step anterior (acción back_to)
  - `{:failed, reason}` - Terminar con error (acción failed)
  - `:no_diverge` - No hay diverge definido para este step

  ## Ejemplos

      iex> metadata = %{diverges: %{fetch_data: [{:timeout, :retry}]}}
      iex> DivergeHandler.evaluate(metadata, :fetch_data, :timeout)
      {:back_to, :fetch_data}

      iex> metadata = %{diverges: %{fetch_data: [{:timeout, :retry}]}}
      iex> DivergeHandler.evaluate(metadata, :fetch_data, {:ok, "data"})
      {:continue, nil}

      iex> metadata = %{diverges: %{fetch_data: [{:timeout, :retry}]}}
      iex> DivergeHandler.evaluate(metadata, :other_step, :timeout)
      :no_diverge
  """
  @spec evaluate(map(), atom(), any()) ::
          {:continue, nil}
          | {:back_to, atom()}
          | {:skip_to, atom()}
          | {:failed, any()}
          | :no_diverge
  def evaluate(workflow_metadata, step_name, step_result) do
    case get_diverge_for_step(workflow_metadata, step_name) do
      nil ->
        :no_diverge

      diverge_patterns ->
        evaluate_diverge_patterns(diverge_patterns, step_result, step_name)
    end
  end

  @doc """
  Obtiene las cláusulas diverge para un step específico.

  ## Parámetros

  - `workflow_metadata` - Metadata del workflow
  - `step_name` - Nombre del step

  ## Retorna

  - Lista de `{pattern, action}` tuples si hay diverge
  - `nil` si no hay diverge para este step
  """
  @spec get_diverge_for_step(map(), atom()) :: [{any(), atom()}] | nil
  def get_diverge_for_step(%{diverges: diverges}, step_name) when is_map(diverges) do
    Map.get(diverges, step_name)
  end

  def get_diverge_for_step(_, _), do: nil

  ## Private Functions

  # Evalúa las cláusulas del diverge contra el resultado del step
  defp evaluate_diverge_patterns(patterns, step_result, step_name) do
    case PatternMatcher.match(patterns, step_result) do
      {:ok, action} ->
        handle_diverge_action(action, step_name, step_result)

      :no_match ->
        # Ningún patrón matcheó, continuar normalmente
        Logger.debug("No diverge pattern matched for #{step_name}, continuing")
        {:continue, nil}
    end
  end

  # Convierte la acción diverge en una acción del handler
  defp handle_diverge_action(:retry, step_name, _step_result) do
    Logger.info("Diverge action :retry for #{step_name}, going back to #{step_name}")
    {:back_to, step_name}
  end

  defp handle_diverge_action(:failed, _step_name, step_result) do
    Logger.info("Diverge action :failed, terminating execution")
    {:failed, step_result}
  end

  defp handle_diverge_action(:continue, _step_name, _step_result) do
    Logger.debug("Diverge action :continue, proceeding to next step")
    {:continue, nil}
  end

  # Manejo de FlowAction structs
  defp handle_diverge_action(%FlowAction.Continue{}, _step_name, _step_result) do
    Logger.debug("Diverge action Continue, proceeding to next step")
    {:continue, nil}
  end

  defp handle_diverge_action(%FlowAction.BackTo{step: target}, _step_name, _step_result) do
    Logger.info("Diverge action BackTo #{target}")
    {:back_to, target}
  end

  defp handle_diverge_action(%FlowAction.SkipTo{step: target}, _step_name, _step_result) do
    Logger.info("Diverge action SkipTo #{target}")
    {:skip_to, target}
  end

  defp handle_diverge_action(%FlowAction.Failed{reason: reason}, _step_name, _step_result) do
    Logger.info("Diverge action Failed: #{inspect(reason)}")
    {:failed, reason}
  end

  # Acción desconocida
  defp handle_diverge_action(unknown, step_name, _step_result) do
    Logger.warning(
      "Unknown diverge action #{inspect(unknown)} for #{step_name}, continuing normally"
    )

    {:continue, nil}
  end
end
