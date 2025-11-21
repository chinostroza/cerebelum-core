"""Decorators for defining workflows and steps.

Provides @step and @workflow decorators for declarative workflow definition.
"""

import functools
import inspect
from typing import Callable, List, Optional, Any, Dict, TypeVar, ParamSpec

from .composition import StepComposition
from .registry import StepRegistry, WorkflowRegistry
from .exceptions import StepDefinitionError, WorkflowDefinitionError

# Type variables for generic function signatures
P = ParamSpec('P')
R = TypeVar('R')


class StepMetadata:
    """Metadata for a decorated step function.

    This class wraps an async function decorated with @step and extracts
    metadata about its parameters and dependencies.

    Attributes:
        name: Function name (used as step identifier)
        function: Original async function
        parameters: List of all parameter names
        has_context: Whether function has 'context' parameter
        has_inputs: Whether function has 'inputs' parameter
        dependencies: List of dependency step names (params except context/inputs)
    """

    def __init__(
        self,
        name: str,
        function: Callable,
        parameters: List[str],
        has_context: bool,
        has_inputs: bool,
        dependencies: List[str],
    ):
        """Initialize step metadata.

        Args:
            name: Step name (function name)
            function: Original async function
            parameters: List of parameter names
            has_context: True if 'context' in parameters
            has_inputs: True if 'inputs' in parameters
            dependencies: List of dependency step names
        """
        self.name = name
        self.function = function
        self.parameters = parameters
        self.has_context = has_context
        self.has_inputs = has_inputs
        self.dependencies = dependencies

    def __rshift__(self, other: object) -> StepComposition:
        """Enable step1 >> step2 or step1 >> [step2, step3] syntax.

        Args:
            other: StepMetadata, StepComposition, or list of StepMetadata (parallel)

        Returns:
            StepComposition containing this step and other

        Raises:
            TypeError: If other is not a valid type
            ValueError: If list is empty

        Example:
            >>> a >> b  # Sequential: StepComposition([a, b])
            >>> a >> [b, c]  # Parallel: StepComposition([a, ParallelGroup([b, c])])
        """
        from .composition import ParallelStepGroup

        if isinstance(other, StepMetadata):
            # Single step - sequential composition
            return StepComposition([self, other])
        elif isinstance(other, StepComposition):
            # Composition - merge
            return StepComposition([self] + other.items)
        elif isinstance(other, list):
            # List of steps - create parallel group
            if not other:
                raise ValueError("Parallel step list cannot be empty")
            if not all(isinstance(s, StepMetadata) for s in other):
                raise TypeError(
                    "Parallel step list must contain only steps decorated with @step"
                )
            parallel_group = ParallelStepGroup(other)
            return StepComposition([self, parallel_group])
        else:
            raise TypeError(
                f"Cannot compose StepMetadata with {type(other).__name__}. "
                f"Right operand must be a step decorated with @step, "
                f"a StepComposition, or a list of steps."
            )

    def __repr__(self) -> str:
        """String representation."""
        return f"StepMetadata(name='{self.name}', dependencies={self.dependencies})"

    def __call__(self, *args: Any, **kwargs: Any) -> Any:
        """Allow calling the original function.

        This enables the step to be called directly during testing.
        """
        return self.function(*args, **kwargs)


