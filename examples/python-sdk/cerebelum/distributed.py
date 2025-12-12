"""Distributed executor and worker implementation."""
from __future__ import annotations

import asyncio
import json
from typing import Any, Dict, Optional, Union

import grpc
from google.protobuf import struct_pb2, timestamp_pb2

from .blueprint import BlueprintSerializer
from .dsl.workflow_markers import WorkflowMarker
from .proto import (
    Ack,
    Blueprint,
    ExecuteRequest,
    PollRequest,
    RegisterRequest,
    TaskResult,
    TaskStatus,
    UnregisterRequest,
    WorkerServiceStub,
    ErrorInfo,
)
from .types import (
    ExecutionContext,
    ExecutionError,
    ExecutionResult,
    StepFunction,
    ValidationError,
    WorkerError,
    WorkflowDefinition,
)


class DistributedExecutor:
    """Distributed executor via gRPC.

    Submits workflows to Cerebelum Core for execution.
    Requires Core BEAM to be running and accessible.

    Example 1 - Execute by workflow ID (recommended):
        executor = DistributedExecutor(core_url="localhost:9090")
        result = await executor.execute("user_onboarding", {"user_id": 123})

    Example 2 - Execute with full workflow definition:
        workflow = WorkflowBuilder("user_onboarding").timeline([...]).build()
        executor = DistributedExecutor(core_url="localhost:9090")
        result = await executor.execute(workflow, {"user_id": 123})
    """

    def __init__(
        self,
        core_url: str,
        worker_id: str = "python-executor",
        timeout: float = 30.0,
    ):
        """Initialize distributed executor.

        Args:
            core_url: gRPC URL of Core BEAM (e.g., "localhost:50051")
            worker_id: Unique worker identifier
            timeout: Request timeout in seconds
        """
        self.core_url = core_url
        self.worker_id = worker_id
        self.timeout = timeout

        # Initialize gRPC channel and stub
        self.channel = grpc.insecure_channel(core_url)
        self.stub = WorkerServiceStub(self.channel)

    async def execute(
        self, workflow: Union[str, WorkflowDefinition], input_data: Any
    ) -> ExecutionResult:
        """Execute workflow via gRPC.

        Args:
            workflow: Workflow ID (str) or WorkflowDefinition object
                - If str: executes an already registered workflow by ID
                - If WorkflowDefinition: submits the blueprint first, then executes
            input_data: Input data

        Returns:
            Execution result

        Raises:
            ValidationError: If blueprint validation fails
            ExecutionError: If execution fails
        """
        # Determine workflow ID
        if isinstance(workflow, str):
            # Workflow ID provided directly - assume it's already registered
            workflow_id = workflow
        else:
            # WorkflowDefinition provided - submit blueprint first
            blueprint_dict = BlueprintSerializer.to_dict(workflow)
            blueprint_pb = self._dict_to_blueprint(blueprint_dict)

            # Submit blueprint for validation
            validation = self.stub.SubmitBlueprint(blueprint_pb)

            if not validation.valid:
                raise ValidationError(list(validation.errors))

            workflow_id = workflow.id

        # Execute workflow
        execute_request = ExecuteRequest(
            workflow_module=workflow_id,
            inputs=self._dict_to_struct(input_data),
        )

        execution_handle = self.stub.ExecuteWorkflow(execute_request)

        # For now, return a simple result
        # TODO: Implement proper polling for completion
        return ExecutionResult(
            execution_id=execution_handle.execution_id,
            status=execution_handle.status,
            output=None,  # Would need to poll for final result
            started_at=self._timestamp_to_str(execution_handle.started_at),
        )

    def _dict_to_blueprint(self, blueprint_dict: Dict[str, Any]) -> Blueprint:
        """Convert blueprint dictionary to protobuf Blueprint."""
        from .proto.worker_service_pb2 import (
            WorkflowDefinition,
            Step,
            DivergeRule,
            PatternMatch,
            BranchRule,
            ConditionBranch,
        )

        definition_dict = blueprint_dict["definition"]

        # Convert timeline
        timeline = [
            Step(name=step["name"], depends_on=step.get("depends_on", []))
            for step in definition_dict["timeline"]
        ]

        # Convert diverge rules
        diverge_rules = [
            DivergeRule(
                from_step=rule["from_step"],
                patterns=[
                    PatternMatch(pattern=p["pattern"], target=p["target"])
                    for p in rule["patterns"]
                ],
            )
            for rule in definition_dict.get("diverge_rules", [])
        ]

        # Convert branch rules
        branch_rules = [
            BranchRule(
                from_step=rule["from_step"],
                branches=[
                    ConditionBranch(
                        condition=b["condition"],
                        target=b["action"]["target_step"],  # Directly use target
                    )
                    for b in rule["branches"]
                ],
            )
            for rule in definition_dict.get("branch_rules", [])
        ]

        definition = WorkflowDefinition(
            timeline=timeline,
            diverge_rules=diverge_rules,
            branch_rules=branch_rules,
            inputs={},  # TODO: Add input definitions
        )

        return Blueprint(
            workflow_module=blueprint_dict["workflow_module"],
            language=blueprint_dict["language"],
            definition=definition,
            version=blueprint_dict["version"],
        )

    def _dict_to_struct(self, data: Any) -> struct_pb2.Struct:
        """Convert Python dict to protobuf Struct."""
        struct = struct_pb2.Struct()
        if isinstance(data, dict):
            struct.update(data)
        return struct

    def _timestamp_to_str(self, timestamp: Optional[timestamp_pb2.Timestamp]) -> Optional[str]:
        """Convert protobuf Timestamp to ISO string."""
        if timestamp is None or (timestamp.seconds == 0 and timestamp.nanos == 0):
            return None
        # Convert to datetime and format
        import datetime

        dt = datetime.datetime.fromtimestamp(
            timestamp.seconds + timestamp.nanos / 1e9, tz=datetime.timezone.utc
        )
        return dt.isoformat()

    def close(self) -> None:
        """Close gRPC channel."""
        self.channel.close()

    def __enter__(self) -> DistributedExecutor:
        """Context manager enter."""
        return self

    def __exit__(self, *args: Any) -> None:
        """Context manager exit."""
        self.close()


