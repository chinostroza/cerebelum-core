defmodule Cerebelum.Execution.BranchHandler do
  @moduledoc """
  Maneja la evaluación de bloques `branch` durante la ejecución de workflows.

  Los bloques branch se usan para decisiones de lógica de negocio que
  determinan el camino que debe seguir el workflow. A diferencia de diverge
  (que maneja errores), branch se usa para routing basado en datos.

  ## Ejemplo de Branch

      branch after: calculate_risk(), on: result do
        result.score > 0.8 -> skip_to(:high_risk_path)
        result.score > 0.5 -> skip_to(:medium_risk_path)
        true -> continue()
      end

  ## Arquitectura

  El BranchHandler:
  1. Revisa si hay un branch definido para el step actual
  2. Evalúa las condiciones del branch usando CondEvaluator
  3. Retorna la acción correspondiente (continue, skip_to)

  ## Uso

      alias Cerebelum.Execution.BranchHandler

      # Después de ejecutar un step
      result = %{score: 0.9, threshold: 0.8}
      step_name = :calculate_risk

      case BranchHandler.evaluate(workflow_metadata, step_name, result) do
        {:continue, _} ->
          # Continuar al siguiente step

        {:skip_to, target_step} ->
          # Saltar a un step específico

        :no_branch ->
          # No hay branch definido, continuar normal
      end
  """

  alias Cerebelum.{CondEvaluator, FlowAction}

  require Logger

  @doc """
  Evalúa el bloque branch para un step, si existe.

  ## Parámetros

  - `workflow_metadata` - Metadata del workflow que contiene los branches
  - `step_name` - Nombre del step que acaba de ejecutarse
  - `step_result` - Resultado del step (disponible como bindings)

  ## Retorna

  - `{:continue, nil}` - Continuar al siguiente step (acción continue)
  - `{:skip_to, target_step}` - Saltar a un step específico (acción skip_to)
  - `:no_branch` - No hay branch definido para este step

  ## Ejemplos

      iex> metadata = %{
      ...>   branches: %{
      ...>     calculate_risk: [
      ...>       {quote(do: result.score > 0.8), :high_risk},
      ...>       {quote(do: true), :low_risk}
      ...>     ]
      ...>   }
      ...> }
      iex> result = %{score: 0.9}
      iex> BranchHandler.evaluate(metadata, :calculate_risk, result)
      {:skip_to, :high_risk}

      iex> metadata = %{
      ...>   branches: %{
      ...>     calculate_risk: [
      ...>       {quote(do: result.score > 0.8), :high_risk}
      ...>     ]
      ...>   }
      ...> }
      iex> result = %{score: 0.5}
      iex> BranchHandler.evaluate(metadata, :calculate_risk, result)
      {:continue, nil}

      iex> metadata = %{branches: %{}}
      iex> BranchHandler.evaluate(metadata, :other_step, %{})
      :no_branch
  """
  @spec evaluate(map(), atom(), any()) ::
          {:continue, nil}
          | {:skip_to, atom()}
          | :no_branch
  def evaluate(workflow_metadata, step_name, step_result) do
    case get_branch_for_step(workflow_metadata, step_name) do
      nil ->
        :no_branch

      branch_conditions ->
        evaluate_branch_conditions(branch_conditions, step_result, step_name)
    end
  end

  @doc """
  Obtiene las condiciones branch para un step específico.

  ## Parámetros

  - `workflow_metadata` - Metadata del workflow
  - `step_name` - Nombre del step

  ## Retorna

  - Lista de `{condition_ast, action}` tuples si hay branch
  - `nil` si no hay branch para este step
  """
  @spec get_branch_for_step(map(), atom()) :: [{Macro.t(), atom()}] | nil
  def get_branch_for_step(%{branches: branches}, step_name) when is_map(branches) do
    Map.get(branches, step_name)
  end

  def get_branch_for_step(_, _), do: nil

  ## Private Functions

  # Evalúa las condiciones del branch contra el resultado del step
  defp evaluate_branch_conditions(conditions, step_result, step_name) do
    # Convertir step_result a bindings map
    bindings = result_to_bindings(step_result)

    case CondEvaluator.evaluate(conditions, bindings) do
      {:ok, action} ->
        handle_branch_action(action, step_name, step_result)

      :no_match ->
        # Ninguna condición fue true, continuar normalmente
        Logger.debug("No branch condition matched for #{step_name}, continuing")
        {:continue, nil}
    end
  end

  # Convierte el resultado del step en bindings para el CondEvaluator
  # Si result es un map, se usa directamente
  # Si result es {:ok, value}, se usa %{result: value}
  # Cualquier otro valor se pone en %{result: value}
  defp result_to_bindings({:ok, value}) when is_map(value) do
    Map.put(value, :result, value)
  end

  defp result_to_bindings({:ok, value}) do
    %{result: value}
  end

  defp result_to_bindings(value) when is_map(value) do
    Map.put(value, :result, value)
  end

  defp result_to_bindings(value) do
    %{result: value}
  end

  # Convierte la acción branch en una acción del handler
  defp handle_branch_action(:continue, _step_name, _step_result) do
    Logger.debug("Branch action :continue, proceeding to next step")
    {:continue, nil}
  end

  # Manejo de FlowAction structs
  defp handle_branch_action(%FlowAction.Continue{}, _step_name, _step_result) do
    Logger.debug("Branch action Continue, proceeding to next step")
    {:continue, nil}
  end

  defp handle_branch_action(%FlowAction.SkipTo{step: target}, step_name, _step_result) do
    Logger.info("Branch from #{step_name} taking path to #{target}")
    {:skip_to, target}
  end

  # Atoms como targets directos (ej: :high_risk en lugar de FlowAction.skip_to(:high_risk))
  defp handle_branch_action(target, step_name, _step_result) when is_atom(target) do
    Logger.info("Branch from #{step_name} taking path to #{target}")
    {:skip_to, target}
  end

  # Acción desconocida
  defp handle_branch_action(unknown, step_name, _step_result) do
    Logger.warning(
      "Unknown branch action #{inspect(unknown)} for #{step_name}, continuing normally"
    )

    {:continue, nil}
  end
end