class WorkflowMetadata:
    """Metadata for a decorated workflow function.

    This class wraps a function decorated with @workflow and provides
    methods for building and executing the workflow.

    Attributes:
        name: Workflow name (function name)
        definition_func: Original workflow definition function
        core_url: URL of Cerebelum Core gRPC server
    """

    def __init__(
        self,
        name: str,
        definition_func: Callable,
        core_url: str = "localhost:9090",
    ):
        """Initialize workflow metadata.

        Args:
            name: Workflow name
            definition_func: Function that defines workflow structure
            core_url: gRPC URL of Cerebelum Core
        """
        self.name = name
        self.definition_func = definition_func
        self.core_url = core_url
        self._built_definition: Optional[Any] = None  # WorkflowDefinition
        self._validation_report: Optional[Any] = None  # ValidationReport

    async def execute(
        self,
        inputs: Dict[str, Any],
        executor: Optional[Any] = None,
        distributed: bool = False,
        max_reconnect_attempts: int = 0,
        reconnect_max_delay: float = 60.0,
    ) -> Any:
        """Execute the workflow with given inputs.

        Args:
            inputs: Input data for workflow
            executor: Optional custom executor (for advanced use cases)
            distributed: If True, runs as distributed worker server (blocks, shows logs)
                        If False, runs locally in-process and returns (default)
            max_reconnect_attempts: Maximum reconnection attempts (distributed mode only)
                                   0 = infinite (default), N = stop after N attempts
            reconnect_max_delay: Maximum delay between reconnection attempts in seconds
                                (distributed mode only, default: 60.0)

        Returns:
            ExecutionResult (local mode only)
            Never returns in distributed mode (runs as server)

        Raises:
            ValueError: If workflow definition is invalid
            ExecutionError: If execution fails
            ConnectionError: If Core is not reachable (distributed mode)

        Example:
            >>> # Local execution (default) - runs and returns
            >>> result = await my_workflow.execute({"user_id": 123})
            >>>
            >>> # Distributed mode - runs as server with logs (blocks)
            >>> await my_workflow.execute({"user_id": 123}, distributed=True)
            >>> # ^ Never returns, keeps running as worker server
            >>>
            >>> # Distributed mode with reconnection limits
            >>> await my_workflow.execute(
            ...     {"user_id": 123},
            ...     distributed=True,
            ...     max_reconnect_attempts=120,  # Stop after ~2 hours
            ...     reconnect_max_delay=60.0
            ... )
            >>>
            >>> # Custom executor (advanced)
            >>> custom_executor = LocalExecutor()
            >>> result = await my_workflow.execute({"user_id": 123}, executor=custom_executor)
        """
        # Build workflow if not already built
        if not self._built_definition:
            self._build()

        # Determine executor
        if executor is None:
            if not distributed:
                # LOCAL MODE: Execute in-process and return
                from .execution import DSLLocalExecutor
                executor = DSLLocalExecutor()
                return await executor.execute(self._built_definition, inputs)
            else:
                # DISTRIBUTED MODE: Run as worker server (blocks)
                await self._run_as_worker_server(
                    inputs,
                    max_reconnect_attempts=max_reconnect_attempts,
                    reconnect_max_delay=reconnect_max_delay
                )
                # Never returns (runs until Ctrl+C)
        else:
            # Custom executor provided
            return await executor.execute(self._built_definition, inputs)

    async def _run_as_worker_server(
        self,
        initial_inputs: Dict[str, Any],
        max_reconnect_attempts: int = 0,
        reconnect_max_delay: float = 60.0
    ) -> None:
        """Run workflow as distributed worker server.

        This mode:
        1. Auto-registers all workflow steps with Core
        2. Submits workflow blueprint to Core
        3. Runs as worker server showing logs
        4. Blocks indefinitely until Ctrl+C

        Args:
            initial_inputs: Initial workflow inputs (used for first execution)
            max_reconnect_attempts: Maximum reconnection attempts (0 = infinite)
            reconnect_max_delay: Maximum delay between reconnection attempts (seconds)
        """
        from ..distributed import Worker, DistributedExecutor
        import uuid

        print("=" * 70)
        print(f"DISTRIBUTED MODE: Running '{self.name}' as worker server")
        print("=" * 70)
        print()
        print(f"📡 Connecting to Core: {self.core_url}")
        print()

        # Create unique worker ID
        worker_id = f"python-{self.name}-{str(uuid.uuid4())[:8]}"

        # Create worker with reconnection configuration
        worker = Worker(
            worker_id=worker_id,
            core_url=self.core_url,
            language="python",
            max_reconnect_attempts=max_reconnect_attempts,
            reconnect_max_delay=reconnect_max_delay,
        )

        # Auto-register all steps from workflow
        print("📝 Auto-registering workflow steps:")
        for step_name, step_meta in self._built_definition.steps_metadata.items():
            worker.register_step(step_name, step_meta.function)
            print(f"   ✅ {step_name}")
        print()

        # Register workflow blueprint
        worker.register_workflow(self._built_definition)

        print("🚀 Submitting initial execution request...")
        print()

        # Submit initial execution request via DistributedExecutor
        try:
            executor = DistributedExecutor(
                core_url=self.core_url,
                worker_id=f"{worker_id}-executor"
            )

            result = await executor.execute(self._built_definition, initial_inputs)

            print(f"✅ Workflow execution submitted: {result.execution_id}")
            print(f"   Status: {result.status}")
            print()

            executor.close()
        except Exception as e:
            print(f"⚠️  Failed to submit initial execution: {e}")
            print()

        # Start worker server (blocks until Ctrl+C)
        print("=" * 70)
        print("WORKER SERVER RUNNING")
        print("=" * 70)
        print()
        print("👷 Worker is now polling for tasks from Core")
        print("📊 You'll see logs below when tasks are received")
        print()
        print("Press Ctrl+C to stop the worker")
        print()

        try:
            # This blocks until Ctrl+C
            await worker.start()
        except KeyboardInterrupt:
            print()
            print("=" * 70)
            print("🛑 Worker server stopped by user")
            print("=" * 70)
        except Exception as e:
            print()
            print("=" * 70)
            print(f"❌ Worker error: {type(e).__name__}: {e}")
            print("=" * 70)
            print()
            print("Make sure Core is running:")
            print(f"   cd ../../ && mix run --no-halt")
            raise

    def validate(self) -> Any:
        """Explicitly validate the workflow.

        Returns:
            ValidationReport with errors and warnings

        Example:
            >>> report = my_workflow.validate()
            >>> if not report.is_valid:
            >>>     print(f"Errors: {report.errors}")
        """
        # Build if not already built (this validates automatically)
        if not self._built_definition:
            self._build()

        # Return cached validation report
        return self._validation_report

    def _build(self) -> None:
        """Build the workflow definition by calling definition function.

        This method creates a WorkflowBuilder, passes it to the user's
        definition function, validates the workflow, serializes it to
        WorkflowDefinition format, and stores the result.

        Raises:
            ValueError: If workflow definition is invalid
        """
        # Import here to avoid circular dependency
        from .builder import WorkflowBuilder
        from .validator import WorkflowValidator
        from .serializer import DSLSerializer

        # Create builder and call user's definition function
        builder = WorkflowBuilder(workflow_name=self.name)
        self.definition_func(builder)

        # Validate the workflow
        validator = WorkflowValidator(
            workflow_name=self.name,
            timeline=builder.get_timeline(),
            diverge_rules=builder.get_diverge_rules(),
            branch_rules=builder.get_branch_rules(),
        )
        validation_report = validator.validate()

        # Store validation report
        self._validation_report = validation_report

        # Raise error if validation failed
        if not validation_report.is_valid:
            raise WorkflowDefinitionError(self.name, validation_report.errors)

        # Serialize to WorkflowDefinition format
        workflow_definition = DSLSerializer.to_workflow_definition(
            workflow_name=self.name,
            builder=builder,
        )

        # Store the built definition
        self._built_definition = workflow_definition

    def __repr__(self) -> str:
        """String representation."""
        return f"WorkflowMetadata(name='{self.name}', core_url='{self.core_url}')"


