"""Cerebelum Python SDK.

A Python SDK for building and executing deterministic workflows
with the Cerebelum Workflow Engine.

New DSL Example (recommended):
    from cerebelum import step, workflow, Context

    @step
    async def fetch_user(context: Context, inputs: dict):
        user_id = inputs["user_id"]
        return {"ok": {"id": user_id, "name": "John"}}

    @step
    async def validate_user(context: Context, fetch_user: dict):
        user = fetch_user
        if user["id"] > 0:
            return {"ok": user}
        return {"error": "invalid_user"}

    @workflow
    def user_workflow(wf):
        wf.timeline(fetch_user >> validate_user)

    # Execute
    result = await user_workflow.execute({"user_id": 123})
    print(result.execution_id)

Legacy Builder Example:
    from cerebelum import WorkflowBuilder, LocalExecutor

    async def step1(ctx, x):
        return x * 2

    workflow = (
        WorkflowBuilder("my_workflow")
        .timeline(["step1"])
        .step("step1", step1)
        .build()
    )

    executor = LocalExecutor()
    result = await executor.execute(workflow, 21)
    print(result.output)  # 42
"""

__version__ = "0.1.0"

# Core types
from .types import (
    ActionType,
    BranchAction,
    BranchRule,
    CerebelumError,
    ConditionBranch,
    DivergeRule,
    ExecutionContext,
    ExecutionError,
    ExecutionResult,
    PatternMatch,
    StepFunction,
    StepMetadata,
    StepRef,
    ValidationError,
    WorkerError,
    WorkflowDefinition,
)

# Workflow builder
from .workflow import BranchBuilder, DivergeBuilder, WorkflowBuilder

# Blueprint serialization
from .blueprint import BlueprintSerializer

# Executors
from .executor import Executor, LocalExecutor
from .distributed import DistributedExecutor, Worker

# Execution Status Client (NEW - Phase: Info Workflow)
from .execution_client import (
    ExecutionClient,
    ExecutionStatus,
    ExecutionState,
    StepStatus,
    SleepInfo,
    ApprovalInfo,
)

# New DSL (Phase 1-7 + Improvements)
from .dsl import (
    step,
    workflow,
    Context,
    StepComposition,
    ParallelStepGroup,
    StepRegistry,
    WorkflowRegistry,
    DSLSerializer,
    DSLLocalExecutor,
    DSLExecutionAdapter,
    # Async helpers (Phase 7)
    sleep,
    poll,
    retry,
    ProgressReporter,
)

# Note: StepMetadata and WorkflowMetadata are imported but not exported
# because they are returned by decorators, not used directly by users
from .dsl import StepMetadata as _StepMetadata
from .dsl import WorkflowMetadata as _WorkflowMetadata

# Public API
__all__ = [
    # Version
    "__version__",
    # New DSL (recommended)
    "step",
    "workflow",
    "Context",
    "StepComposition",
    "ParallelStepGroup",
    "DSLSerializer",
    "DSLLocalExecutor",
    "DSLExecutionAdapter",
    # Async Helpers (Phase 7 - Long-running operations)
    "sleep",
    "poll",
    "retry",
    "ProgressReporter",
    # Types
    "ActionType",
    "BranchAction",
    "BranchRule",
    "CerebelumError",
    "ConditionBranch",
    "DivergeRule",
    "ExecutionContext",
    "ExecutionError",
    "ExecutionResult",
    "PatternMatch",
    "StepFunction",
    "StepMetadata",
    "StepRef",
    "ValidationError",
    "WorkerError",
    "WorkflowDefinition",
    # Legacy Workflow Builder
    "WorkflowBuilder",
    "DivergeBuilder",
    "BranchBuilder",
    # Blueprint
    "BlueprintSerializer",
    # Executors
    "Executor",
    "LocalExecutor",
    "DistributedExecutor",
    # Worker
    "Worker",
    # Execution Status Client (NEW - Phase: Info Workflow)
    "ExecutionClient",
    "ExecutionStatus",
    "ExecutionState",
    "StepStatus",
    "SleepInfo",
    "ApprovalInfo",
    # Registries (advanced use)
    "StepRegistry",
    "WorkflowRegistry",
]