class Worker:
    """Worker that polls for tasks from Core BEAM.

    Example:
        worker = Worker(
            worker_id="python-worker-1",
            core_url="localhost:50051",
            language="python"
        )

        worker.register_step("fetch_user", fetch_user_function)
        worker.register_step("send_email", send_email_function)

        await worker.start()
    """

    def __init__(
        self,
        worker_id: str,
        core_url: str,
        language: str = "python",
        heartbeat_interval: float = 10.0,
        poll_timeout: float = 30.0,
        auto_reconnect: bool = True,
        max_reconnect_attempts: int = 0,  # 0 = infinite
        reconnect_base_delay: float = 1.0,
        reconnect_max_delay: float = 60.0,
    ):
        """Initialize worker.

        Args:
            worker_id: Unique worker identifier
            core_url: gRPC URL of Core BEAM
            language: Worker language (default: "python")
            heartbeat_interval: Seconds between heartbeats
            poll_timeout: Timeout for task polling in seconds
            auto_reconnect: Enable automatic reconnection (default: True)
            max_reconnect_attempts: Maximum reconnection attempts (0 = infinite)
            reconnect_base_delay: Base delay for exponential backoff (seconds)
            reconnect_max_delay: Maximum delay between reconnection attempts (seconds)
        """
        self.worker_id = worker_id
        self.core_url = core_url
        self.language = language
        self.heartbeat_interval = heartbeat_interval
        self.poll_timeout = poll_timeout
        self.auto_reconnect = auto_reconnect
        self.max_reconnect_attempts = max_reconnect_attempts
        self.reconnect_base_delay = reconnect_base_delay
        self.reconnect_max_delay = reconnect_max_delay

        # Step registry
        self.steps: Dict[str, StepFunction] = {}

        # Workflow registry
        self.workflows: Dict[str, WorkflowDefinition] = {}

        # gRPC channel and stub
        self.channel = grpc.insecure_channel(core_url)
        self.stub = WorkerServiceStub(self.channel)

        # Running state
        self.running = False
        self.connected = False
        self.reconnect_attempts = 0
        self.heartbeat_task: Optional[asyncio.Task] = None

    def register_step(self, name: str, function: StepFunction) -> None:
        """Register a step function.

        Args:
            name: Step name
            function: Async function to execute
        """
        self.steps[name] = function

    def register_workflow(self, workflow: WorkflowDefinition) -> None:
        """Register a workflow definition (blueprint).

        The workflow blueprint will be submitted to Core when the worker starts.

        Args:
            workflow: Complete workflow definition
        """
        self.workflows[workflow.id] = workflow

    async def _register_with_core(self) -> bool:
        """Register worker with Core and submit workflows.

        Returns:
            True if registration successful, False otherwise
        """
        try:
            # Register worker
            register_req = RegisterRequest(
                worker_id=self.worker_id,
                language=self.language,
                capabilities=list(self.steps.keys()),
                version="0.1.0",
                metadata={},
            )

            response = self.stub.Register(register_req)
            if not response.success:
                print(f"❌ Failed to register worker: {response.message}")
                return False

            print(f"✅ Worker '{self.worker_id}' registered successfully")

            # Submit workflow blueprints
            for workflow_id, workflow in self.workflows.items():
                try:
                    blueprint_dict = BlueprintSerializer.to_dict(workflow)
                    blueprint_pb = self._dict_to_blueprint(blueprint_dict)

                    validation = self.stub.SubmitBlueprint(blueprint_pb)

                    if not validation.valid:
                        print(f"⚠️  Workflow '{workflow_id}' validation failed: {', '.join(validation.errors)}")
                    else:
                        print(f"✅ Workflow '{workflow_id}' blueprint submitted successfully")
                except Exception as e:
                    print(f"❌ Failed to submit blueprint for '{workflow_id}': {e}")

            self.connected = True
            self.reconnect_attempts = 0
            return True

        except Exception as e:
            print(f"❌ Registration failed: {e}")
            return False

    async def _reconnect(self) -> bool:
        """Attempt to reconnect to Core with exponential backoff.

        Returns:
            True if reconnection successful, False if max attempts reached
        """
        if not self.auto_reconnect:
            print("❌ Auto-reconnect disabled, stopping worker")
            return False

        self.connected = False

        while self.running:
            self.reconnect_attempts += 1

            # Check max attempts
            if self.max_reconnect_attempts > 0 and self.reconnect_attempts > self.max_reconnect_attempts:
                print(f"❌ Max reconnection attempts ({self.max_reconnect_attempts}) reached, stopping worker")
                return False

            # Calculate delay with exponential backoff
            delay = min(
                self.reconnect_base_delay * (2 ** (self.reconnect_attempts - 1)),
                self.reconnect_max_delay
            )

            print(f"🔄 Reconnection attempt {self.reconnect_attempts} in {delay:.1f}s...")
            await asyncio.sleep(delay)

            # Recreate channel and stub
            try:
                self.channel.close()
            except:
                pass

            self.channel = grpc.insecure_channel(self.core_url)
            self.stub = WorkerServiceStub(self.channel)

            # Try to register
            if await self._register_with_core():
                print(f"✅ Reconnected successfully after {self.reconnect_attempts} attempts")
                return True

        return False

    async def start(self) -> None:
        """Start worker (register, heartbeat, poll for tasks)."""
        self.running = True

        # Initial registration
        if not await self._register_with_core():
            if not await self._reconnect():
                raise WorkerError("Failed to connect to Core")

        # Start heartbeat task
        self.heartbeat_task = asyncio.create_task(self._heartbeat_loop())

        # Start polling for tasks
        try:
            await self._poll_loop()
        except KeyboardInterrupt:
            print("\n🛑 Stopping worker...")
        finally:
            await self.stop()

    async def stop(self) -> None:
        """Stop worker (unregister, stop heartbeat)."""
        self.running = False

        # Cancel heartbeat
        if self.heartbeat_task:
            self.heartbeat_task.cancel()
            try:
                await self.heartbeat_task
            except asyncio.CancelledError:
                pass

        # Unregister
        unregister_req = UnregisterRequest(
            worker_id=self.worker_id, reason="shutdown"
        )
        self.stub.Unregister(unregister_req)

        # Close channel
        self.channel.close()

        print(f"✅ Worker '{self.worker_id}' stopped")

    async def _heartbeat_loop(self) -> None:
        """Send periodic heartbeats."""
        from .proto.worker_service_pb2 import HeartbeatRequest, WorkerStatus

        consecutive_failures = 0
        max_consecutive_failures = 3

        while self.running:
            try:
                if not self.connected:
                    # Wait for reconnection
                    await asyncio.sleep(self.heartbeat_interval)
                    continue

                heartbeat_req = HeartbeatRequest(
                    worker_id=self.worker_id, status=WorkerStatus.IDLE
                )
                self.stub.Heartbeat(heartbeat_req)
                consecutive_failures = 0
                await asyncio.sleep(self.heartbeat_interval)

            except grpc.RpcError as e:
                consecutive_failures += 1
                print(f"❌ Heartbeat error ({consecutive_failures}/{max_consecutive_failures}): {e.code()}")

                if consecutive_failures >= max_consecutive_failures:
                    print(f"⚠️  Connection lost, attempting to reconnect...")
                    consecutive_failures = 0
                    if not await self._reconnect():
                        # Reconnection failed, stop worker
                        self.running = False
                        break

                await asyncio.sleep(self.heartbeat_interval)

            except Exception as e:
                print(f"❌ Unexpected heartbeat error: {e}")
                await asyncio.sleep(self.heartbeat_interval)

    async def _poll_loop(self) -> None:
        """Poll for tasks and execute them."""
        consecutive_failures = 0
        max_consecutive_failures = 3

        while self.running:
            try:
                if not self.connected:
                    # Wait for reconnection
                    await asyncio.sleep(1.0)
                    continue

                # Poll for task
                poll_req = PollRequest(
                    worker_id=self.worker_id,
                    timeout_ms=int(self.poll_timeout * 1000),
                )

                task = self.stub.PollForTask(poll_req)

                # Reset failure counter on successful poll
                consecutive_failures = 0

                # Check if task is empty (timeout)
                if not task.task_id:
                    # No task available, continue polling
                    continue

                print(f"📋 Received task: {task.step_name} (execution: {task.execution_id})")

                # Execute task
                result = await self._execute_task(task)

                # Submit result
                self.stub.SubmitResult(result)

                print(f"✅ Task completed: {task.step_name}")

            except grpc.RpcError as e:
                consecutive_failures += 1
                print(f"❌ Poll error ({consecutive_failures}/{max_consecutive_failures}): {e.code()}")

                if consecutive_failures >= max_consecutive_failures:
                    print(f"⚠️  Connection lost, attempting to reconnect...")
                    consecutive_failures = 0
                    if not await self._reconnect():
                        # Reconnection failed, stop worker
                        self.running = False
                        break

                await asyncio.sleep(1.0)

            except Exception as e:
                print(f"❌ Unexpected poll error: {e}")
                await asyncio.sleep(1.0)

    async def _execute_task(self, task: Any) -> TaskResult:
        """Execute a task and return result."""
        step_name = task.step_name
        step_function = self.steps.get(step_name)

        if not step_function:
            # Step not registered
            error_info = ErrorInfo(
                kind="not_found",
                message=f"Step '{step_name}' not registered in worker",
                stacktrace="",
            )
            return TaskResult(
                task_id=task.task_id,
                execution_id=task.execution_id,
                worker_id=self.worker_id,
                status=TaskStatus.FAILED,
                result=None,
                error=error_info,
                completed_at=self._current_timestamp(),
            )

        try:
            # Create execution context
            ctx = ExecutionContext(
                execution_id=task.execution_id,
                workflow_id=task.workflow_module,
                step_name=step_name,
                metadata={},
            )

            # Convert inputs from protobuf Struct to dict
            inputs = self._struct_to_dict(task.step_inputs)

            # Execute step - unpack dict as keyword arguments
            output = await step_function(ctx, **inputs)

            # Convert output to protobuf Struct
            result_struct = self._dict_to_struct(output)

            return TaskResult(
                task_id=task.task_id,
                execution_id=task.execution_id,
                worker_id=self.worker_id,
                status=TaskStatus.SUCCESS,
                result=result_struct,
                error=None,
                completed_at=self._current_timestamp(),
            )

        except WorkflowMarker as marker:
            # Handle workflow control flow markers (sleep, approval, etc.)
            from .dsl.workflow_markers import SleepMarker, ApprovalMarker

            if isinstance(marker, SleepMarker):
                # Step requested sleep
                # WORKAROUND: Protobuf hasn't been regenerated yet, so SLEEP status doesn't exist
                # Encode sleep request in result data with special marker
                # TODO: After protobuf regeneration, use TaskStatus.SLEEP and sleep_request field
                sleep_data = {
                    "__cerebelum_sleep_request__": True,
                    "duration_ms": marker.duration_ms,
                    "data": marker.data
                }

                result_struct = self._dict_to_struct(sleep_data)

                return TaskResult(
                    task_id=task.task_id,
                    execution_id=task.execution_id,
                    worker_id=self.worker_id,
                    status=TaskStatus.SUCCESS,  # Use SUCCESS for now
                    result=result_struct,
                    error=None,
                    completed_at=self._current_timestamp(),
                )

            elif isinstance(marker, ApprovalMarker):
                # Step requested approval
                # WORKAROUND: Protobuf hasn't been regenerated yet
                # Encode approval request in result data with special marker
                # TODO: After protobuf regeneration, use TaskStatus.APPROVAL and approval_request field
                approval_data = {
                    "__cerebelum_approval_request__": True,
                    "approval_type": marker.approval_type,
                    "data": marker.data,
                    "timeout_ms": marker.timeout_ms
                }

                result_struct = self._dict_to_struct(approval_data)

                return TaskResult(
                    task_id=task.task_id,
                    execution_id=task.execution_id,
                    worker_id=self.worker_id,
                    status=TaskStatus.SUCCESS,  # Use SUCCESS for now
                    result=result_struct,
                    error=None,
                    completed_at=self._current_timestamp(),
                )
            else:
                # Unknown workflow marker
                raise

        except Exception as e:
            import traceback

            error_info = ErrorInfo(
                kind=type(e).__name__,
                message=str(e),
                stacktrace=traceback.format_exc(),
            )

            return TaskResult(
                task_id=task.task_id,
                execution_id=task.execution_id,
                worker_id=self.worker_id,
                status=TaskStatus.FAILED,
                result=None,
                error=error_info,
                completed_at=self._current_timestamp(),
            )

    def _struct_to_dict(self, struct: Optional[struct_pb2.Struct]) -> Any:
        """Convert protobuf Struct to Python dict."""
        if struct is None:
            return {}
        # Use protobuf's MessageToDict for proper conversion
        from google.protobuf.json_format import MessageToDict

        return MessageToDict(struct, preserving_proto_field_name=True)

    def _dict_to_struct(self, data: Any) -> struct_pb2.Struct:
        """Convert Python data to protobuf Struct."""
        struct = struct_pb2.Struct()
        if isinstance(data, dict):
            struct.update(data)
        elif data is not None:
            # Wrap non-dict values
            struct.update({"value": data})
        return struct

    def _current_timestamp(self) -> timestamp_pb2.Timestamp:
        """Get current timestamp as protobuf Timestamp."""
        import datetime

        now = datetime.datetime.now(datetime.timezone.utc)
        timestamp = timestamp_pb2.Timestamp()
        timestamp.FromDatetime(now)
        return timestamp

    def _dict_to_blueprint(self, blueprint_dict: Dict[str, Any]) -> Blueprint:
        """Convert blueprint dictionary to protobuf Blueprint."""
        from .proto.worker_service_pb2 import (
            WorkflowDefinition,
            Step,
            DivergeRule,
            PatternMatch,
            BranchRule,
            ConditionBranch,
        )

        definition_dict = blueprint_dict["definition"]

        # Convert timeline
        timeline = [
            Step(name=step["name"], depends_on=step.get("depends_on", []))
            for step in definition_dict["timeline"]
        ]

        # Convert diverge rules
        diverge_rules = [
            DivergeRule(
                from_step=rule["from_step"],
                patterns=[
                    PatternMatch(pattern=p["pattern"], target=p["target"])
                    for p in rule["patterns"]
                ],
            )
            for rule in definition_dict.get("diverge_rules", [])
        ]

        # Convert branch rules
        branch_rules = [
            BranchRule(
                from_step=rule["from_step"],
                branches=[
                    ConditionBranch(
                        condition=b["condition"],
                        target=b["action"]["target_step"],  # Directly use target
                    )
                    for b in rule["branches"]
                ],
            )
            for rule in definition_dict.get("branch_rules", [])
        ]

        definition = WorkflowDefinition(
            timeline=timeline,
            diverge_rules=diverge_rules,
            branch_rules=branch_rules,
            inputs={},  # TODO: Add input definitions
        )

        return Blueprint(
            workflow_module=blueprint_dict["workflow_module"],
            language=blueprint_dict["language"],
            definition=definition,
            version=blueprint_dict["version"],
        )