def step(func: Callable[P, R]) -> StepMetadata:
    """Decorator to mark an async function as a workflow step.

    The decorated function must:
    - Be async
    - Have 'context' as first parameter
    - Return dict with "ok" or "error" key

    Args:
        func: Async function to decorate

    Returns:
        StepMetadata instance

    Raises:
        StepDefinitionError: If function definition is invalid

    Example:
        >>> @step
        >>> async def my_step(context, inputs):
        >>>     result = await process(inputs["data"])
        >>>     return {"ok": result}
    """
    # Validation: Must be async
    if not inspect.iscoroutinefunction(func):
        raise StepDefinitionError(
            func.__name__,
            "Step functions must be async. Use 'async def' to define the function."
        )

    # Extract metadata using inspect
    sig = inspect.signature(func)
    params = list(sig.parameters.keys())

    # First param must be 'context'
    if not params or params[0] != 'context':
        raise StepDefinitionError(
            func.__name__,
            f"First parameter must be 'context'. Got: {params if params else 'no parameters'}\n"
            f"  Example: async def {func.__name__}(context: Context, inputs: dict): ..."
        )

    # Determine dependencies (all params except 'context' and 'inputs')
    has_context = 'context' in params
    has_inputs = 'inputs' in params
    dependencies = [p for p in params if p not in ('context', 'inputs')]

    # Early validation: Check if dependencies exist in registry
    # (Only warn, don't fail - the step might be registered later)
    for dep in dependencies:
        if dep not in StepRegistry.all():
            import warnings
            # Try to find similar names for helpful suggestions
            all_step_names = list(StepRegistry.all().keys())
            suggestions = [s for s in all_step_names if dep.lower() in s.lower() or s.lower() in dep.lower()]

            warning_msg = f"Step '{func.__name__}' depends on '{dep}' which is not yet registered."
            if suggestions:
                warning_msg += f" Did you mean: {suggestions}?"
            warnings.warn(warning_msg, UserWarning, stacklevel=2)

    # Wrap function to auto-convert returns to {"ok": ...} / {"error": ...}
    @functools.wraps(func)
    async def wrapped_function(*args, **kwargs):
        """Wrapper that automatically converts returns to result envelope."""
        try:
            result = await func(*args, **kwargs)

            # If already in envelope format, return as-is
            if isinstance(result, dict) and ("ok" in result or "error" in result):
                return result

            # Auto-wrap in {"ok": ...}
            return {"ok": result}

        except Exception as e:
            # Auto-catch exceptions and convert to {"error": ...}
            return {"error": str(e)}

    # Create metadata
    metadata = StepMetadata(
        name=func.__name__,
        function=wrapped_function,  # Use wrapped version
        parameters=params,
        has_context=has_context,
        has_inputs=has_inputs,
        dependencies=dependencies,
    )

    # Register in global registry
    StepRegistry.register(metadata)

    # Return metadata (not wrapped function)
    # This allows using the step directly in workflow definitions
    return metadata


