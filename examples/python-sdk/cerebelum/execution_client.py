"""Client for querying workflow execution status.

Provides an API to query the status of running, paused, and completed workflows
from the Cerebelum Core via gRPC.
"""

import grpc
from typing import List, Optional, Dict, Any
from datetime import datetime
from dataclasses import dataclass
from enum import Enum

# Import generated protobuf classes
try:
    from . import worker_service_pb2 as pb
    from . import worker_service_pb2_grpc as pb_grpc
except ImportError:
    # Fallback for when protobufs aren't generated yet
    pb = None
    pb_grpc = None


class ExecutionState(Enum):
    """Execution state enum matching protobuf."""
    UNSPECIFIED = "EXECUTION_STATE_UNSPECIFIED"
    RUNNING = "EXECUTION_RUNNING"
    COMPLETED = "EXECUTION_COMPLETED"
    FAILED = "EXECUTION_FAILED"
    SLEEPING = "EXECUTION_SLEEPING"
    WAITING_FOR_APPROVAL = "EXECUTION_WAITING_FOR_APPROVAL"
    PAUSED = "EXECUTION_PAUSED"


@dataclass
class StepStatus:
    """Status of a single workflow step."""
    step_name: str
    step_index: int
    status: str  # "completed", "failed", "running"
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    duration_seconds: int
    output: Optional[Dict[str, Any]]
    error: Optional[Dict[str, str]]

    @classmethod
    def from_proto(cls, proto_step):
        """Create StepStatus from protobuf."""
        return cls(
            step_name=proto_step.step_name,
            step_index=proto_step.step_index,
            status=proto_step.status,
            started_at=_timestamp_to_datetime(proto_step.started_at) if proto_step.HasField("started_at") else None,
            completed_at=_timestamp_to_datetime(proto_step.completed_at) if proto_step.HasField("completed_at") else None,
            duration_seconds=proto_step.duration_seconds,
            output=_struct_to_dict(proto_step.output) if proto_step.HasField("output") else None,
            error=_error_info_to_dict(proto_step.error) if proto_step.HasField("error") else None
        )


@dataclass
class SleepInfo:
    """Information about a sleeping workflow."""
    duration_ms: int
    sleep_started_at: Optional[datetime]
    remaining_ms: int
    data: Optional[Dict[str, Any]]

    @classmethod
    def from_proto(cls, proto_sleep):
        """Create SleepInfo from protobuf."""
        return cls(
            duration_ms=proto_sleep.duration_ms,
            sleep_started_at=_timestamp_to_datetime(proto_sleep.sleep_started_at) if proto_sleep.HasField("sleep_started_at") else None,
            remaining_ms=proto_sleep.remaining_ms,
            data=_struct_to_dict(proto_sleep.data) if proto_sleep.HasField("data") else None
        )


@dataclass
class ApprovalInfo:
    """Information about a workflow waiting for approval."""
    approval_type: str
    data: Optional[Dict[str, Any]]
    timeout_ms: int
    requested_at: Optional[datetime]
    remaining_timeout_ms: int

    @classmethod
    def from_proto(cls, proto_approval):
        """Create ApprovalInfo from protobuf."""
        return cls(
            approval_type=proto_approval.approval_type,
            data=_struct_to_dict(proto_approval.data) if proto_approval.HasField("data") else None,
            timeout_ms=proto_approval.timeout_ms,
            requested_at=_timestamp_to_datetime(proto_approval.requested_at) if proto_approval.HasField("requested_at") else None,
            remaining_timeout_ms=proto_approval.remaining_timeout_ms
        )


