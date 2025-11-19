defmodule Cerebelum.Infrastructure.DLQ do
  @moduledoc """
  Dead Letter Queue (DLQ) for managing tasks that have failed after max retries.

  Features:
  - Persist failed tasks to database
  - Manual retry of failed tasks
  - Resolution tracking
  - Metrics and telemetry

  Tasks are moved to DLQ when they exceed the maximum retry count (3 attempts).
  DLQ items can be:
  - Listed and filtered by status, execution_id, workflow_module
  - Manually retried (requeued to TaskRouter)
  - Marked as resolved
  """

  use GenServer
  require Logger
  alias Cerebelum.Infrastructure.Schemas.DLQItem
  alias Cerebelum.Repo
  import Ecto.Query

  # Client API

  @doc """
  Start the DLQ GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a task to the DLQ after max retries exceeded.

  ## Parameters
  - task_info: Map containing task details (from TaskRouter)
    - task_id: Task identifier
    - execution_id: Execution identifier
    - workflow_module: Workflow module name
    - step_name: Step name
    - inputs: Task inputs
    - context: Task context
    - retry_count: Number of retry attempts
  - error: Map containing error details
    - kind: Error kind (e.g., "timeout", "exception")
    - message: Error message
    - stacktrace: Error stacktrace (optional)

  ## Returns
  - {:ok, dlq_item_id}
  """
  def add_to_dlq(task_info, error) do
    GenServer.call(__MODULE__, {:add_to_dlq, task_info, error})
  end

  @doc """
  List DLQ items with optional filters.

  ## Parameters
  - opts: Keyword list of filters
    - status: Filter by status ("pending", "retried", "resolved", "failed")
    - execution_id: Filter by execution ID
    - workflow_module: Filter by workflow module
    - limit: Maximum number of items to return (default: 100)
    - offset: Offset for pagination (default: 0)

  ## Returns
  - {:ok, [dlq_items]}
  """
  def list_items(opts \\ []) do
    GenServer.call(__MODULE__, {:list_items, opts})
  end

  @doc """
  Get a single DLQ item by ID.

  ## Returns
  - {:ok, dlq_item} if found
  - {:error, :not_found} if not found
  """
  def get_item(dlq_item_id) do
    GenServer.call(__MODULE__, {:get_item, dlq_item_id})
  end

  @doc """
  Retry a DLQ item by requeuing it to the TaskRouter.

  ## Parameters
  - dlq_item_id: DLQ item ID to retry
  - retried_by: User or system identifier that triggered the retry

  ## Returns
  - {:ok, task_id} if successful
  - {:error, reason} if failed
  """
  def retry_item(dlq_item_id, retried_by \\ "system") do
    GenServer.call(__MODULE__, {:retry_item, dlq_item_id, retried_by})
  end

  @doc """
  Mark a DLQ item as resolved without retrying.

  ## Parameters
  - dlq_item_id: DLQ item ID to resolve
  - resolved_by: User or system identifier that resolved the item
  - reason: Optional reason for resolution

  ## Returns
  - {:ok, dlq_item}
  - {:error, reason}
  """
  def resolve_item(dlq_item_id, resolved_by, reason \\ nil) do
    GenServer.call(__MODULE__, {:resolve_item, dlq_item_id, resolved_by, reason})
  end

  @doc """
  Get DLQ statistics.

  ## Returns
  - Map with counts by status
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("DLQ started")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:add_to_dlq, task_info, error}, _from, state) do
    dlq_attrs = %{
      task_id: task_info.task_id,
      execution_id: task_info.execution_id,
      workflow_module: to_string(task_info.workflow_module),
      step_name: task_info.step_name,
      error_kind: Map.get(error, :kind),
      error_message: Map.get(error, :message),
      error_stacktrace: Map.get(error, :stacktrace),
      retry_count: task_info.retry_count,
      task_inputs: task_info.inputs,
      task_context: task_info.context,
      status: "pending"
    }

    case %DLQItem{}
         |> DLQItem.changeset(dlq_attrs)
         |> Repo.insert() do
      {:ok, dlq_item} ->
        Logger.warning("Task moved to DLQ: #{task_info.task_id} (execution: #{task_info.execution_id}, step: #{task_info.step_name})")

        # Emit telemetry
        :telemetry.execute(
          [:cerebelum, :dlq, :item_added],
          %{count: 1},
          %{
            workflow_module: task_info.workflow_module,
            step_name: task_info.step_name,
            error_kind: Map.get(error, :kind)
          }
        )

        {:reply, {:ok, dlq_item.id}, state}

      {:error, changeset} ->
        Logger.error("Failed to add task to DLQ: #{inspect(changeset.errors)}")
        {:reply, {:error, :insert_failed}, state}
    end
  end

  @impl true
  def handle_call({:list_items, opts}, _from, state) do
    query = from(d in DLQItem)

    # Apply filters
    query =
      if status = Keyword.get(opts, :status) do
        from(d in query, where: d.status == ^status)
      else
        query
      end

    query =
      if execution_id = Keyword.get(opts, :execution_id) do
        from(d in query, where: d.execution_id == ^execution_id)
      else
        query
      end

    query =
      if workflow_module = Keyword.get(opts, :workflow_module) do
        from(d in query, where: d.workflow_module == ^workflow_module)
      else
        query
      end

    # Apply ordering (most recent first)
    query = from(d in query, order_by: [desc: d.inserted_at])

    # Apply pagination
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    query = from(d in query, limit: ^limit, offset: ^offset)

    items = Repo.all(query)

    {:reply, {:ok, items}, state}
  end

  @impl true
  def handle_call({:get_item, dlq_item_id}, _from, state) do
    case Repo.get(DLQItem, dlq_item_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      dlq_item ->
        {:reply, {:ok, dlq_item}, state}
    end
  end

  @impl true
  def handle_call({:retry_item, dlq_item_id, retried_by}, _from, state) do
    case Repo.get(DLQItem, dlq_item_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      dlq_item ->
        if dlq_item.status != "pending" do
          {:reply, {:error, :already_processed}, state}
        else
          # Requeue the task to TaskRouter
          task = %{
            workflow_module: String.to_atom(dlq_item.workflow_module),
            step_name: dlq_item.step_name,
            inputs: dlq_item.task_inputs,
            context: dlq_item.task_context,
            retry_count: 0  # Reset retry count for manual retry
          }

          case Cerebelum.Infrastructure.TaskRouter.queue_task(dlq_item.execution_id, task) do
            {:ok, task_id} ->
              # Update DLQ item status
              {:ok, _updated_item} =
                dlq_item
                |> Ecto.Changeset.change(%{
                  status: "retried",
                  resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
                  resolved_by: retried_by
                })
                |> Repo.update()

              Logger.info("DLQ item retried: #{dlq_item_id} by #{retried_by}, new task: #{task_id}")

              # Emit telemetry
              :telemetry.execute(
                [:cerebelum, :dlq, :item_retried],
                %{count: 1},
                %{
                  workflow_module: dlq_item.workflow_module,
                  step_name: dlq_item.step_name
                }
              )

              {:reply, {:ok, task_id}, state}

            {:error, reason} ->
              Logger.error("Failed to requeue DLQ item #{dlq_item_id}: #{inspect(reason)}")
              {:reply, {:error, :requeue_failed}, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:resolve_item, dlq_item_id, resolved_by, _reason}, _from, state) do
    case Repo.get(DLQItem, dlq_item_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      dlq_item ->
        if dlq_item.status != "pending" do
          {:reply, {:error, :already_processed}, state}
        else
          {:ok, updated_item} =
            dlq_item
            |> Ecto.Changeset.change(%{
              status: "resolved",
              resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
              resolved_by: resolved_by
            })
            |> Repo.update()

          Logger.info("DLQ item resolved: #{dlq_item_id} by #{resolved_by}")

          # Emit telemetry
          :telemetry.execute(
            [:cerebelum, :dlq, :item_resolved],
            %{count: 1},
            %{
              workflow_module: dlq_item.workflow_module,
              step_name: dlq_item.step_name
            }
          )

          {:reply, {:ok, updated_item}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats =
      from(d in DLQItem,
        select: {d.status, count(d.id)},
        group_by: d.status
      )
      |> Repo.all()
      |> Enum.into(%{})

    total = Enum.reduce(stats, 0, fn {_status, count}, acc -> acc + count end)

    stats_with_total = Map.put(stats, "total", total)

    {:reply, {:ok, stats_with_total}, state}
  end
end
