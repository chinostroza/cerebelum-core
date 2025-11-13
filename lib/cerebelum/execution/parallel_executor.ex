defmodule Cerebelum.Execution.ParallelExecutor do
  @moduledoc """
  Executes multiple workflow tasks in parallel.

  This module handles:
  - Concurrent execution of multiple tasks using Task.async
  - Individual error handling for each task
  - Timeout enforcement
  - Result collection and merging
  - Event emission for parallel execution

  ## Usage

      # In a workflow step:
      def fetch_data(context, _) do
        tasks = [
          {:fetch_users, []},
          {:fetch_orders, []},
          {:fetch_products, []}
        ]
        {:parallel, tasks}
      end

  ## Return Format

  When a step returns `{:parallel, tasks}` or `{:parallel, tasks, initial_state}`:
  - `tasks` is a list of `{function_name, args}` tuples
  - Each task is executed concurrently
  - Results are merged into a map: `%{function_name: result, ...}`
  - If `initial_state` is provided, it's merged with task results

  ## Error Handling

  - Individual task errors don't crash other tasks
  - Failed tasks are recorded in events
  - If any task fails, the parallel execution fails
  - Partial results are available in events
  """

  require Logger

  alias Cerebelum.Events.{
    ParallelStartedEvent,
    ParallelTaskCompletedEvent,
    ParallelTaskFailedEvent,
    ParallelCompletedEvent
  }

  alias Cerebelum.EventStore

  @default_timeout 30_000

  @doc """
  Executes tasks in parallel.

  ## Parameters

  - `workflow_module` - The workflow module containing task functions
  - `task_specs` - List of `{function_name, args}` tuples
  - `context` - Current execution context
  - `parent_step` - Name of the step that initiated parallel execution
  - `execution_id` - Current execution ID
  - `opts` - Options:
    - `:timeout` - Max time to wait for all tasks (default: 30_000ms)
    - `:initial_version` - Starting event version

  ## Returns

  - `{:ok, merged_results, final_version}` - All tasks succeeded
  - `{:error, reason, partial_results, final_version}` - Some tasks failed
  """
  @spec execute_parallel(
          module(),
          [{atom(), list()}],
          map(),
          atom(),
          String.t(),
          keyword()
        ) :: {:ok, map(), non_neg_integer()} | {:error, term(), map(), non_neg_integer()}
  def execute_parallel(workflow_module, task_specs, context, parent_step, execution_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    version = Keyword.get(opts, :initial_version, 0)

    Logger.info("Starting parallel execution of #{length(task_specs)} tasks from step #{parent_step}")

    # Emit ParallelStartedEvent
    event = ParallelStartedEvent.new(execution_id, parent_step, task_specs, version)
    EventStore.append(execution_id, event, version)
    version = version + 1

    # Start all tasks
    start_time = System.monotonic_time(:millisecond)

    tasks =
      Enum.map(task_specs, fn {task_name, task_args} ->
        Task.async(fn ->
          execute_single_task(workflow_module, task_name, task_args, context)
        end)
      end)

    # Wait for all tasks to complete
    task_results =
      tasks
      |> Enum.zip(task_specs)
      |> Enum.map(fn {task, {task_name, _args}} ->
        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, result} ->
            {task_name, result}

          {:exit, reason} ->
            {task_name, {:error, {:task_exited, reason}}}

          nil ->
            {task_name, {:error, :timeout}}
        end
      end)

    total_duration = System.monotonic_time(:millisecond) - start_time

    # Process results and emit events
    {merged_results, errors, version} =
      process_task_results(task_results, parent_step, execution_id, version)

    # Emit completion event
    if Enum.empty?(errors) do
      event = ParallelCompletedEvent.new(execution_id, parent_step, merged_results, total_duration, version)
      EventStore.append(execution_id, event, version)
      version = version + 1

      Logger.info("Parallel execution completed successfully: #{length(task_results)} tasks")
      {:ok, merged_results, version}
    else
      # Some tasks failed
      Logger.error("Parallel execution had #{length(errors)} failures")
      first_error = List.first(errors)
      {:error, first_error, merged_results, version}
    end
  end

  # Private functions

  defp execute_single_task(workflow_module, task_name, task_args, context) do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Call the task function with context and provided args
      full_args = [context | task_args]
      result = apply(workflow_module, task_name, full_args)
      duration = System.monotonic_time(:millisecond) - start_time

      {:ok, result, duration}
    rescue
      exception ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:error, :exception, Exception.message(exception), duration}
    catch
      :exit, reason ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:error, :exit, inspect(reason), duration}

      :throw, value ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:error, :throw, inspect(value), duration}
    end
  end

  defp process_task_results(task_results, parent_step, execution_id, initial_version) do
    {results, errors, version} =
      Enum.reduce(task_results, {%{}, [], initial_version}, fn {task_name, result},
                                                                {acc_results, acc_errors, ver} ->
        case result do
          {:ok, task_result, duration} ->
            # Task succeeded - emit success event
            event =
              ParallelTaskCompletedEvent.new(
                execution_id,
                parent_step,
                task_name,
                task_result,
                duration,
                ver
              )

            EventStore.append(execution_id, event, ver)

            {Map.put(acc_results, task_name, task_result), acc_errors, ver + 1}

          {:error, error_kind, error_message, _duration} ->
            # Task failed - emit failure event
            event =
              ParallelTaskFailedEvent.new(
                execution_id,
                parent_step,
                task_name,
                error_kind,
                error_message,
                ver
              )

            EventStore.append(execution_id, event, ver)

            error = {:task_failed, task_name, error_kind, error_message}
            {acc_results, [error | acc_errors], ver + 1}

          {:error, reason} ->
            # Task failed without duration info
            event =
              ParallelTaskFailedEvent.new(
                execution_id,
                parent_step,
                task_name,
                :unknown,
                inspect(reason),
                ver
              )

            EventStore.append(execution_id, event, ver)

            error = {:task_failed, task_name, :unknown, inspect(reason)}
            {acc_results, [error | acc_errors], ver + 1}
        end
      end)

    {results, Enum.reverse(errors), version}
  end
end
