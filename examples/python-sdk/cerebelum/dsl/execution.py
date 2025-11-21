"""Execution adapter for DSL workflows.

Bridges the new DSL (with Context and dependency resolution) with the
existing execution infrastructure (LocalExecutor, DistributedExecutor).
"""

from typing import Any, Dict, Optional, TYPE_CHECKING
from ..types import ExecutionContext, ExecutionResult, ExecutionError
from .context import Context
from .exceptions import DSLError, DependencyError, StepExecutionError

if TYPE_CHECKING:
    from .decorators import StepMetadata
    from ..types import WorkflowDefinition


class DSLExecutionAdapter:
    """Adapter for executing DSL workflows with dependency resolution.

    Handles:
    - Converting ExecutionContext to DSL Context
    - Resolving step dependencies from execution state
    - Executing steps with proper parameter binding
    - Managing execution state across steps

    Example:
        >>> adapter = DSLExecutionAdapter()
        >>> result = await adapter.execute_step(
        ...     step=my_step,
        ...     exec_context=exec_ctx,
        ...     execution_state={"previous_step": {"ok": "data"}},
        ...     workflow_inputs={"user_id": 123}
        ... )
    """

    @staticmethod
    async def execute_step(
        step: "StepMetadata",
        exec_context: ExecutionContext,
        execution_state: Dict[str, Any],
        workflow_inputs: Dict[str, Any],
    ) -> Any:
        """Execute a single step with dependency resolution.

        Args:
            step: StepMetadata for the step to execute
            exec_context: Execution context from executor
            execution_state: Dict mapping step names to their outputs
            workflow_inputs: Original workflow inputs

        Returns:
            Step output

        Raises:
            ExecutionError: If step execution fails or dependencies are missing

        Example:
            >>> # Execute step that depends on previous steps
            >>> result = await DSLExecutionAdapter.execute_step(
            ...     step=validate_user,
            ...     exec_context=ctx,
            ...     execution_state={"fetch_user": {"ok": {"id": 123}}},
            ...     workflow_inputs={"user_id": 123}
            ... )
        """
        # Create DSL Context
        dsl_context = Context(
            inputs=workflow_inputs,
            execution_id=exec_context.execution_id,
            workflow_name=exec_context.workflow_id,
            step_name=step.name,
            attempt=1,
        )

        # Build kwargs for step function
        kwargs = {}

        # Add context
        if step.has_context:
            kwargs["context"] = dsl_context

        # Add workflow inputs
        if step.has_inputs:
            kwargs["inputs"] = workflow_inputs

        # Resolve dependencies
        for dep_name in step.dependencies:
            if dep_name not in execution_state:
                raise DependencyError(
                    step_name=step.name,
                    dependency=dep_name,
                    reason="dependency has not been executed yet. Check timeline order."
                )

            # Get the output from the dependency step
            dep_output = execution_state[dep_name]

            # Extract the value from {"ok": value} or {"error": message} format
            if isinstance(dep_output, dict):
                if "ok" in dep_output:
                    kwargs[dep_name] = dep_output["ok"]
                elif "error" in dep_output:
                    # Previous step had error, pass it through
                    kwargs[dep_name] = dep_output
                else:
                    # Unknown format, pass as-is
                    kwargs[dep_name] = dep_output
            else:
                # Not a dict, pass as-is
                kwargs[dep_name] = dep_output

        # Execute the step function
        try:
            result = await step.function(**kwargs)
            return result
        except Exception as e:
            raise StepExecutionError(
                step_name=step.name,
                message=str(e),
                original_error=e,
                execution_id=exec_context.execution_id,
            )


class DSLLocalExecutor:
    """Local executor optimized for DSL workflows.

    This executor understands DSL concepts like:
    - Context objects
    - Dependency resolution from parameter names
    - Return value contract ({"ok": ...} or {"error": ...})

    Example:
        >>> executor = DSLLocalExecutor()
        >>> result = await executor.execute(workflow_definition, {"user_id": 123})
    """

    async def execute(
        self,
        workflow: "WorkflowDefinition",
        input_data: Dict[str, Any],
    ) -> ExecutionResult:
        """Execute DSL workflow locally.

        Args:
            workflow: WorkflowDefinition with DSL steps
            input_data: Workflow inputs

        Returns:
            ExecutionResult

        Raises:
            ExecutionError: If execution fails
        """
        import uuid
        from datetime import datetime

        execution_id = str(uuid.uuid4())
        started_at = datetime.utcnow().isoformat()

        try:
            # Execution state: maps step names to their outputs
            execution_state: Dict[str, Any] = {}

            # Create base execution context
            base_context = ExecutionContext(
                execution_id=execution_id,
                workflow_id=workflow.id,
                step_name="",  # Will be updated per step
                metadata={},
            )

            # Execute timeline steps (using timeline_structure for parallelism)
            timeline_to_execute = workflow.timeline_structure if workflow.timeline_structure else workflow.timeline
            last_result = None

            for item in timeline_to_execute:
                if isinstance(item, list):
                    # Parallel execution group - use asyncio.gather
                    tasks = []
                    for step_name in item:
                        # Get step metadata
                        step_meta = workflow.steps_metadata.get(step_name)
                        if not step_meta:
                            raise ExecutionError(
                                f"Step '{step_name}' not found in metadata",
                                step_name=step_name,
                            )

                        # Create context for this step
                        step_context = ExecutionContext(
                            execution_id=base_context.execution_id,
                            workflow_id=base_context.workflow_id,
                            step_name=step_name,
                            metadata=base_context.metadata,
                        )

                        # Create task for parallel execution
                        task = DSLExecutionAdapter.execute_step(
                            step=step_meta,
                            exec_context=step_context,
                            execution_state=execution_state,
                            workflow_inputs=input_data,
                        )
                        tasks.append((step_name, task))

                    # Execute all tasks in parallel
                    import asyncio
                    results = await asyncio.gather(*[task for _, task in tasks])

                    # Store all results
                    for (step_name, _), result in zip(tasks, results):
                        execution_state[step_name] = result
                        last_result = result

                        # Check for error
                        if isinstance(result, dict) and "error" in result:
                            raise ExecutionError(
                                f"Step '{step_name}' returned error: {result['error']}",
                                step_name=step_name,
                            )

                else:
                    # Single step - execute normally
                    step_name = item

                    # Get step metadata
                    step_meta = workflow.steps_metadata.get(step_name)
                    if not step_meta:
                        raise ExecutionError(
                            f"Step '{step_name}' not found in metadata",
                            step_name=step_name,
                        )

                    # Update context for this step
                    base_context.step_name = step_name

                    # Execute step with dependency resolution
                    result = await DSLExecutionAdapter.execute_step(
                        step=step_meta,
                        exec_context=base_context,
                        execution_state=execution_state,
                        workflow_inputs=input_data,
                    )

                    # Store result in execution state
                    execution_state[step_name] = result
                    last_result = result

                    # Check for error
                    if isinstance(result, dict) and "error" in result:
                        # Step returned error, stop execution
                        raise ExecutionError(
                            f"Step '{step_name}' returned error: {result['error']}",
                            step_name=step_name,
                        )

            completed_at = datetime.utcnow().isoformat()

            return ExecutionResult(
                execution_id=execution_id,
                status="completed",
                output=last_result,
                started_at=started_at,
                completed_at=completed_at,
            )

        except (ExecutionError, DSLError):
            # Re-raise DSL and execution errors without wrapping
            raise
        except Exception as e:
            raise ExecutionError(
                f"Workflow execution failed: {e}",
                error=str(type(e).__name__),
            )
