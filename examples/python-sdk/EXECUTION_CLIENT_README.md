# ExecutionClient - Workflow Status Query API

Query workflow execution status, list running workflows, and resume failed executions from Python.

## Quick Start

```python
from cerebelum import ExecutionClient, ExecutionState

# Initialize client
client = ExecutionClient(core_url="localhost:9090")

# Get status of a specific execution
status = await client.get_execution_status("exec-123")
print(f"Progress: {status.progress_percentage}%")
print(f"Current step: {status.current_step_name}")

# List all running executions
executions, total, has_more = await client.list_executions(
    status=ExecutionState.RUNNING,
    limit=10
)

for exec in executions:
    print(f"{exec.workflow_name}: {exec.progress_percentage}%")

# Resume a failed execution
await client.resume_execution("exec-123")
```

## Installation

The ExecutionClient is included in the `cerebelum` package:

```python
from cerebelum import (
    ExecutionClient,      # Main client
    ExecutionStatus,      # Status dataclass
    ExecutionState,       # State enum
    StepStatus,           # Individual step info
    SleepInfo,            # Sleep state
    ApprovalInfo,         # Approval state
)
```

## API Reference

### ExecutionClient

Main client for querying workflow execution status.

#### `__init__(core_url: str = "localhost:9090")`

Initialize the client.

**Args:**
- `core_url`: URL of the Cerebelum Core gRPC server

#### `get_execution_status(execution_id: str) -> ExecutionStatus`

Get detailed status of a specific execution.

**Args:**
- `execution_id`: The execution ID to query

**Returns:**
- `ExecutionStatus` with complete information

**Example:**
```python
status = await client.get_execution_status("exec-123")
print(f"Workflow: {status.workflow_name}")
print(f"Status: {status.status}")
print(f"Progress: {status.current_step_index}/{status.total_steps}")
```

#### `list_executions(workflow_name=None, status=None, limit=50, offset=0)`

List workflow executions with optional filtering.

**Args:**
- `workflow_name`: Filter by workflow name (optional)
- `status`: Filter by ExecutionState (optional)
- `limit`: Maximum results (default: 50, max: 100)
- `offset`: Skip results for pagination (default: 0)

**Returns:**
- Tuple of `(executions, total_count, has_more)`

**Example:**
```python
# List first 10 running workflows
executions, total, has_more = await client.list_executions(
    status=ExecutionState.RUNNING,
    limit=10
)

# Paginate through all executions
for page in range(0, total, 50):
    executions, _, _ = await client.list_executions(limit=50, offset=page)
    # ... process executions
```

#### `list_active_workflows() -> List[ExecutionStatus]`

Convenience method to get all running workflows.

**Example:**
```python
active = await client.list_active_workflows()
for workflow in active:
    print(f"{workflow.workflow_name}: {workflow.current_step_name}")
```

#### `resume_execution(execution_id: str, skip_completed_steps=True) -> str`

Resume a paused or failed workflow execution.

**Args:**
- `execution_id`: The execution ID to resume
- `skip_completed_steps`: Skip already completed steps (default: True)

**Returns:**
- Status string: "resumed", "already_running", or "failed_to_resume"

**Example:**
```python
status = await client.resume_execution("exec-123")
if status == "resumed":
    print("✅ Execution resumed successfully")
```

## ExecutionStatus

Comprehensive status of a workflow execution.

**Fields:**
- `execution_id`: Unique execution identifier
- `workflow_name`: Name of the workflow
- `status`: ExecutionState enum (RUNNING, COMPLETED, FAILED, etc.)
- `started_at`: Timestamp when execution started
- `completed_at`: Timestamp when execution completed (if finished)
- `current_step_index`: Current step index (0-based)
- `total_steps`: Total number of steps
- `current_step_name`: Name of current step
- `progress_percentage`: Progress as percentage (0-100)
- `completed_steps`: List of StepStatus for completed steps
- `inputs`: Original workflow inputs
- `step_outputs`: Map of step_name -> output dict
- `error`: Error information if failed
- `sleep_info`: SleepInfo if workflow is sleeping
- `approval_info`: ApprovalInfo if waiting for approval
- `elapsed_seconds`: Total elapsed time in seconds