@dataclass
class ExecutionStatus:
    """Complete status of a workflow execution.

    Provides detailed information about a workflow execution including:
    - Basic info (execution_id, workflow_name, status)
    - Progress (current_step_index, total_steps)
    - Completed steps with their outputs
    - Inputs and step outputs
    - Error information if failed
    - Sleep/approval state if paused
    """
    execution_id: str
    workflow_name: str
    status: ExecutionState
    started_at: Optional[datetime]
    completed_at: Optional[datetime]

    # Progress info
    current_step_index: int
    total_steps: int
    current_step_name: str
    progress_percentage: float

    # Completed steps
    completed_steps: List[StepStatus]

    # Inputs and outputs
    inputs: Dict[str, Any]
    step_outputs: Dict[str, Dict[str, Any]]

    # Error if failed
    error: Optional[Dict[str, str]]

    # Sleep/Approval state
    sleep_info: Optional[SleepInfo]
    approval_info: Optional[ApprovalInfo]

    # Timing
    elapsed_seconds: Optional[int]

    @classmethod
    def from_proto(cls, proto_status):
        """Create ExecutionStatus from protobuf."""
        started_at = _timestamp_to_datetime(proto_status.started_at) if proto_status.HasField("started_at") else None
        completed_at = _timestamp_to_datetime(proto_status.completed_at) if proto_status.HasField("completed_at") else None

        # Calculate elapsed time
        elapsed_seconds = None
        if started_at:
            end_time = completed_at or datetime.now()
            elapsed_seconds = int((end_time - started_at).total_seconds())

        # Calculate progress percentage
        progress_percentage = 0.0
        if proto_status.total_steps > 0:
            progress_percentage = (proto_status.current_step_index / proto_status.total_steps) * 100

        # Parse status enum
        status = ExecutionState.UNSPECIFIED
        try:
            status_name = pb.ExecutionState.Name(proto_status.status)
            status = ExecutionState(status_name)
        except (ValueError, AttributeError):
            pass

        return cls(
            execution_id=proto_status.execution_id,
            workflow_name=proto_status.workflow_name,
            status=status,
            started_at=started_at,
            completed_at=completed_at,
            current_step_index=proto_status.current_step_index,
            total_steps=proto_status.total_steps,
            current_step_name=proto_status.current_step_name,
            progress_percentage=progress_percentage,
            completed_steps=[StepStatus.from_proto(s) for s in proto_status.completed_steps],
            inputs=_struct_to_dict(proto_status.inputs) if proto_status.HasField("inputs") else {},
            step_outputs={k: _struct_to_dict(v) for k, v in proto_status.step_outputs.items()},
            error=_error_info_to_dict(proto_status.error) if proto_status.HasField("error") else None,
            sleep_info=SleepInfo.from_proto(proto_status.sleep_info) if proto_status.HasField("sleep_info") else None,
            approval_info=ApprovalInfo.from_proto(proto_status.approval_info) if proto_status.HasField("approval_info") else None,
            elapsed_seconds=elapsed_seconds
        )