def workflow(
    func: Optional[Callable] = None,
    *,
    core_url: str = "localhost:9090"
) -> Any:
    """Decorator to mark a function as a workflow definition.

    The decorated function receives a WorkflowBuilder and defines
    the workflow structure using timeline, diverge, and branch methods.

    Args:
        func: Function to decorate (when used without parameters)
        core_url: gRPC URL of Cerebelum Core

    Returns:
        WorkflowMetadata instance

    Raises:
        TypeError: If function is async

    Example:
        >>> @workflow
        >>> def my_workflow(wf):
        >>>     wf.timeline(step1 >> step2 >> step3)
        >>>
        >>> # Or with custom core_url:
        >>> @workflow(core_url="production:9090")
        >>> def my_workflow(wf):
        >>>     wf.timeline(step1 >> step2)
    """
    def decorator(f: Callable) -> WorkflowMetadata:
        # Validation: Must NOT be async
        if inspect.iscoroutinefunction(f):
            raise StepDefinitionError(
                f.__name__,
                "Workflow definition functions must NOT be async. "
                "Remove 'async' keyword from the function definition."
            )

        # Create metadata
        metadata = WorkflowMetadata(
            name=f.__name__,
            definition_func=f,
            core_url=core_url,
        )

        # Register
        WorkflowRegistry.register(metadata)

        return metadata

    # Support both @workflow and @workflow(core_url="...")
    if func is None:
        # Called with parameters: @workflow(core_url="...")
        return decorator
    else:
        # Called without parameters: @workflow
        return decorator(func)
