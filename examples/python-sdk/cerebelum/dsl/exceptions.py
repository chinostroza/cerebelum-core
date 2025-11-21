"""Custom exceptions for DSL workflows.

Provides specific exception types for better error handling and debugging.
"""

from typing import List, Optional


class DSLError(Exception):
    """Base exception for all DSL-related errors."""
    pass


class StepDefinitionError(DSLError):
    """Raised when step definition is invalid.

    Examples:
        - Step function is not async
        - Missing 'context' parameter
        - Invalid parameter names
    """

    def __init__(self, step_name: str, message: str):
        self.step_name = step_name
        self.message = message
        super().__init__(f"Step '{step_name}': {message}")


class WorkflowDefinitionError(DSLError):
    """Raised when workflow definition is invalid.

    Examples:
        - Empty timeline
        - Circular dependencies
        - Missing step references
    """

    def __init__(self, workflow_name: str, errors: List[str]):
        self.workflow_name = workflow_name
        self.errors = errors
        error_list = "\n".join(f"  - {e}" for e in errors)
        super().__init__(
            f"Workflow '{workflow_name}' validation failed:\n{error_list}"
        )


class DependencyError(DSLError):
    """Raised when step dependencies cannot be resolved.

    Examples:
        - Dependency step not found
        - Dependency not yet executed
        - Circular dependency
    """

    def __init__(self, step_name: str, dependency: str, reason: str):
        self.step_name = step_name
        self.dependency = dependency
        self.reason = reason
        super().__init__(
            f"Step '{step_name}' cannot resolve dependency '{dependency}': {reason}"
        )


class StepExecutionError(DSLError):
    """Raised when step execution fails.

    Wraps the original exception with additional context.
    """

    def __init__(
        self,
        step_name: str,
        message: str,
        original_error: Optional[Exception] = None,
        execution_id: Optional[str] = None,
    ):
        self.step_name = step_name
        self.message = message
        self.original_error = original_error
        self.execution_id = execution_id

        error_msg = f"Step '{step_name}' execution failed: {message}"
        if execution_id:
            error_msg = f"[{execution_id}] {error_msg}"
        if original_error:
            error_msg += f"\n  Caused by: {type(original_error).__name__}: {str(original_error)}"

        super().__init__(error_msg)


class StepTimeoutError(DSLError):
    """Raised when step execution times out."""

    def __init__(self, step_name: str, timeout_seconds: float):
        self.step_name = step_name
        self.timeout_seconds = timeout_seconds
        super().__init__(
            f"Step '{step_name}' timed out after {timeout_seconds} seconds"
        )


class RetryExhaustedError(DSLError):
    """Raised when all retry attempts are exhausted."""

    def __init__(
        self,
        step_name: str,
        attempts: int,
        last_error: Optional[Exception] = None,
    ):
        self.step_name = step_name
        self.attempts = attempts
        self.last_error = last_error

        error_msg = f"Step '{step_name}' failed after {attempts} attempts"
        if last_error:
            error_msg += f"\n  Last error: {type(last_error).__name__}: {str(last_error)}"

        super().__init__(error_msg)


class InvalidReturnValueError(DSLError):
    """Raised when step returns invalid value.

    Steps should return {"ok": value} or {"error": message}.
    """

    def __init__(self, step_name: str, return_value: any):
        self.step_name = step_name
        self.return_value = return_value
        super().__init__(
            f"Step '{step_name}' returned invalid value: {return_value}\n"
            f'  Expected: {{"ok": value}} or {{"error": message}}'
        )


class SerializationError(DSLError):
    """Raised when workflow serialization fails."""

    def __init__(self, workflow_name: str, message: str):
        self.workflow_name = workflow_name
        self.message = message
        super().__init__(
            f"Failed to serialize workflow '{workflow_name}': {message}"
        )
