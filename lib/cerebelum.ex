defmodule Cerebelum do
  @moduledoc """
  Public API for Cerebelum workflow orchestration.

  Cerebelum is a workflow orchestration framework that allows you to define,
  execute, and monitor complex workflows with ease.

  ## Quick Start

      # Define a workflow
      defmodule MyWorkflow do
        use Cerebelum.Workflow

        workflow do
          timeline do
            step1() |> step2() |> step3()
          end
        end

        def step1(context), do: {:ok, "result1"}
        def step2(_context, step1), do: {:ok, "result2"}
        def step3(_context, step1, step2), do: {:ok, "result3"}
      end

      # Execute it
      {:ok, execution} = Cerebelum.execute_workflow(MyWorkflow, %{user_id: 123})

      # Check status
      status = Cerebelum.get_execution_status(execution.id)
      #=> %{state: :completed, results: %{...}, ...}

  ## Main Functions

  - `execute_workflow/2` - Start a workflow execution
  - `execute_workflow/3` - Start with options
  - `get_execution_status/1` - Get execution status by ID
  - `stop_execution/1` - Stop a running execution
  - `list_executions/0` - List all running executions
  """

  alias Cerebelum.Execution.{Engine, Supervisor}

  @type execution :: %{
          id: String.t(),
          pid: pid()
        }

  @type execution_status :: %{
          state: atom(),
          execution_id: String.t(),
          workflow_module: module(),
          current_step: atom() | nil,
          timeline_progress: String.t(),
          completed_steps: non_neg_integer(),
          total_steps: non_neg_integer(),
          results: map(),
          error: term() | nil,
          context: map()
        }

  @doc """
  Sleep for a specified duration within a workflow step.

  This function pauses execution for the specified duration. When used
  in workflows with resurrection enabled, the workflow state is preserved
  and can survive system restarts.

  ## Parameters

  - `duration_ms` - Sleep duration in milliseconds (integer)

  ## Returns

  - `:ok` - Always returns :ok after sleep completes

  ## Examples

      defmodule MyWorkflow do
        use Cerebelum.Workflow

        workflow do
          timeline do
            send_email() |> wait_24h() |> send_reminder()
          end
        end

        def wait_24h(_context, _result) do
          # Sleep for 24 hours
          Cerebelum.sleep(24 * 60 * 60 * 1000)
          {:ok, :awake}
        end
      end

  ## Behavior

  - Sleeps < 1 hour: Uses in-memory process sleep
  - Sleeps > 1 hour (default threshold): Workflow may hibernate to save memory
  - Workflows survive system restarts during sleep (with resurrection enabled)
  - State is automatically reconstructed when workflow wakes up

  ## Notes

  When hibernation is enabled (`:enable_workflow_hibernation` config), workflows
  sleeping longer than `:hibernation_threshold_ms` will:
  1. Save state to database
  2. Terminate process to free memory
  3. Be automatically resurrected by WorkflowScheduler
  4. Continue execution seamlessly after sleep
  """
  @spec sleep(non_neg_integer()) :: :ok
  def sleep(duration_ms) when is_integer(duration_ms) and duration_ms >= 0 do
    # Use standard Process.sleep
    # The Engine's state machine will handle hibernation if configured
    Process.sleep(duration_ms)
    :ok
  end

  @doc """
  Resume a paused workflow execution.

  Reconstructs workflow state from events and resumes execution.
  Used for workflow resurrection after system restarts or crashes.

  ## Parameters

  - `execution_id` - The unique execution identifier (string)

  ## Returns

  - `{:ok, pid}` - New process ID of resumed execution
  - `{:error, :already_running}` - Execution is already running
  - `{:error, :not_resumable}` - Execution cannot be resumed (completed/failed)
  - `{:error, :not_found}` - No events found for this execution

  ## Examples

      # After system restart, resume paused workflow
      {:ok, pid} = Cerebelum.resume_execution("exec-abc-123")

      # Check status of resumed workflow
      {:ok, status} = Cerebelum.get_execution_status(pid)
      IO.puts("Resumed at step: \#{status.current_step}")
  """
  @spec resume_execution(String.t()) :: {:ok, pid()} | {:error, term()}
  def resume_execution(execution_id) when is_binary(execution_id) do
    Supervisor.resume_execution(execution_id)
  end

  @doc """
  Executes a workflow with the given inputs.

  This starts a new workflow execution as a supervised process.
  The execution runs asynchronously - this function returns immediately.

  ## Parameters

  - `workflow_module` - A module that uses `Cerebelum.Workflow`
  - `inputs` - A map of initial inputs for the workflow

  ## Returns

  - `{:ok, execution}` - Execution started successfully
  - `{:error, reason}` - Failed to start execution

  ## Examples

      {:ok, execution} = Cerebelum.execute_workflow(MyWorkflow, %{
        order_id: "ORD-123",
        customer_id: "CUST-456"
      })

      IO.puts("Execution started: \#{execution.id}")
      #=> "Execution started: abc-123-def-456"
  """
  @spec execute_workflow(module(), map()) :: {:ok, execution()} | {:error, term()}
  def execute_workflow(workflow_module, inputs) when is_map(inputs) do
    execute_workflow(workflow_module, inputs, [])
  end

  @doc """
  Executes a workflow with the given inputs and options.

  ## Parameters

  - `workflow_module` - A module that uses `Cerebelum.Workflow`
  - `inputs` - A map of initial inputs for the workflow
  - `opts` - Keyword list of options:
    - `:correlation_id` - For distributed tracing
    - `:tags` - Initial tags for the execution
    - `:metadata` - Initial metadata

  ## Examples

      {:ok, execution} = Cerebelum.execute_workflow(
        MyWorkflow,
        %{order_id: "123"},
        correlation_id: "trace-abc",
        tags: ["priority:high"]
      )
  """
  @spec execute_workflow(module(), map(), keyword()) :: {:ok, execution()} | {:error, term()}
  def execute_workflow(workflow_module, inputs, opts) when is_map(inputs) and is_list(opts) do
    context_opts = Keyword.take(opts, [:correlation_id, :tags, :metadata, :execution_id])

    case Supervisor.start_execution(workflow_module, inputs, context_opts: context_opts) do
      {:ok, pid} ->
        # Get the execution_id from the engine
        status = Engine.get_status(pid)

        {:ok,
         %{
           id: status.execution_id,
           pid: pid
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the current status of an execution.

  ## Parameters

  - `execution_id` - The execution ID (string) or PID

  ## Returns

  - `{:ok, status}` - Execution status
  - `{:error, :not_found}` - Execution not found or terminated

  ## Examples

      {:ok, status} = Cerebelum.get_execution_status("abc-123-def-456")

      case status.state do
        :completed -> IO.puts("Workflow completed!")
        :failed -> IO.puts("Workflow failed: \#{inspect(status.error)}")
        :executing_step -> IO.puts("Running step: \#{status.current_step}")
        _ -> IO.puts("Status: \#{status.state}")
      end
  """
  @spec get_execution_status(String.t() | pid()) ::
          {:ok, execution_status()} | {:error, :not_found}
  def get_execution_status(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      status = Engine.get_status(pid)
      {:ok, status}
    else
      {:error, :not_found}
    end
  end

  def get_execution_status(execution_id) when is_binary(execution_id) do
    # Find the execution by ID
    case find_execution_by_id(execution_id) do
      {:ok, pid} -> get_execution_status(pid)
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Stops a running execution.

  ## Parameters

  - `execution_id` - The execution ID (string) or PID

  ## Returns

  - `:ok` - Execution stopped
  - `{:error, :not_found}` - Execution not found

  ## Examples

      Cerebelum.stop_execution("abc-123-def-456")
      #=> :ok
  """
  @spec stop_execution(String.t() | pid()) :: :ok | {:error, :not_found}
  def stop_execution(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      Engine.stop(pid)
      :ok
    else
      {:error, :not_found}
    end
  end

  def stop_execution(execution_id) when is_binary(execution_id) do
    case find_execution_by_id(execution_id) do
      {:ok, pid} -> stop_execution(pid)
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Lists all currently running executions.

  Returns a list of execution information maps.

  ## Examples

      executions = Cerebelum.list_executions()
      #=> [
      #     %{id: "abc-123", pid: #PID<0.123.0>, state: :executing_step},
      #     %{id: "def-456", pid: #PID<0.124.0>, state: :completed}
      #   ]
  """
  @spec list_executions() :: [map()]
  def list_executions do
    Supervisor.list_executions()
    |> Enum.map(fn pid ->
      status = Engine.get_status(pid)

      %{
        id: status.execution_id,
        pid: pid,
        state: status.state,
        workflow_module: status.workflow_module,
        current_step: status.current_step,
        progress: status.timeline_progress
      }
    end)
  end

  @doc """
  Counts the number of currently running executions.

  ## Examples

      count = Cerebelum.count_executions()
      #=> 5
  """
  @spec count_executions() :: non_neg_integer()
  def count_executions do
    Supervisor.count_executions()
  end

  ## Private Functions

  defp find_execution_by_id(execution_id) do
    Supervisor.list_executions()
    |> Enum.find_value(:error, fn pid ->
      status = Engine.get_status(pid)

      if status.execution_id == execution_id do
        {:ok, pid}
      else
        nil
      end
    end)
  end
end
