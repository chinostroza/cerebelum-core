"""Execution context for workflow steps.

Provides read-only access to execution metadata and workflow inputs.
"""

from dataclasses import dataclass
from typing import Any, Dict


@dataclass(frozen=True)
class Context:
    """Read-only execution context for workflow steps.

    The frozen=True parameter makes all fields immutable after creation,
    preventing any modifications to the context.

    Attributes:
        inputs: Original workflow input data
        execution_id: Unique execution identifier
        workflow_name: Name of the workflow
        step_name: Name of the current step
        attempt: Retry attempt number (1-indexed)

    Example:
        >>> @step
        >>> async def my_step(context: Context, inputs: dict):
        >>>     user_id = context.inputs["user_id"]
        >>>     execution_id = context.execution_id
        >>>     print(f"Execution {execution_id}, attempt {context.attempt}")
        >>>     return {"ok": "processed"}

        >>> # Attempting to modify raises an error:
        >>> context.attempt = 2  # Raises FrozenInstanceError
    """

    inputs: Dict[str, Any]
    execution_id: str
    workflow_name: str
    step_name: str
    attempt: int = 1
