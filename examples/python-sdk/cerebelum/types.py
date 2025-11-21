"""Type definitions for Cerebelum SDK."""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Dict, Generic, List, Optional, TypeVar, Union

# Type variables for generic StepRef
I = TypeVar("I")  # Input type
O = TypeVar("O")  # Output type


class ActionType(str, Enum):
    """Branch action types."""

    SKIP_TO = "skip_to"
    BACK_TO = "back_to"
    END = "end"


@dataclass
class StepRef(Generic[I, O]):
    """Type-safe reference to a workflow step.

    Generic parameters:
        I: Input type for the step
        O: Output type for the step

    Example:
        fetch_user: StepRef[int, UserData] = StepRef("fetch_user")
    """

    name: str

    def __str__(self) -> str:
        return self.name


# Step function type
StepFunction = Callable[[Any, Any], Coroutine[Any, Any, Any]]


@dataclass
class StepMetadata:
    """Metadata for a workflow step."""

    name: str
    function: StepFunction
    depends_on: List[str] = field(default_factory=list)


@dataclass
class PatternMatch:
    """Pattern match for diverge rules."""

    pattern: str  # Pattern to match (e.g., ":ok", "True", "{error: _}")
    target: str  # Target step name


@dataclass
class DivergeRule:
    """Diverge rule for pattern-based routing."""

    from_step: str
    patterns: List[PatternMatch] = field(default_factory=list)


@dataclass
class BranchAction:
    """Action to take when branch condition is true."""

    type: ActionType
    target_step: str


@dataclass
class ConditionBranch:
    """Conditional branch in workflow."""

    condition: str  # Condition expression (e.g., "result > 10")
    action: BranchAction


@dataclass
class BranchRule:
    """Branch rule for conditional routing."""

    from_step: str
    branches: List[ConditionBranch] = field(default_factory=list)


@dataclass
class WorkflowDefinition:
    """Complete workflow definition."""

    id: str
    timeline: List[str]  # Flattened timeline (for backward compatibility)
    steps_metadata: Dict[str, StepMetadata]
    diverge_rules: List[DivergeRule] = field(default_factory=list)
    branch_rules: List[BranchRule] = field(default_factory=list)
    timeline_structure: Optional[List[Union[str, List[str]]]] = None  # Preserves parallel groups
    inputs: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ExecutionContext:
    """Context passed to each step during execution."""

    execution_id: str
    workflow_id: str
    step_name: str
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ExecutionResult:
    """Result of workflow execution."""

    execution_id: str
    status: str  # "completed", "failed", "timeout"
    output: Optional[Any] = None
    error: Optional[str] = None
    started_at: Optional[str] = None
    completed_at: Optional[str] = None


# Exceptions


class CerebelumError(Exception):
    """Base exception for Cerebelum SDK."""

    pass


class ValidationError(CerebelumError):
    """Raised when workflow validation fails."""

    def __init__(self, errors: List[str]):
        self.errors = errors
        super().__init__(f"Validation failed: {', '.join(errors)}")


class ExecutionError(CerebelumError):
    """Raised when workflow execution fails."""

    def __init__(self, message: str, step_name: Optional[str] = None, error: Optional[str] = None):
        self.message = message
        self.step_name = step_name
        self.error = error
        super().__init__(f"Execution failed at step '{step_name}': {message}")


class WorkerError(CerebelumError):
    """Raised when worker encounters an error."""

    pass
