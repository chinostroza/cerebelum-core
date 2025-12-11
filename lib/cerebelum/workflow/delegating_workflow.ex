defmodule Cerebelum.WorkflowDelegatingWorkflow do
  @moduledoc """
  Workflow dinámico que delega la ejecución de steps a workers distribuidos.

  Este workflow actúa como un puente entre el Engine (que maneja orquestación,
  eventos, resurrection) y los Workers externos (Python, Kotlin, etc.) que
  ejecutan los steps individuales.

  ## Arquitectura

  ```
  Python Worker → gRPC ExecuteRequest
                    ↓
             execute_workflow()
                    ↓
             Execution.Supervisor.start_execution(WorkflowDelegatingWorkflow, ...)
                    ↓
             Engine ejecuta workflow:
               - Emite eventos (StepStartedEvent, StepCompletedEvent)
               - Delega steps a TaskRouter
               - Workers ejecutan steps
               - Engine procesa Sleep/Approval
               - Resurrection automática funciona ✅
  ```

  ## Ventajas

  - ✅ Workers de cualquier lenguaje aprovechan OTP/BEAM
  - ✅ Resurrection completa para workflows distribuidos
  - ✅ Sleep multi-día con hibernación
  - ✅ EventStore persistente
  - ✅ StateReconstructor funciona
  - ✅ WorkflowScheduler despierta workflows
  - ✅ Un solo camino de ejecución (no duplicamos código)

  ## Uso

  Este workflow NO se usa directamente por usuarios. Es usado internamente
  por `worker_service_server.ex` cuando recibe un `ExecuteRequest` via gRPC.

  El workflow se crea dinámicamente con el blueprint del workflow de Python/Kotlin.
  """

  use Cerebelum.Workflow
  require Logger

  @doc """
  Define el workflow dinámicamente basado en el blueprint.

  El blueprint contiene:
  - timeline: lista de steps
  - diverge_rules: reglas de divergencia
  - branch_rules: reglas de branching
  """
  workflow do
    # El timeline se define dinámicamente en runtime
    # Ver __workflow_metadata__/0
  end

  @doc false
  @impl true
  def __workflow_metadata__ do
    # Metadata mínima - el timeline real se inyecta en runtime
    # via el context con la key :blueprint
    %{
      timeline: [],
      diverges: %{},
      branches: %{},
      version: "dynamic"
    }
  end

  @doc """
  Ejecuta un step delegando al Worker via TaskRouter.

  Este es el punto de integración entre el Engine y los Workers distribuidos.

  ## Flujo

  1. Engine llama a esta función con el step a ejecutar
  2. Creamos una Task y la encolamos en TaskRouter
  3. Worker hace poll y recibe la Task
  4. Worker ejecuta el step
  5. Worker envía el resultado via submit_result
  6. Esperamos el resultado aquí (blocking)
  7. Procesamos el resultado (puede ser Sleep/Approval/Success/Error)
  8. Retornamos al Engine

  ## Returns

  - `{:ok, result}` - Step completado exitosamente
  - `{:error, reason}` - Step falló
  - `{:sleep, [milliseconds: X], data}` - Step pidió sleep
  - `{:approval, approval_data}` - Step pidió approval
  """
  def execute_step(context, step_name, step_inputs) do
    execution_id = context.execution_id
    workflow_module = Map.get(context, :workflow_module, "unknown")

    Logger.debug("Delegating step '#{step_name}' to worker for execution #{execution_id}")

    # 1. Crear task para el worker
    task = %{
      workflow_module: workflow_module,
      step_name: step_name,
      inputs: step_inputs,
      context: %{
        execution_id: execution_id,
        step_name: step_name
      }
    }

    # 2. Encolar task en TaskRouter
    case Cerebelum.Infrastructure.TaskRouter.queue_task(execution_id, task) do
      {:ok, task_id} ->
        Logger.debug("Task #{task_id} queued for step '#{step_name}'")

        # 3. Esperar resultado del worker (blocking)
        # Timeout: 5 minutos (configurable)
        timeout = :timer.minutes(5)

        case await_task_result(task_id, execution_id, timeout) do
          {:ok, result} ->
            Logger.debug("Step '#{step_name}' completed successfully")
            {:ok, result}

          {:sleep, duration_ms, data} ->
            Logger.info("Step '#{step_name}' requested sleep for #{duration_ms}ms")
            {:sleep, [milliseconds: duration_ms], data}

          {:approval, approval_data} ->
            Logger.info("Step '#{step_name}' requested approval")
            {:approval, approval_data}

          {:error, reason} ->
            Logger.error("Step '#{step_name}' failed: #{inspect(reason)}")
            {:error, reason}

          {:timeout, _} ->
            Logger.error("Step '#{step_name}' timed out after #{timeout}ms")
            {:error, :task_timeout}
        end

      {:error, reason} ->
        Logger.error("Failed to queue task for step '#{step_name}': #{inspect(reason)}")
        {:error, {:queue_failed, reason}}
    end
  end

  @doc """
  Espera el resultado de una task ejecutada por un worker.

  Esta función bloquea hasta que:
  1. El worker completa la task y envía el resultado
  2. Se alcanza el timeout

  ## Implementación

  Usamos el GenServer del Engine como receptor de mensajes.
  Cuando el worker llama `submit_result`, enviamos un mensaje
  al proceso del Engine con el resultado.

  ## Returns

  - `{:ok, result}` - Task completada
  - `{:sleep, duration_ms, data}` - Worker pidió sleep
  - `{:approval, approval_data}` - Worker pidió approval
  - `{:error, reason}` - Task falló
  - `{:timeout, task_id}` - Timeout alcanzado
  """
  defp await_task_result(task_id, execution_id, timeout) do
    # Registrar que estamos esperando este task
    # El submit_result encontrará nuestro PID y nos enviará un mensaje
    registry_key = {:awaiting_task, execution_id, task_id}
    Registry.register(Cerebelum.Execution.Registry, registry_key, self())

    # Esperar el mensaje con el resultado
    receive do
      {:task_result, ^task_id, result} ->
        # Cleanup registry
        Registry.unregister(Cerebelum.Execution.Registry, registry_key)
        result

    after
      timeout ->
        # Cleanup registry
        Registry.unregister(Cerebelum.Execution.Registry, registry_key)
        {:timeout, task_id}
    end
  end

  @doc """
  Callback llamado desde worker_service_server cuando un worker envía resultado.

  Este es el punto de entrada para los resultados de workers.
  """
  def notify_task_result(execution_id, task_id, result) do
    registry_key = {:awaiting_task, execution_id, task_id}

    # Buscar el proceso que está esperando este task
    case Registry.lookup(Cerebelum.Execution.Registry, registry_key) do
      [{pid, _value}] ->
        # Enviar resultado al proceso esperando
        send(pid, {:task_result, task_id, result})
        :ok

      [] ->
        Logger.warning("No process awaiting task #{task_id} for execution #{execution_id}")
        {:error, :no_awaiter}
    end
  end

  @doc """
  Construye dinámicamente el workflow basado en el blueprint.

  Esta función se llama desde execute_workflow para crear un
  workflow con la estructura del blueprint de Python/Kotlin.

  ## Blueprint Structure

  ```elixir
  %{
    timeline: ["step1", "step2", "step3"],
    diverge_rules: [...],
    branch_rules: [...]
  }
  ```

  ## Returns

  Metadata del workflow con:
  - timeline: lista de steps del blueprint
  - diverges: reglas de divergencia convertidas
  - branches: reglas de branching convertidas
  """
  def build_from_blueprint(blueprint) do
    timeline = extract_timeline(blueprint)
    diverges = extract_diverges(blueprint)
    branches = extract_branches(blueprint)

    %{
      timeline: timeline,
      diverges: diverges,
      branches: branches,
      version: "dynamic-#{System.unique_integer()}"
    }
  end

  defp extract_timeline(%{definition: %{timeline: timeline}}) when is_list(timeline) do
    # Convertir steps de string a atoms
    Enum.map(timeline, fn
      %{name: name} -> String.to_atom(name)
      name when is_binary(name) -> String.to_atom(name)
      name when is_atom(name) -> name
    end)
  end
  defp extract_timeline(_), do: []

  defp extract_diverges(%{definition: %{diverge_rules: rules}}) when is_list(rules) do
    # Convertir diverge rules del blueprint al formato del Engine
    Enum.reduce(rules, %{}, fn rule, acc ->
      from_step = String.to_atom(rule.from_step)
      patterns = Enum.map(rule.patterns, fn pattern ->
        {pattern.pattern, String.to_atom(pattern.target)}
      end)

      Map.put(acc, from_step, patterns)
    end)
  end
  defp extract_diverges(_), do: %{}

  defp extract_branches(%{definition: %{branch_rules: rules}}) when is_list(rules) do
    # Convertir branch rules del blueprint al formato del Engine
    Enum.reduce(rules, %{}, fn rule, acc ->
      from_step = String.to_atom(rule.from_step)
      branches = Enum.map(rule.branches, fn branch ->
        {branch.condition, String.to_atom(branch.target)}
      end)

      Map.put(acc, from_step, branches)
    end)
  end
  defp extract_branches(_), do: %{}
end
