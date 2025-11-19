defmodule Cerebelum.Worker.WorkerStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :WORKER_STATUS_UNSPECIFIED, 0
  field :IDLE, 1
  field :BUSY, 2
  field :DRAINING, 3
end

defmodule Cerebelum.Worker.TaskStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :TASK_STATUS_UNSPECIFIED, 0
  field :SUCCESS, 1
  field :FAILED, 2
  field :TIMEOUT, 3
  field :CANCELLED, 4
end

defmodule Cerebelum.Worker.RegisterRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Cerebelum.Worker.RegisterRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :worker_id, 1, type: :string, json_name: "workerId"
  field :language, 2, type: :string
  field :capabilities, 3, repeated: true, type: :string

  field :metadata, 4,
    repeated: true,
    type: Cerebelum.Worker.RegisterRequest.MetadataEntry,
    map: true

  field :version, 5, type: :string
end

defmodule Cerebelum.Worker.RegisterResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
  field :heartbeat_interval_ms, 3, type: :int32, json_name: "heartbeatIntervalMs"
end

defmodule Cerebelum.Worker.HeartbeatRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :worker_id, 1, type: :string, json_name: "workerId"
  field :status, 2, type: Cerebelum.Worker.WorkerStatus, enum: true
end

defmodule Cerebelum.Worker.HeartbeatResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :acknowledged, 1, type: :bool
  field :commands, 2, repeated: true, type: :string
end

defmodule Cerebelum.Worker.UnregisterRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :worker_id, 1, type: :string, json_name: "workerId"
  field :reason, 2, type: :string
end

defmodule Cerebelum.Worker.PollRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :worker_id, 1, type: :string, json_name: "workerId"
  field :timeout_ms, 2, type: :int32, json_name: "timeoutMs"
end

defmodule Cerebelum.Worker.Task do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :task_id, 1, type: :string, json_name: "taskId"
  field :execution_id, 2, type: :string, json_name: "executionId"
  field :workflow_module, 3, type: :string, json_name: "workflowModule"
  field :step_name, 4, type: :string, json_name: "stepName"
  field :step_inputs, 5, type: Google.Protobuf.Struct, json_name: "stepInputs"
  field :context, 6, type: Google.Protobuf.Struct
  field :created_at, 7, type: Google.Protobuf.Timestamp, json_name: "createdAt"
end

defmodule Cerebelum.Worker.TaskResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :task_id, 1, type: :string, json_name: "taskId"
  field :execution_id, 2, type: :string, json_name: "executionId"
  field :worker_id, 3, type: :string, json_name: "workerId"
  field :status, 4, type: Cerebelum.Worker.TaskStatus, enum: true
  field :result, 5, type: Google.Protobuf.Struct
  field :error, 6, type: Cerebelum.Worker.ErrorInfo
  field :completed_at, 7, type: Google.Protobuf.Timestamp, json_name: "completedAt"
end

defmodule Cerebelum.Worker.ErrorInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :kind, 1, type: :string
  field :message, 2, type: :string
  field :stacktrace, 3, type: :string
end

defmodule Cerebelum.Worker.Ack do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
end

defmodule Cerebelum.Worker.Blueprint do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :workflow_module, 1, type: :string, json_name: "workflowModule"
  field :language, 2, type: :string
  field :source_code, 3, type: :string, json_name: "sourceCode"
  field :definition, 4, type: Cerebelum.Worker.WorkflowDefinition
  field :version, 5, type: :string
end

defmodule Cerebelum.Worker.WorkflowDefinition.InputsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Cerebelum.Worker.InputDefinition
end

defmodule Cerebelum.Worker.WorkflowDefinition do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :timeline, 1, repeated: true, type: Cerebelum.Worker.Step

  field :diverge_rules, 2,
    repeated: true,
    type: Cerebelum.Worker.DivergeRule,
    json_name: "divergeRules"

  field :branch_rules, 3,
    repeated: true,
    type: Cerebelum.Worker.BranchRule,
    json_name: "branchRules"

  field :inputs, 4,
    repeated: true,
    type: Cerebelum.Worker.WorkflowDefinition.InputsEntry,
    map: true
end

defmodule Cerebelum.Worker.Step do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :name, 1, type: :string
  field :depends_on, 2, repeated: true, type: :string, json_name: "dependsOn"
end

defmodule Cerebelum.Worker.DivergeRule do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :from_step, 1, type: :string, json_name: "fromStep"
  field :patterns, 2, repeated: true, type: Cerebelum.Worker.PatternMatch
end

defmodule Cerebelum.Worker.BranchRule do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :from_step, 1, type: :string, json_name: "fromStep"
  field :branches, 2, repeated: true, type: Cerebelum.Worker.ConditionBranch
end

defmodule Cerebelum.Worker.PatternMatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :pattern, 1, type: :string
  field :target, 2, type: :string
end

defmodule Cerebelum.Worker.ConditionBranch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :condition, 1, type: :string
  field :target, 2, type: :string
end

defmodule Cerebelum.Worker.InputDefinition do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :type, 1, type: :string
  field :required, 2, type: :bool
  field :default_value, 3, type: Google.Protobuf.Struct, json_name: "defaultValue"
end

defmodule Cerebelum.Worker.BlueprintValidation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :valid, 1, type: :bool
  field :errors, 2, repeated: true, type: :string
  field :warnings, 3, repeated: true, type: :string
  field :workflow_hash, 4, type: :string, json_name: "workflowHash"
end

defmodule Cerebelum.Worker.ExecuteRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :workflow_module, 1, type: :string, json_name: "workflowModule"
  field :inputs, 2, type: Google.Protobuf.Struct
  field :options, 3, type: Cerebelum.Worker.ExecutionOptions
end

defmodule Cerebelum.Worker.ExecutionOptions do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :execution_id, 1, type: :string, json_name: "executionId"
  field :correlation_id, 2, type: :string, json_name: "correlationId"
  field :tags, 3, repeated: true, type: :string
  field :timeout_ms, 4, type: :int32, json_name: "timeoutMs"
end

defmodule Cerebelum.Worker.ExecutionHandle do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :execution_id, 1, type: :string, json_name: "executionId"
  field :status, 2, type: :string
  field :started_at, 3, type: Google.Protobuf.Timestamp, json_name: "startedAt"
end

defmodule Cerebelum.Worker.WorkerService.Service do
  @moduledoc false

  use GRPC.Service, name: "cerebelum.worker.WorkerService", protoc_gen_elixir_version: "0.15.0"

  rpc :Register, Cerebelum.Worker.RegisterRequest, Cerebelum.Worker.RegisterResponse

  rpc :Heartbeat, Cerebelum.Worker.HeartbeatRequest, Cerebelum.Worker.HeartbeatResponse

  rpc :Unregister, Cerebelum.Worker.UnregisterRequest, Google.Protobuf.Empty

  rpc :PollForTask, Cerebelum.Worker.PollRequest, Cerebelum.Worker.Task

  rpc :SubmitResult, Cerebelum.Worker.TaskResult, Cerebelum.Worker.Ack

  rpc :SubmitBlueprint, Cerebelum.Worker.Blueprint, Cerebelum.Worker.BlueprintValidation

  rpc :ExecuteWorkflow, Cerebelum.Worker.ExecuteRequest, Cerebelum.Worker.ExecutionHandle
end

defmodule Cerebelum.Worker.WorkerService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Cerebelum.Worker.WorkerService.Service
end
