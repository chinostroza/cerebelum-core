"""Workflow control flow markers for sleep, approval, etc.

These exceptions are raised by helper functions like sleep() and approval()
to signal special workflow behaviors that the worker should handle.
"""

from typing import Any, Optional


class WorkflowMarker(Exception):
    """Base class for workflow control flow markers."""
    pass


class SleepMarker(WorkflowMarker):
    """Marker raised when a step requests sleep.

    The worker will catch this and send a SLEEP TaskResult to Core,
    which will pause the workflow for the specified duration.

    Attributes:
        duration_ms: Sleep duration in milliseconds
        data: Optional data to carry through the sleep
    """

    def __init__(self, duration_ms: int, data: Optional[dict] = None):
        self.duration_ms = duration_ms
        self.data = data or {}
        super().__init__(f"Sleep requested for {duration_ms}ms")


class ApprovalMarker(WorkflowMarker):
    """Marker raised when a step requests human approval.

    The worker will catch this and send an APPROVAL TaskResult to Core,
    which will pause the workflow until approval is received.

    Attributes:
        approval_type: Type of approval ("manual", "automated", etc.)
        data: Approval data/context
        timeout_ms: Optional timeout in milliseconds
    """

    def __init__(
        self,
        approval_type: str = "manual",
        data: Optional[dict] = None,
        timeout_ms: Optional[int] = None
    ):
        self.approval_type = approval_type
        self.data = data or {}
        self.timeout_ms = timeout_ms
        super().__init__(f"Approval requested: {approval_type}")
