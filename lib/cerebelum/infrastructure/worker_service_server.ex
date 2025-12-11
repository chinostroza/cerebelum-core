defmodule Cerebelum.Infrastructure.WorkerServiceServer do
  @moduledoc """
  gRPC server implementation for WorkerService.
  
  Handles communication between Core BEAM and SDK workers in different languages
  (Kotlin, TypeScript, Python). Provides RPCs for:
  - Worker registration and lifecycle
  - Task polling and result submission
  - Blueprint submission and validation
  - Workflow execution requests
  """

  use GRPC.Server, service: Cerebelum.Worker.WorkerService.Service

  alias Cerebelum.Worker.{
    RegisterRequest,
    RegisterResponse,
    HeartbeatRequest,
    HeartbeatResponse,
    UnregisterRequest,
    PollRequest,
    Task,
    TaskResult,
    Ack,
    Blueprint,
    BlueprintValidation,
    ExecuteRequest,
    ExecutionHandle
  }

  require Logger

  @heartbeat_interval_ms 10_000

  # Worker Lifecycle Management

  @doc """
  Register a new worker with the Core BEAM system.
  """
  @spec register(RegisterRequest.t(), GRPC.Server.Stream.t()) ::
          RegisterResponse.t()
  def register(request, _stream) do
    Logger.info("Worker registering: #{request.worker_id} (#{request.language})")

    metadata = %{
      language: request.language,
      capabilities: request.capabilities,
      version: request.version,
      metadata: request.metadata
    }

    case Cerebelum.Infrastructure.WorkerRegistry.register_worker(request.worker_id, metadata) do
      {:ok, _worker} ->
        %RegisterResponse{
          success: true,
          message: "Worker registered successfully",
          heartbeat_interval_ms: @heartbeat_interval_ms
        }

      {:error, :already_registered} ->
        %RegisterResponse{
          success: false,
          message: "Worker already registered",
          heartbeat_interval_ms: @heartbeat_interval_ms
        }
    end
  end

  @doc """
  Process heartbeat from worker to maintain liveness.
  """
  @spec heartbeat(HeartbeatRequest.t(), GRPC.Server.Stream.t()) ::
          HeartbeatResponse.t()
  def heartbeat(request, _stream) do
    Logger.debug("Heartbeat from worker: #{request.worker_id}")

    # Convert protobuf status enum to atom
    status = case request.status do
      :IDLE -> :idle
      :BUSY -> :busy
      :DRAINING -> :draining
      _ -> :idle
    end

    Cerebelum.Infrastructure.WorkerRegistry.heartbeat(request.worker_id, status)

    %HeartbeatResponse{
      acknowledged: true,
      commands: []  # No commands for now
    }
  end

  @doc """
  Unregister a worker from the system.
  """
  @spec unregister(UnregisterRequest.t(), GRPC.Server.Stream.t()) ::
          Google.Protobuf.Empty.t()
  def unregister(request, _stream) do
    Logger.info("Worker unregistering: #{request.worker_id}, reason: #{request.reason}")

    Cerebelum.Infrastructure.WorkerRegistry.unregister_worker(request.worker_id, request.reason)

    %Google.Protobuf.Empty{}
  end

  # Task Execution

  @doc """
  Long-polling RPC for workers to retrieve tasks.
  Workers call this and block until a task is available or timeout occurs.
  """
  @spec poll_for_task(PollRequest.t(), GRPC.Server.Stream.t()) :: Task.t()
  def poll_for_task(request, _stream) do
    Logger.debug("Worker #{request.worker_id} polling for tasks (timeout: #{request.timeout_ms}ms)")

    timeout = request.timeout_ms || 10_000

    case Cerebelum.Infrastructure.TaskRouter.poll_for_task(request.worker_id, timeout) do
      {:ok, task} ->
        # Convert internal task format to protobuf Task
        %Task{
          task_id: task.task_id,
          execution_id: task.execution_id,
          workflow_module: Map.get(task, :workflow_module, ""),
          step_name: Map.get(task, :step_name, ""),
          step_inputs: convert_to_struct(Map.get(task, :inputs, %{})),
          context: convert_to_struct(Map.get(task, :context, %{})),
          created_at: timestamp_from_ms(task.queued_at)
        }

      {:error, :timeout} ->
        # No task available within timeout, return empty task
        # Client should handle this and retry
        %Task{
          task_id: "",
          execution_id: "",
          workflow_module: "",
          step_name: "",
          step_inputs: nil,
          context: nil,
          created_at: nil
        }
    end
  end

  @doc """
  Submit task execution result from worker.
  """
  @spec submit_result(TaskResult.t(), GRPC.Server.Stream.t()) :: Ack.t()
  def submit_result(result, _stream) do
    Logger.info("Task result submitted: #{result.task_id} from worker #{result.worker_id}, status: #{result.status}")

    # Convert protobuf result to internal format
    internal_result = %{
      task_id: result.task_id,
      execution_id: result.execution_id,
      worker_id: result.worker_id,
      status: convert_task_status(result.status),
      result: struct_to_map(result.result),
      error: if(result.error, do: convert_error_info(result.error), else: nil),
      completed_at: timestamp_to_ms(result.completed_at)
    }

    # Submit result to TaskRouter and get task metadata
    case Cerebelum.Infrastructure.TaskRouter.submit_result(
      result.task_id,
      result.worker_id,
      internal_result
    ) do
      {:ok, metadata} ->
        # ✅ NEW: Notify WorkflowDelegatingWorkflow instead of ExecutionStateManager
        # This allows the Engine to handle the result properly
        execution_id = metadata.execution_id
        task_id = result.task_id

        # Convert result to format expected by WorkflowDelegatingWorkflow
        workflow_result = case internal_result.status do
          :success ->
            # Check if result contains a sleep/approval marker (workaround for protobuf)
            result_data = internal_result.result

            cond do
              # Check for sleep marker
              is_map(result_data) && Map.get(result_data, "__cerebelum_sleep_request__") == true ->
                duration_ms = Map.get(result_data, "duration_ms", 0)
                data = Map.get(result_data, "data", %{})
                Logger.info("Detected sleep request: #{duration_ms}ms")
                {:sleep, duration_ms, data}

              # Check for approval marker
              is_map(result_data) && Map.get(result_data, "__cerebelum_approval_request__") == true ->
                approval_data = %{
                  type: Map.get(result_data, "approval_type", "manual"),
                  data: Map.get(result_data, "data", %{}),
                  timeout_ms: Map.get(result_data, "timeout_ms")
                }
                Logger.info("Detected approval request: #{approval_data.type}")
                {:approval, approval_data}

              # Normal success
              true ->
                {:ok, result_data}
            end

          :failed ->
            error = internal_result.error || %{message: "Unknown error"}
            {:error, error[:message] || "Task failed"}

          :timeout ->
            {:error, :task_timeout}

          :cancelled ->
            {:error, :task_cancelled}

          :sleep ->
            # Extract sleep request from protobuf (when protobuf is regenerated)
            sleep_req = result.sleep_request
            if sleep_req do
              duration_ms = sleep_req.duration_ms || 0
              data = struct_to_map(sleep_req.data)
              {:sleep, duration_ms, data}
            else
              {:error, "Sleep status without sleep_request"}
            end

          :approval ->
            # Extract approval request from protobuf (when protobuf is regenerated)
            approval_req = result.approval_request
            if approval_req do
              approval_data = %{
                type: approval_req.approval_type || "manual",
                data: struct_to_map(approval_req.data),
                timeout_ms: approval_req.timeout_ms
              }
              {:approval, approval_data}
            else
              {:error, "Approval status without approval_request"}
            end

          _ ->
            {:error, :unknown_status}
        end

        # Notify the WorkflowDelegatingWorkflow that the task completed
        Cerebelum.WorkflowDelegatingWorkflow.notify_task_result(
          execution_id,
          task_id,
          workflow_result
        )

        Logger.info("Notified WorkflowDelegatingWorkflow for execution #{execution_id}, task #{task_id}")

        %Ack{
          success: true,
          message: "Task result processed and notified to workflow engine"
        }

      {:error, :task_not_found} ->
        Logger.error("Task not found: #{result.task_id}")

        %Ack{
          success: false,
          message: "Task not found: #{result.task_id}"
        }
    end
  end

  # Workflow Management

  @doc """
  Submit a workflow blueprint for validation.
  Allows SDK workers to register workflow definitions.
  """
  @spec submit_blueprint(Blueprint.t(), GRPC.Server.Stream.t()) ::
          BlueprintValidation.t()
  def submit_blueprint(blueprint, _stream) do
    Logger.info("Blueprint submitted: #{blueprint.workflow_module} (#{blueprint.language})")

    # Convert protobuf Blueprint to internal format
    internal_blueprint = %{
      workflow_module: blueprint.workflow_module,
      language: blueprint.language,
      source_code: blueprint.source_code,
      definition: convert_workflow_definition(blueprint.definition)
    }

    # Validate blueprint
    case Cerebelum.Application.UseCases.ValidateBlueprint.execute(internal_blueprint) do
      {:ok, result} ->
        # Store blueprint for later execution
        :ok = Cerebelum.Infrastructure.BlueprintRegistry.store_blueprint(
          blueprint.workflow_module,
          internal_blueprint
        )

        Logger.info("Blueprint validated and stored: #{blueprint.workflow_module}")

        %BlueprintValidation{
          valid: true,
          errors: [],
          warnings: result.warnings,
          workflow_hash: result.workflow_hash
        }

      {:error, result} ->
        %BlueprintValidation{
          valid: false,
          errors: result.errors,
          warnings: result.warnings,
          workflow_hash: ""
        }
    end
  end

  @doc """
  Execute a workflow via gRPC request.

  This now uses the Engine system to get full OTP benefits:
  - Event sourcing
  - Resurrection
  - Sleep/Approval
  - Hibernation
  - StateReconstructor
  """
  @spec execute_workflow(ExecuteRequest.t(), GRPC.Server.Stream.t()) ::
          ExecutionHandle.t()
  def execute_workflow(request, _stream) do
    Logger.info("Workflow execution requested: #{request.workflow_module}")

    # Convert inputs from Protobuf Struct to Elixir map
    inputs = struct_to_map(request.inputs)

    Logger.debug("Execution inputs: #{inspect(inputs)}")

    # Lookup blueprint from registry
    case Cerebelum.Infrastructure.BlueprintRegistry.get_blueprint(request.workflow_module) do
      {:ok, blueprint} ->
        Logger.info("Blueprint found for #{request.workflow_module}")

        # ✅ NEW: Use Engine instead of ExecutionStateManager
        # This gives us: events, resurrection, sleep, hibernation, OTP supervision
        {:ok, pid} = Cerebelum.Execution.Supervisor.start_execution(
          Cerebelum.WorkflowDelegatingWorkflow,
          inputs,
          # Pass blueprint and workflow_module via context
          blueprint: blueprint,
          workflow_module: request.workflow_module,
          execution_mode: :distributed
        )

        # Get execution_id from the Engine process
        execution_id = Cerebelum.Execution.Engine.get_execution_id(pid)

        Logger.info("Execution started: #{execution_id} (Engine PID: #{inspect(pid)})")

        %ExecutionHandle{
          execution_id: execution_id,
          status: "running",
          started_at: %Google.Protobuf.Timestamp{
            seconds: System.os_time(:second),
            nanos: 0
          }
        }

      {:error, :not_found} ->
        Logger.error("Blueprint not found for workflow #{request.workflow_module}. Did you call SubmitBlueprint first?")

        # Return error handle
        %ExecutionHandle{
          execution_id: "error_#{System.unique_integer([:positive])}",
          status: "failed",
          started_at: %Google.Protobuf.Timestamp{
            seconds: System.os_time(:second),
            nanos: 0
          }
        }
    end
  end

  # Helper Functions

  defp convert_workflow_definition(nil), do: %{timeline: [], diverge_rules: [], branch_rules: [], inputs: %{}}
  defp convert_workflow_definition(definition) do
    %{
      timeline: Enum.map(definition.timeline || [], &convert_step/1),
      diverge_rules: Enum.map(definition.diverge_rules || [], &convert_diverge_rule/1),
      branch_rules: Enum.map(definition.branch_rules || [], &convert_branch_rule/1),
      inputs: definition.inputs || %{}
    }
  end

  defp convert_step(step) do
    %{
      name: step.name,
      depends_on: step.depends_on || []
    }
  end

  defp convert_diverge_rule(rule) do
    %{
      from_step: rule.from_step,
      patterns: Enum.map(rule.patterns || [], fn pattern ->
        # Parse pattern string as JSON if it looks like JSON
        parsed_pattern = parse_pattern(pattern.pattern)

        %{
          pattern: parsed_pattern,
          target: pattern.target
        }
      end)
    }
  end

  defp parse_pattern(pattern_str) when is_binary(pattern_str) do
    # Try to parse as JSON (for dict patterns)
    case Jason.decode(pattern_str) do
      {:ok, decoded} when is_map(decoded) ->
        decoded
      _ ->
        # Not JSON, keep as string
        pattern_str
    end
  end
  defp parse_pattern(pattern), do: pattern

  defp convert_branch_rule(rule) do
    %{
      from_step: rule.from_step,
      branches: Enum.map(rule.branches || [], fn branch ->
        %{
          condition: branch.condition,
          action: %{
            type: "skip_to",  # Default action type
            target_step: branch.target
          }
        }
      end)
    }
  end

  defp convert_to_struct(map) when is_map(map) do
    # Convert Elixir map to Google.Protobuf.Struct
    # For now, we'll use a simple conversion
    # TODO: Implement proper map-to-Struct conversion
    %Google.Protobuf.Struct{
      fields: Enum.into(map, %{}, fn {k, v} ->
        {to_string(k), value_to_proto_value(v)}
      end)
    }
  end
  defp convert_to_struct(_), do: nil

  defp value_to_proto_value(v) when is_binary(v) do
    %Google.Protobuf.Value{kind: {:string_value, v}}
  end
  defp value_to_proto_value(v) when is_number(v) do
    %Google.Protobuf.Value{kind: {:number_value, v * 1.0}}
  end
  defp value_to_proto_value(v) when is_boolean(v) do
    %Google.Protobuf.Value{kind: {:bool_value, v}}
  end
  defp value_to_proto_value(nil) do
    %Google.Protobuf.Value{kind: {:null_value, :NULL_VALUE}}
  end
  defp value_to_proto_value(v) when is_map(v) do
    %Google.Protobuf.Value{
      kind: {:struct_value, convert_to_struct(v)}
    }
  end
  defp value_to_proto_value(v) when is_list(v) do
    %Google.Protobuf.Value{
      kind: {:list_value, %Google.Protobuf.ListValue{
        values: Enum.map(v, &value_to_proto_value/1)
      }}
    }
  end
  defp value_to_proto_value(v) do
    # Fallback: convert to string
    %Google.Protobuf.Value{kind: {:string_value, inspect(v)}}
  end

  defp struct_to_map(nil), do: %{}
  defp struct_to_map(%Google.Protobuf.Struct{fields: fields}) do
    Enum.into(fields, %{}, fn {k, v} -> {k, proto_value_to_value(v)} end)
  end
  defp struct_to_map(_), do: %{}

  defp proto_value_to_value(%Google.Protobuf.Value{kind: {:string_value, v}}), do: v
  defp proto_value_to_value(%Google.Protobuf.Value{kind: {:number_value, v}}), do: v
  defp proto_value_to_value(%Google.Protobuf.Value{kind: {:bool_value, v}}), do: v
  defp proto_value_to_value(%Google.Protobuf.Value{kind: {:null_value, _}}), do: nil
  defp proto_value_to_value(%Google.Protobuf.Value{kind: {:struct_value, v}}), do: struct_to_map(v)
  defp proto_value_to_value(%Google.Protobuf.Value{kind: {:list_value, %{values: vs}}}), do: Enum.map(vs, &proto_value_to_value/1)
  defp proto_value_to_value(_), do: nil

  defp convert_task_status(:SUCCESS), do: :success
  defp convert_task_status(:FAILED), do: :failed
  defp convert_task_status(:TIMEOUT), do: :timeout
  defp convert_task_status(:CANCELLED), do: :cancelled
  defp convert_task_status(:SLEEP), do: :sleep
  defp convert_task_status(:APPROVAL), do: :approval
  defp convert_task_status(_), do: :unknown

  defp convert_error_info(nil), do: nil
  defp convert_error_info(error) do
    %{
      kind: error.kind,
      message: error.message,
      stacktrace: error.stacktrace
    }
  end

  defp timestamp_from_ms(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    nanos = rem(ms, 1000) * 1_000_000
    %Google.Protobuf.Timestamp{seconds: seconds, nanos: nanos}
  end
  defp timestamp_from_ms(_), do: nil

  defp timestamp_to_ms(nil), do: System.system_time(:millisecond)
  defp timestamp_to_ms(%Google.Protobuf.Timestamp{seconds: s, nanos: n}) do
    s * 1000 + div(n, 1_000_000)
  end
  defp timestamp_to_ms(_), do: System.system_time(:millisecond)
end
