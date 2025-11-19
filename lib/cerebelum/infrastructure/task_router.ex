defmodule Cerebelum.Infrastructure.TaskRouter do
  @moduledoc """
  Pull-based task distribution and routing for SDK workers.
  
  Features:
  - Pull-based: Workers poll for tasks (not push-based)
  - Long-polling: Workers can block up to 30s waiting for tasks
  - Sticky routing: Steps of same execution go to same worker (cache locality)
  - Fallback: If preferred worker unavailable, route to any idle worker
  - Task reassignment: When worker dies, reassign its pending tasks
  - Queue management: Queue tasks when no workers available
  
  Architecture:
  - ETS tables for fast concurrent access
  - GenServer for coordination and state management
  - Long-polling implemented via process messaging
  """

  use GenServer
  require Logger

  @max_long_poll_timeout_ms 30_000  # Max 30 seconds
  @default_timeout_ms 10_000  # Default 10 seconds
  @default_task_timeout_ms 300_000  # 5 minutes default task timeout
  @max_retries 3  # Maximum retry attempts per task
  @retry_backoff_base_ms 1000  # Base backoff for retries (exponential)

  @task_queue_table :task_queue
  @execution_worker_mapping_table :execution_worker_mapping
  @pending_polls_table :pending_polls
  @task_metadata_table :task_metadata
  @active_tasks_table :active_tasks  # Track assigned tasks for timeout monitoring

  # Client API

  @doc """
  Start the TaskRouter GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queue a task for execution by SDK workers.

  ## Parameters
  - execution_id: The workflow execution ID
  - task: Task details (step_name, inputs, context)

  ## Returns
  - {:ok, task_id} on success
  """
  def queue_task(execution_id, task) do
    GenServer.call(__MODULE__, {:queue_task, execution_id, task})
  end

  @doc """
  Queue initial tasks for a workflow execution.

  Creates tasks for the initial steps in the workflow timeline that have no dependencies.

  ## Parameters
  - execution_id: The workflow execution ID
  - workflow_module: The workflow module atom
  - initial_steps: List of step names to enqueue
  - inputs: Workflow inputs

  ## Returns
  - {:ok, [task_ids]} on success
  """
  def queue_initial_tasks(execution_id, workflow_module, initial_steps, inputs) do
    task_ids = Enum.map(initial_steps, fn step_name ->
      task = %{
        workflow_module: workflow_module,
        step_name: step_name,
        inputs: inputs,
        context: %{}
      }

      {:ok, task_id} = queue_task(execution_id, task)
      task_id
    end)

    {:ok, task_ids}
  end

  @doc """
  Poll for next available task (long-polling support).
  
  Workers call this to get work. If no task is available immediately,
  the call will block up to timeout_ms waiting for a task to become available.
  
  ## Parameters
  - worker_id: Worker requesting task
  - timeout_ms: How long to wait for task (max 30s)
  
  ## Returns
  - {:ok, task} if task available
  - {:error, :timeout} if no task available within timeout
  """
  def poll_for_task(worker_id, timeout_ms \\ @default_timeout_ms) do
    timeout = min(timeout_ms, @max_long_poll_timeout_ms)
    GenServer.call(__MODULE__, {:poll_for_task, worker_id, timeout}, timeout + 1000)
  end

  @doc """
  Submit task result from worker.
  
  Marks the task as completed and notifies the execution engine.
  
  ## Parameters
  - task_id: Task identifier
  - worker_id: Worker that completed the task
  - result: Task result data
  """
  def submit_result(task_id, worker_id, result) do
    GenServer.call(__MODULE__, {:submit_result, task_id, worker_id, result})
  end

  @doc """
  Cancel pending tasks for an execution.
  
  Used when execution is cancelled or fails.
  """
  def cancel_tasks(execution_id) do
    GenServer.call(__MODULE__, {:cancel_tasks, execution_id})
  end

  @doc """
  Get statistics about task queue and routing.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables for task management
    :ets.new(@task_queue_table, [:named_table, :bag, :public, read_concurrency: true])
    :ets.new(@execution_worker_mapping_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@pending_polls_table, [:named_table, :bag, :public])
    :ets.new(@task_metadata_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@active_tasks_table, [:named_table, :set, :public, read_concurrency: true])

    Logger.info("TaskRouter started")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:queue_task, execution_id, task}, _from, state) do
    task_id = generate_task_id()
    retry_count = Map.get(task, :retry_count, 0)

    task_with_id = Map.merge(task, %{
      task_id: task_id,
      execution_id: execution_id,
      queued_at: System.system_time(:millisecond),
      status: :pending,
      retry_count: retry_count
    })

    # Store task metadata for later lookup (including inputs/context for DLQ)
    metadata = %{
      step_name: Map.get(task, :step_name),
      workflow_module: Map.get(task, :workflow_module),
      execution_id: execution_id,
      retry_count: retry_count,
      inputs: Map.get(task, :inputs, %{}),
      context: Map.get(task, :context, %{})
    }
    :ets.insert(@task_metadata_table, {task_id, metadata})

    # Add to queue
    :ets.insert(@task_queue_table, {execution_id, task_with_id})

    Logger.debug("Task queued: #{task_id} for execution #{execution_id}, step: #{metadata.step_name}, retry: #{retry_count}")

    # Check if any workers are waiting (long-polling)
    notify_waiting_workers(execution_id)

    {:reply, {:ok, task_id}, state}
  end

  @impl true
  def handle_call({:poll_for_task, worker_id, timeout_ms}, from, state) do
    case get_next_task_for_worker(worker_id) do
      {:ok, task} ->
        # Task available immediately - track it for timeout monitoring
        track_assigned_task(task)
        Logger.debug("Task #{task.task_id} assigned to worker #{worker_id}")
        {:reply, {:ok, task}, state}

      :no_tasks ->
        # No task available, implement long-polling
        # Store the pending poll request
        ref = make_ref()
        expires_at = System.system_time(:millisecond) + timeout_ms

        :ets.insert(@pending_polls_table, {worker_id, {ref, from, expires_at}})

        # Schedule timeout cleanup
        Process.send_after(self(), {:poll_timeout, worker_id, ref}, timeout_ms)

        Logger.debug("Worker #{worker_id} long-polling (timeout: #{timeout_ms}ms)")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:submit_result, task_id, worker_id, result}, _from, state) do
    Logger.info("Task result received: #{task_id} from worker #{worker_id}, status: #{result.status}")

    # Remove from active tasks (no longer needs timeout monitoring)
    :ets.delete(@active_tasks_table, task_id)

    # Look up task metadata to get step_name and workflow_module
    case :ets.lookup(@task_metadata_table, task_id) do
      [{^task_id, metadata}] ->
        # Clean up metadata after retrieval
        :ets.delete(@task_metadata_table, task_id)

        # Return metadata along with result for further processing
        {:reply, {:ok, metadata}, state}

      [] ->
        Logger.warning("Task metadata not found for task #{task_id}")
        {:reply, {:error, :task_not_found}, state}
    end
  end

  @impl true
  def handle_call({:cancel_tasks, execution_id}, _from, state) do
    # Remove all pending tasks for this execution
    :ets.match_delete(@task_queue_table, {execution_id, :_})
    
    Logger.info("Cancelled all tasks for execution #{execution_id}")
    
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    pending_tasks = :ets.tab2list(@task_queue_table) |> length()
    pending_polls = :ets.tab2list(@pending_polls_table) |> length()
    active_executions = :ets.tab2list(@execution_worker_mapping_table) |> length()
    
    stats = %{
      pending_tasks: pending_tasks,
      pending_polls: pending_polls,
      active_executions: active_executions
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_info({:poll_timeout, worker_id, ref}, state) do
    # Check if poll request still exists
    case :ets.match(@pending_polls_table, {worker_id, {ref, :"$1", :_}}) do
      [[from]] ->
        # Poll request still pending, send timeout response
        :ets.match_delete(@pending_polls_table, {worker_id, {ref, :_, :_}})
        GenServer.reply(from, {:error, :timeout})
        Logger.debug("Worker #{worker_id} poll timeout")

      [] ->
        # Already handled (task was assigned)
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:task_timeout, task_id}, state) do
    # Check if task is still active (hasn't been completed)
    case :ets.lookup(@active_tasks_table, task_id) do
      [{^task_id, task_info}] ->
        Logger.warning("Task #{task_id} timed out after #{@default_task_timeout_ms}ms")

        # Remove from active tasks
        :ets.delete(@active_tasks_table, task_id)

        # Look up metadata to determine if we should retry
        case :ets.lookup(@task_metadata_table, task_id) do
          [{^task_id, metadata}] ->
            retry_count = Map.get(metadata, :retry_count, 0)

            if retry_count < @max_retries do
              # Retry the task
              Logger.info("Retrying task #{task_id}, attempt #{retry_count + 1}/#{@max_retries}")
              retry_task(task_info, retry_count + 1)
            else
              # Max retries exceeded - move to DLQ and fail the execution
              Logger.error("Task #{task_id} exceeded max retries (#{@max_retries}), moving to DLQ")

              execution_id = Map.get(metadata, :execution_id)
              step_name = Map.get(metadata, :step_name)
              workflow_module = Map.get(metadata, :workflow_module)

              # Add task to DLQ
              error = %{
                kind: "timeout",
                message: "Task timed out after #{@max_retries} retries",
                stacktrace: ""
              }

              dlq_task_info = %{
                task_id: task_id,
                execution_id: execution_id,
                workflow_module: workflow_module,
                step_name: step_name,
                inputs: task_info.inputs,
                context: task_info.context,
                retry_count: retry_count
              }

              Cerebelum.Infrastructure.DLQ.add_to_dlq(dlq_task_info, error)

              # Clean up task metadata
              :ets.delete(@task_metadata_table, task_id)

              # Fail the execution
              Cerebelum.Infrastructure.ExecutionStateManager.fail_execution(
                execution_id,
                "Task #{step_name} (#{task_id}) timed out after #{@max_retries} retries - moved to DLQ"
              )

              # Cancel all other tasks for this execution
              cancel_tasks(execution_id)
            end

          [] ->
            # Metadata already cleaned up (shouldn't happen, but handle gracefully)
            Logger.warning("Task metadata not found for timed out task #{task_id}")
        end

      [] ->
        # Task already completed or cleaned up
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:requeue_task, execution_id, task_info, retry_count}, state) do
    # Re-queue the task with incremented retry count
    retry_task_data = %{
      workflow_module: task_info.workflow_module,
      step_name: task_info.step_name,
      inputs: task_info.inputs,
      context: task_info.context,
      retry_count: retry_count
    }

    {:ok, _task_id} = queue_task(execution_id, retry_task_data)

    Logger.info("Task re-queued for execution #{execution_id}, step: #{task_info.step_name}, retry: #{retry_count}")

    {:noreply, state}
  end

  # Private Functions

  defp get_next_task_for_worker(worker_id) do
    # 1. Try sticky routing first (tasks from executions this worker already handles)
    case get_sticky_task(worker_id) do
      {:ok, task} -> {:ok, task}
      :no_sticky_tasks ->
        # 2. Get any available task
        get_any_task(worker_id)
    end
  end

  defp get_sticky_task(worker_id) do
    # Get executions this worker is handling
    case :ets.lookup(@execution_worker_mapping_table, worker_id) do
      [] ->
        :no_sticky_tasks
        
      executions ->
        # Check if any of these executions have pending tasks
        execution_ids = Enum.map(executions, fn {_, exec_id} -> exec_id end)
        
        Enum.find_value(execution_ids, :no_sticky_tasks, fn exec_id ->
          case pop_task_for_execution(exec_id, worker_id) do
            {:ok, task} -> {:ok, task}
            :empty -> nil
          end
        end)
    end
  end

  defp get_any_task(worker_id) do
    # Get first available task from queue
    case :ets.first(@task_queue_table) do
      :"$end_of_table" ->
        :no_tasks
        
      execution_id ->
        pop_task_for_execution(execution_id, worker_id)
    end
  end

  defp pop_task_for_execution(execution_id, worker_id) do
    case :ets.lookup(@task_queue_table, execution_id) do
      [] ->
        :empty
        
      [{^execution_id, task} | _] ->
        # Remove task from queue
        :ets.delete_object(@task_queue_table, {execution_id, task})
        
        # Record that this worker is handling this execution (sticky routing)
        :ets.insert(@execution_worker_mapping_table, {worker_id, execution_id})
        
        {:ok, task}
    end
  end

  defp notify_waiting_workers(execution_id) do
    # Get worker that's already handling this execution (sticky routing)
    case :ets.match(@execution_worker_mapping_table, {:"$1", execution_id}) do
      [[preferred_worker_id]] ->
        # Notify preferred worker if they're waiting
        notify_worker_if_waiting(preferred_worker_id)
        
      [] ->
        # No preferred worker, notify any waiting worker
        notify_any_waiting_worker()
    end
  end

  defp notify_worker_if_waiting(worker_id) do
    case :ets.lookup(@pending_polls_table, worker_id) do
      [] ->
        :ok

      [{^worker_id, {ref, from, _expires_at}} | _] ->
        # Worker is waiting, try to assign task
        case get_next_task_for_worker(worker_id) do
          {:ok, task} ->
            :ets.match_delete(@pending_polls_table, {worker_id, {ref, :_, :_}})
            # Track assigned task for timeout monitoring
            track_assigned_task(task)
            GenServer.reply(from, {:ok, task})
            Logger.debug("Task assigned to waiting worker #{worker_id}")

          :no_tasks ->
            # Race condition: task was taken by another thread
            :ok
        end
    end
  end

  defp notify_any_waiting_worker do
    case :ets.first(@pending_polls_table) do
      :"$end_of_table" ->
        :ok
        
      worker_id ->
        notify_worker_if_waiting(worker_id)
    end
  end

  defp track_assigned_task(task) do
    task_id = task.task_id

    # Store task info for timeout monitoring
    :ets.insert(@active_tasks_table, {task_id, task})

    # Schedule timeout check
    Process.send_after(self(), {:task_timeout, task_id}, @default_task_timeout_ms)

    Logger.debug("Tracking task #{task_id} for timeout (#{@default_task_timeout_ms}ms)")
  end

  defp retry_task(task_info, new_retry_count) do
    execution_id = task_info.execution_id

    # Calculate exponential backoff delay
    backoff_ms = @retry_backoff_base_ms * :math.pow(2, new_retry_count - 1) |> round()

    Logger.debug("Scheduling retry for task after #{backoff_ms}ms backoff")

    # Re-queue the task with updated retry count after backoff
    Process.send_after(self(), {:requeue_task, execution_id, task_info, new_retry_count}, backoff_ms)
  end

  defp generate_task_id do
    "task_#{System.unique_integer([:positive])}_#{:rand.uniform(999999)}"
  end
end
