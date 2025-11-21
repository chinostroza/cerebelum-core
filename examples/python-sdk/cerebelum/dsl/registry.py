"""Global registries for steps and workflows.

Maintains global state for decorated functions to enable workflow composition.
"""

from typing import Dict, Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from .decorators import StepMetadata, WorkflowMetadata


class StepRegistry:
    """Global registry for @step decorated functions.

    This is a class-level registry that stores all steps decorated with @step.
    It enables workflow builders to reference steps by name.
    """

    _steps: Dict[str, "StepMetadata"] = {}

    @classmethod
    def register(cls, step: "StepMetadata") -> None:
        """Register a step in the global registry.

        Args:
            step: StepMetadata instance to register

        Note:
            If a step with the same name already exists, it will be replaced.
            This allows hot-reloading during development.
        """
        cls._steps[step.name] = step

    @classmethod
    def get(cls, name: str) -> Optional["StepMetadata"]:
        """Get a step by name.

        Args:
            name: Name of the step to retrieve

        Returns:
            StepMetadata if found, None otherwise
        """
        return cls._steps.get(name)

    @classmethod
    def all(cls) -> Dict[str, "StepMetadata"]:
        """Get all registered steps.

        Returns:
            Copy of the steps dictionary
        """
        return cls._steps.copy()

    @classmethod
    def clear(cls) -> None:
        """Clear all registered steps.

        This is primarily useful for testing to ensure a clean state
        between test runs.
        """
        cls._steps.clear()


class WorkflowRegistry:
    """Global registry for @workflow decorated functions.

    This is a class-level registry that stores all workflows decorated
    with @workflow.
    """

    _workflows: Dict[str, "WorkflowMetadata"] = {}

    @classmethod
    def register(cls, workflow: "WorkflowMetadata") -> None:
        """Register a workflow in the global registry.

        Args:
            workflow: WorkflowMetadata instance to register

        Note:
            If a workflow with the same name already exists, it will be replaced.
        """
        cls._workflows[workflow.name] = workflow

    @classmethod
    def get(cls, name: str) -> Optional["WorkflowMetadata"]:
        """Get a workflow by name.

        Args:
            name: Name of the workflow to retrieve

        Returns:
            WorkflowMetadata if found, None otherwise
        """
        return cls._workflows.get(name)

    @classmethod
    def all(cls) -> Dict[str, "WorkflowMetadata"]:
        """Get all registered workflows.

        Returns:
            Copy of the workflows dictionary
        """
        return cls._workflows.copy()

    @classmethod
    def clear(cls) -> None:
        """Clear all registered workflows.

        This is primarily useful for testing.
        """
        cls._workflows.clear()