## ExecutionState Enum

```python
class ExecutionState(Enum):
    UNSPECIFIED = "EXECUTION_STATE_UNSPECIFIED"
    RUNNING = "EXECUTION_RUNNING"
    COMPLETED = "EXECUTION_COMPLETED"
    FAILED = "EXECUTION_FAILED"
    SLEEPING = "EXECUTION_SLEEPING"
    WAITING_FOR_APPROVAL = "EXECUTION_WAITING_FOR_APPROVAL"
    PAUSED = "EXECUTION_PAUSED"
```

## Examples

### Monitor Progress in Real-Time

```python
import asyncio

async def monitor_workflow(client, execution_id):
    while True:
        status = await client.get_execution_status(execution_id)

        print(f"Progress: {status.progress_percentage:.1f}%")
        print(f"Current: {status.current_step_name}")

        if status.status in [ExecutionState.COMPLETED, ExecutionState.FAILED]:
            print(f"Finished: {status.status}")
            break

        await asyncio.sleep(2)
```

### List All Workflows by Status

```python
async def list_by_status(client):
    for state in [ExecutionState.RUNNING, ExecutionState.COMPLETED, ExecutionState.FAILED]:
        executions, count, _ = await client.list_executions(status=state, limit=10)
        print(f"\n{state.value}: {count} total")
        for exec in executions:
            print(f"  - {exec.workflow_name} ({exec.progress_percentage:.0f}%)")
```

### Resume All Failed Executions

```python
async def resume_all_failed(client):
    executions, _, _ = await client.list_executions(
        status=ExecutionState.FAILED,
        limit=100
    )

    print(f"Found {len(executions)} failed executions")

    for exec in executions:
        print(f"Resuming {exec.execution_id[:16]}...")
        result = await client.resume_execution(exec.execution_id)
        print(f"  Result: {result}")
```

### Display Execution Dashboard

```python
async def show_dashboard(client):
    # Get counts by status
    running, _, _ = await client.list_executions(status=ExecutionState.RUNNING)
    completed, _, _ = await client.list_executions(status=ExecutionState.COMPLETED)
    failed, _, _ = await client.list_executions(status=ExecutionState.FAILED)
    sleeping, _, _ = await client.list_executions(status=ExecutionState.SLEEPING)

    print("🔄 Running:", len(running))
    print("✅ Completed:", len(completed))
    print("❌ Failed:", len(failed))
    print("💤 Sleeping:", len(sleeping))

    if running:
        print("\nActive Workflows:")
        for exec in running:
            print(f"  {exec.workflow_name}: {exec.current_step_name} ({exec.progress_percentage:.0f}%)")
```

## Complete Example

See `example_execution_client.py` for a comprehensive example with:
- Getting execution status
- Listing executions with filters
- Monitoring progress in real-time
- Resuming failed executions

Run it with:
```bash
python3 example_execution_client.py
```

## Architecture

The ExecutionClient communicates with Cerebelum Core via gRPC:

```
Python SDK (ExecutionClient)
    ↓ gRPC
Cerebelum Core (WorkerServiceServer)
    ↓
StateReconstructor (rebuilds state from events)
    ↓
EventStore (PostgreSQL)
```

**Key Features:**
- ✅ Real-time status queries
- ✅ Filtering by workflow name and status
- ✅ Pagination support
- ✅ Resume failed/paused executions
- ✅ Complete execution history
- ✅ Step-by-step progress tracking
- ✅ Sleep/approval state information

## Requirements

- Cerebelum Core running on specified URL (default: localhost:9090)
- Generated protobuf files (`worker_service_pb2.py`, `worker_service_pb2_grpc.py`)
- Python 3.8+
- `grpcio` package

## Notes

- The client uses insecure gRPC channels (no TLS) - suitable for local development
- For production, implement secure channels with proper authentication
- All methods are async and must be called with `await`
- Remember to call `client.close()` when done to clean up resources

## Related Documentation

- [Long-Running Workflows Guide](../../docs/long-running-workflows.md)
- [Async Operations Guide](../../docs/async-operations-guide.md)
- [Analysis Document](../../ANALISIS_REQUERIMIENTO_INFO_WORKFLOW.md)