class ExecutionClient:
    """Client for querying workflow execution status from Cerebelum Core.

    Provides methods to:
    - Get detailed status of a specific execution
    - List executions with filtering and pagination
    - Resume paused or failed executions

    Example:
        >>> client = ExecutionClient(core_url="localhost:9090")
        >>>
        >>> # Get status of a specific execution
        >>> status = await client.get_execution_status("exec-123")
        >>> print(f"Progress: {status.progress_percentage}%")
        >>>
        >>> # List all running executions
        >>> executions = await client.list_executions(status=ExecutionState.RUNNING)
        >>> for exec in executions:
        >>>     print(f"{exec.workflow_name}: {exec.progress_percentage}%")
        >>>
        >>> # Resume a failed execution
        >>> await client.resume_execution("exec-123")
    """

    def __init__(self, core_url: str = "localhost:9090"):
        """Initialize the execution client.

        Args:
            core_url: URL of the Cerebelum Core gRPC server (default: localhost:9090)
        """
        self.core_url = core_url
        self.channel = None
        self.stub = None

    def _ensure_connected(self):
        """Ensure gRPC connection is established."""
        if self.channel is None:
            self.channel = grpc.insecure_channel(self.core_url)
            if pb_grpc:
                self.stub = pb_grpc.WorkerServiceStub(self.channel)

    async def get_execution_status(self, execution_id: str) -> ExecutionStatus:
        """Get the status of a specific workflow execution.

        Args:
            execution_id: The execution ID to query

        Returns:
            ExecutionStatus with complete information about the execution

        Raises:
            grpc.RpcError: If the execution is not found or RPC fails

        Example:
            >>> status = await client.get_execution_status("exec-123")
            >>> print(f"Workflow: {status.workflow_name}")
            >>> print(f"Progress: {status.current_step_index}/{status.total_steps}")
            >>> print(f"Status: {status.status.value}")
        """
        self._ensure_connected()

        if not pb:
            raise RuntimeError("Protobuf classes not generated. Run: python -m grpc_tools.protoc ...")

        request = pb.GetExecutionStatusRequest(execution_id=execution_id)
        response = self.stub.GetExecutionStatus(request)

        return ExecutionStatus.from_proto(response)

    async def list_executions(
        self,
        workflow_name: Optional[str] = None,
        status: Optional[ExecutionState] = None,
        limit: int = 50,
        offset: int = 0
    ) -> tuple[List[ExecutionStatus], int, bool]:
        """List workflow executions with optional filtering.

        Args:
            workflow_name: Filter by workflow name (optional)
            status: Filter by execution state (optional)
            limit: Maximum number of results (default: 50, max: 100)
            offset: Number of results to skip for pagination (default: 0)

        Returns:
            Tuple of (executions, total_count, has_more)
            - executions: List of ExecutionStatus objects
            - total_count: Total number of matching executions
            - has_more: Whether there are more results available

        Example:
            >>> # List first 10 running executions
            >>> executions, total, has_more = await client.list_executions(
            ...     status=ExecutionState.RUNNING,
            ...     limit=10
            ... )
            >>> print(f"Found {total} running executions")
            >>>
            >>> # Paginate through results
            >>> for page in range(0, total, 10):
            ...     executions, _, _ = await client.list_executions(limit=10, offset=page)
            ...     for exec in executions:
            ...         print(f"{exec.execution_id}: {exec.progress_percentage}%")
        """
        self._ensure_connected()

        if not pb:
            raise RuntimeError("Protobuf classes not generated. Run: python -m grpc_tools.protoc ...")

        # Convert status enum to protobuf
        status_value = None
        if status:
            try:
                status_value = getattr(pb, status.value)
            except AttributeError:
                pass

        request = pb.ListExecutionsRequest(
            workflow_name=workflow_name or "",
            status=status_value if status_value is not None else pb.EXECUTION_STATE_UNSPECIFIED,
            limit=limit,
            offset=offset
        )

        response = self.stub.ListExecutions(request)

        executions = [ExecutionStatus.from_proto(e) for e in response.executions]

        return executions, response.total_count, response.has_more

    async def list_active_workflows(self) -> List[ExecutionStatus]:
        """Convenience method to get all running workflows.

        Returns:
            List of ExecutionStatus for all running workflows

        Example:
            >>> active = await client.list_active_workflows()
            >>> for workflow in active:
            ...     print(f"{workflow.workflow_name}: {workflow.current_step_name}")
        """
        executions, _, _ = await self.list_executions(status=ExecutionState.RUNNING, limit=100)
        return executions

    async def resume_execution(
        self,
        execution_id: str,
        skip_completed_steps: bool = True
    ) -> str:
        """Resume a paused or failed workflow execution.

        Args:
            execution_id: The execution ID to resume
            skip_completed_steps: Skip already completed steps (default: True)

        Returns:
            Status string ("resumed", "already_running", or "failed_to_resume")

        Raises:
            grpc.RpcError: If RPC fails

        Example:
            >>> # Resume a failed execution
            >>> status = await client.resume_execution("exec-123")
            >>> if status == "resumed":
            ...     print("Execution resumed successfully")
            >>> elif status == "already_running":
            ...     print("Execution is already running")
        """
        self._ensure_connected()

        if not pb:
            raise RuntimeError("Protobuf classes not generated. Run: python -m grpc_tools.protoc ...")

        request = pb.ResumeExecutionRequest(
            execution_id=execution_id,
            skip_completed_steps=skip_completed_steps
        )

        response = self.stub.ResumeExecution(request)

        return response.status

    def close(self):
        """Close the gRPC channel."""
        if self.channel:
            self.channel.close()
            self.channel = None
            self.stub = None


# Helper functions

def _timestamp_to_datetime(timestamp) -> Optional[datetime]:
    """Convert protobuf Timestamp to Python datetime."""
    if not timestamp:
        return None
    return datetime.fromtimestamp(timestamp.seconds + timestamp.nanos / 1e9)


def _struct_to_dict(struct) -> Dict[str, Any]:
    """Convert protobuf Struct to Python dict."""
    if not struct:
        return {}

    # This is a simplified conversion - in production you'd use MessageToDict
    result = {}
    for key, value in struct.fields.items():
        result[key] = _value_to_python(value)
    return result


def _value_to_python(value) -> Any:
    """Convert protobuf Value to Python value."""
    kind = value.WhichOneof("kind")
    if kind == "null_value":
        return None
    elif kind == "number_value":
        return value.number_value
    elif kind == "string_value":
        return value.string_value
    elif kind == "bool_value":
        return value.bool_value
    elif kind == "struct_value":
        return _struct_to_dict(value.struct_value)
    elif kind == "list_value":
        return [_value_to_python(v) for v in value.list_value.values]
    return None


def _error_info_to_dict(error_info) -> Optional[Dict[str, str]]:
    """Convert protobuf ErrorInfo to Python dict."""
    if not error_info:
        return None
    return {
        "kind": error_info.kind,
        "message": error_info.message,
        "stacktrace": error_info.stacktrace
    }
