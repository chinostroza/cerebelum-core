"""Workflow executors for local and distributed execution."""
from __future__ import annotations

import asyncio
import uuid
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Any, Dict, Optional

from .blueprint import BlueprintSerializer
from .types import ExecutionContext, ExecutionError, ExecutionResult, WorkflowDefinition


class Executor(ABC):
    """Abstract base class for workflow executors."""

    @abstractmethod
    async def execute(self, workflow: WorkflowDefinition, input_data: Any) -> ExecutionResult:
        """Execute a workflow.

        Args:
            workflow: Workflow definition to execute
            input_data: Input data for the workflow

        Returns:
            Execution result

        Raises:
            ExecutionError: If execution fails
        """
        pass


class LocalExecutor(Executor):
    """Local in-process executor.

    Executes workflows synchronously in the current process.
    Useful for development, testing, and small workloads.

    Example:
        executor = LocalExecutor()
        result = await executor.execute(workflow, {"user_id": 123})
    """

    async def execute(self, workflow: WorkflowDefinition, input_data: Any) -> ExecutionResult:
        """Execute workflow locally.

        Args:
            workflow: Workflow to execute
            input_data: Input data

        Returns:
            Execution result
        """
        execution_id = str(uuid.uuid4())
        started_at = datetime.utcnow().isoformat()

        try:
            # Execute timeline steps using index-based iteration
            state = input_data
            last_result = None
            timeline = workflow.timeline[:]  # Make a copy
            step_idx = 0

            while step_idx < len(timeline):
                step_name = timeline[step_idx]

                # Get step metadata
                step_meta = workflow.steps_metadata.get(step_name)
                if not step_meta:
                    raise ExecutionError(
                        f"Step '{step_name}' not found in metadata",
                        step_name=step_name,
                    )

                # Create execution context
                ctx = ExecutionContext(
                    execution_id=execution_id,
                    workflow_id=workflow.id,
                    step_name=step_name,
                    metadata={},
                )

                # Execute step
                try:
                    result = await step_meta.function(ctx, state)
                    last_result = result

                    # Check diverge rules
                    should_diverge, target_step = self._check_diverge(
                        workflow, step_name, result
                    )
                    if should_diverge and target_step:
                        if target_step == "END":
                            break
                        # Jump to target step
                        if target_step in timeline:
                            step_idx = timeline.index(target_step)
                            state = result  # Update state before jumping
                            continue
                        else:
                            # Target not in timeline, just continue
                            step_idx += 1
                            state = result
                            continue

                    # Check branch rules
                    should_branch, target_step = self._check_branch(
                        workflow, step_name, result, state
                    )
                    if should_branch and target_step:
                        if target_step == "END":
                            break
                        # Handle skip_to and back_to
                        if target_step in timeline:
                            step_idx = timeline.index(target_step)
                            state = result  # Update state before jumping
                            continue
                        else:
                            # Target not in timeline, just continue
                            step_idx += 1
                            state = result
                            continue

                    # Update state for next step
                    state = result
                    step_idx += 1

                except Exception as e:
                    raise ExecutionError(
                        str(e),
                        step_name=step_name,
                        error=str(type(e).__name__),
                    )

            completed_at = datetime.utcnow().isoformat()

            return ExecutionResult(
                execution_id=execution_id,
                status="completed",
                output=last_result,
                started_at=started_at,
                completed_at=completed_at,
            )

        except ExecutionError:
            raise
        except Exception as e:
            raise ExecutionError(
                f"Workflow execution failed: {e}",
                error=str(type(e).__name__),
            )

    def _check_diverge(
        self, workflow: WorkflowDefinition, step_name: str, result: Any
    ) -> tuple[bool, Optional[str]]:
        """Check if diverge rule matches.

        Args:
            workflow: Workflow definition
            step_name: Current step
            result: Step result

        Returns:
            (should_diverge, target_step)
        """
        for rule in workflow.diverge_rules:
            if rule.from_step == step_name:
                # Check patterns
                for pattern in rule.patterns:
                    if self._match_pattern(pattern.pattern, result):
                        return (True, pattern.target)
        return (False, None)

    def _check_branch(
        self,
        workflow: WorkflowDefinition,
        step_name: str,
        result: Any,
        state: Any,
    ) -> tuple[bool, Optional[str]]:
        """Check if branch condition matches.

        Args:
            workflow: Workflow definition
            step_name: Current step
            result: Step result
            state: Current state

        Returns:
            (should_branch, target_step)
        """
        for rule in workflow.branch_rules:
            if rule.from_step == step_name:
                # Check conditions
                for branch in rule.branches:
                    if self._eval_condition(branch.condition, result, state):
                        return (True, branch.action.target_step)
        return (False, None)

    def _match_pattern(self, pattern: str, value: Any) -> bool:
        """Match pattern against value.

        Args:
            pattern: Pattern string
            value: Value to match

        Returns:
            True if pattern matches
        """
        # Simple pattern matching
        if pattern == str(value):
            return True
        # Boolean patterns
        if pattern == "True" and value is True:
            return True
        if pattern == "False" and value is False:
            return True
        # String patterns (remove quotes if present)
        if pattern.startswith('"') and pattern.endswith('"'):
            # Remove quotes and compare
            pattern_value = pattern[1:-1]
            if pattern_value == str(value):
                return True
        # Atom-style patterns
        if pattern.startswith(":") and isinstance(value, str):
            return pattern == value
        return False

    def _eval_condition(self, condition: str, result: Any, state: Any) -> bool:
        """Evaluate branch condition.

        Args:
            condition: Condition expression
            result: Step result
            state: Current state

        Returns:
            True if condition is true

        Warning:
            Uses eval() - only use with trusted conditions
        """
        try:
            # Create safe evaluation context
            context = {"result": result, "state": state}
            return bool(eval(condition, {"__builtins__": {}}, context))
        except Exception:
            return False


# DistributedExecutor moved to distributed.py
